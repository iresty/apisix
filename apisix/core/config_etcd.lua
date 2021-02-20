--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local require      = require
local table        = require("apisix.core.table")
local config_local = require("apisix.core.config_local")
local log          = require("apisix.core.log")
local json         = require("apisix.core.json")
local etcd_apisix  = require("apisix.core.etcd")
local etcd         = require("resty.etcd")
local new_tab      = require("table.new")
local clone_tab    = require("table.clone")
local check_schema = require("apisix.core.schema").check
local exiting      = ngx.worker.exiting
local insert_tab   = table.insert
local type         = type
local ipairs       = ipairs
local setmetatable = setmetatable
local ngx_sleep    = require("apisix.core.utils").sleep
local ngx_timer_at = ngx.timer.at
local ngx_time     = ngx.time
local sub_str      = string.sub
local tostring     = tostring
local tonumber     = tonumber
local xpcall       = xpcall
local debug        = debug
local error        = error
local rand         = math.random
local created_obj  = {}


local _M = {
    version = 0.3,
    local_conf = config_local.local_conf,
    clear_local_cache = config_local.clear_cache,
}


local mt = {
    __index = _M,
    __tostring = function(self)
        return " etcd key: " .. self.key
    end
}


local function getkey(etcd_cli, key)
    if not etcd_cli then
        return nil, "not inited"
    end

    local res, err = etcd_cli:readdir(key)
    if not res then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    if type(res.body) ~= "table" then
        return nil, "failed to get key from etcd"
    end

    res, err = etcd_apisix.get_format(res, key, true)
    if not res then
        return nil, err
    end

    return res
end


local function readdir(etcd_cli, key)
    if not etcd_cli then
        return nil, "not inited"
    end

    local res, err = etcd_cli:readdir(key)
    if not res then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    if type(res.body) ~= "table" then
        return nil, "failed to read etcd dir"
    end

    res, err = etcd_apisix.get_format(res, key .. '/', true)
    if not res then
        return nil, err
    end

    return res
end

local function waitdir(etcd_cli, key, modified_index, timeout)
    if not etcd_cli then
        return nil, nil, "not inited"
    end

    local opts = {}
    opts.start_revision = modified_index
    opts.timeout = timeout
    opts.need_cancel = true
    local res_func, func_err, http_cli = etcd_cli:watchdir(key, opts)
    if not res_func then
        return nil, func_err
    end

    -- in etcd v3, the 1st res of watch is watch info, useless to us.
    -- try twice to skip create info
    local res, err = res_func()
    if not res or not res.result or not res.result.events then
        res, err = res_func()
    end

    if http_cli then
        local res_cancel, err_cancel = etcd_cli:watchcancel(http_cli)
        if res_cancel == 1 then
            log.info("cancel watch connection success")
        else
            log.error("cancel watch failed: ", err_cancel)
        end
    end

    if not res then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    if type(res.result) ~= "table" then
        return nil, "failed to wait etcd dir"
    end
    return etcd_apisix.watch_format(res)
end


local function short_key(self, str)
    return sub_str(str, #self.key + 2)
end


function _M.upgrade_version(self, new_ver)
    new_ver = tonumber(new_ver)
    if not new_ver then
        return
    end

    local pre_index = self.prev_index

    if new_ver <= pre_index then
        return
    end

    self.prev_index = new_ver
    return
end


local function sync_data(self)
    if not self.key then
        return nil, "missing 'key' arguments"
    end

    if self.need_reload then
        local res, err = readdir(self.etcd_cli, self.key)
        if not res then
            return false, err
        end

        local dir_res, headers = res.body.node or {}, res.headers
        log.debug("readdir key: ", self.key, " res: ",
                  json.delay_encode(dir_res))
        if not dir_res then
            return false, err
        end

        if self.values then
            for i, val in ipairs(self.values) do
                if val and val.clean_handlers then
                    for _, clean_handler in ipairs(val.clean_handlers) do
                        clean_handler(val)
                    end
                    val.clean_handlers = nil
                end
            end

            self.values = nil
            self.values_hash = nil
        end

        local changed = false

        if self.single_item then
            self.values = new_tab(1, 0)
            self.values_hash = new_tab(0, 1)

            local item = dir_res
            local data_valid = item.value ~= nil

            if data_valid and self.item_schema then
                data_valid, err = check_schema(self.item_schema, item.value)
                if not data_valid then
                    log.error("failed to check item data of [", self.key,
                              "] err:", err, " ,val: ", json.encode(item.value))
                end
            end

            if data_valid and self.checker then
                data_valid, err = self.checker(item.value)
                if not data_valid then
                    log.error("failed to check item data of [", self.key,
                              "] err:", err, " ,val: ", json.delay_encode(item.value))
                end
            end

            if data_valid then
                changed = true
                insert_tab(self.values, item)
                self.values_hash[self.key] = #self.values

                item.clean_handlers = {}

                if self.filter then
                    self.filter(item)
                end
            end

            self:upgrade_version(item.modifiedIndex)

        else
            if not dir_res.nodes then
                dir_res.nodes = {}
            end

            self.values = new_tab(#dir_res.nodes, 0)
            self.values_hash = new_tab(0, #dir_res.nodes)

            for _, item in ipairs(dir_res.nodes) do
                local key = short_key(self, item.key)
                local data_valid = true
                if type(item.value) ~= "table" then
                    data_valid = false
                    log.error("invalid item data of [", self.key .. "/" .. key,
                              "], val: ", item.value,
                              ", it should be an object")
                end

                if data_valid and self.item_schema then
                    data_valid, err = check_schema(self.item_schema, item.value)
                    if not data_valid then
                        log.error("failed to check item data of [", self.key,
                                  "] err:", err, " ,val: ", json.encode(item.value))
                    end
                end

                if data_valid and self.checker then
                    data_valid, err = self.checker(item.value)
                    if not data_valid then
                        log.error("failed to check item data of [", self.key,
                                  "] err:", err, " ,val: ", json.delay_encode(item.value))
                    end
                end

                if data_valid then
                    changed = true
                    insert_tab(self.values, item)
                    self.values_hash[key] = #self.values

                    item.value.id = key
                    item.clean_handlers = {}

                    if self.filter then
                        self.filter(item)
                    end
                end

                self:upgrade_version(item.modifiedIndex)
            end
        end

        if headers then
            self:upgrade_version(headers["X-Etcd-Index"])
        end

        if changed then
            self.conf_version = self.conf_version + 1
        end

        self.need_reload = false
        return true
    end

    local dir_res, err = waitdir(self.etcd_cli, self.key, self.prev_index + 1, self.timeout)
    log.info("waitdir key: ", self.key, " prev_index: ", self.prev_index + 1)
    log.info("res: ", json.delay_encode(dir_res, true))

    if not dir_res then
        if err == "compacted" then
            self.need_reload = true
            log.warn("waitdir [", self.key, "] err: ", err,
                     ", will read the configuration again via readdir")
            return false
        end

        return false, err
    end

    local res = dir_res.body.node
    local err_msg = dir_res.body.message
    if err_msg then
        return false, err
    end

    if not res then
        return false, err
    end

    local res_copy = res
    -- waitdir will return [res] even for self.single_item = true
    for _, res in ipairs(res_copy) do
        local key
        if self.single_item then
            key = self.key
        else
            key = short_key(self, res.key)
        end

        if res.value and not self.single_item and type(res.value) ~= "table" then
            self:upgrade_version(res.modifiedIndex)
            return false, "invalid item data of [" .. self.key .. "/" .. key
                            .. "], val: " .. res.value
                            .. ", it should be an object"
        end

        if res.value and self.item_schema then
            local ok, err = check_schema(self.item_schema, res.value)
            if not ok then
                self:upgrade_version(res.modifiedIndex)

                return false, "failed to check item data of ["
                                .. self.key .. "] err:" .. err
            end

            if self.checker then
                local ok, err = self.checker(res.value)
                if not ok then
                    self:upgrade_version(res.modifiedIndex)

                    return false, "failed to check item data of ["
                                    .. self.key .. "] err:" .. err
                end
            end
        end

        self:upgrade_version(res.modifiedIndex)

        if res.dir then
            if res.value then
                return false, "todo: support for parsing `dir` response "
                                .. "structures. " .. json.encode(res)
            end
            return false
        end

        local pre_index = self.values_hash[key]
        if pre_index then
            local pre_val = self.values[pre_index]
            if pre_val and pre_val.clean_handlers then
                for _, clean_handler in ipairs(pre_val.clean_handlers) do
                    clean_handler(pre_val)
                end
                pre_val.clean_handlers = nil
            end

            if res.value then
                if not self.single_item then
                    res.value.id = key
                end

                self.values[pre_index] = res
                res.clean_handlers = {}
                log.info("update data by key: ", key)

            else
                self.sync_times = self.sync_times + 1
                self.values[pre_index] = false
                self.values_hash[key] = nil
                log.info("delete data by key: ", key)
            end

        elseif res.value then
            res.clean_handlers = {}
            insert_tab(self.values, res)
            self.values_hash[key] = #self.values
            if not self.single_item then
                res.value.id = key
            end

            log.info("insert data by key: ", key)
        end

        -- avoid space waste
        if self.sync_times > 100 then
            local values_original = table.clone(self.values)
            table.clear(self.values)

            for i = 1, #values_original do
                local val = values_original[i]
                if val then
                    table.insert(self.values, val)
                end
            end

            table.clear(self.values_hash)
            log.info("clear stale data in `values_hash` for key: ", key)

            for i = 1, #self.values do
                key = short_key(self, self.values[i].key)
                self.values_hash[key] = i
            end

            self.sync_times = 0
        end

        -- /plugins' filter need to known self.values when it is called
        -- so the filter should be called after self.values set.
        if self.filter then
            self.filter(res)
        end

        self.conf_version = self.conf_version + 1
    end

    return self.values
end


function _M.get(self, key)
    if not self.values_hash then
        return
    end

    local arr_idx = self.values_hash[tostring(key)]
    if not arr_idx then
        return nil
    end

    return self.values[arr_idx]
end


function _M.getkey(self, key)
    if not self.running then
        return nil, "stopped"
    end

    return getkey(self.etcd_cli, key)
end


local get_etcd
do
    local etcd_cli

    function get_etcd()
        if etcd_cli ~= nil then
            return etcd_cli
        end

        local local_conf, err = config_local.local_conf()
        if not local_conf then
            return nil, err
        end

        local etcd_conf = clone_tab(local_conf.etcd)
        etcd_conf.http_host = etcd_conf.host
        etcd_conf.host = nil
        etcd_conf.prefix = nil
        etcd_conf.protocol = "v3"
        etcd_conf.api_prefix = "/v3"

        -- default to verify etcd cluster certificate
        etcd_conf.ssl_verify = true
        if etcd_conf.tls and etcd_conf.tls.verify == false then
            etcd_conf.ssl_verify = false
        end

        local err
        etcd_cli, err = etcd.new(etcd_conf)
        return etcd_cli, err
    end
end


local function _automatic_fetch(premature, self)
    if premature then
        return
    end

    local i = 0
    while not exiting() and self.running and i <= 32 do
        i = i + 1

        local ok, err = xpcall(function()
            if not self.etcd_cli then
                local etcd_cli, err = get_etcd()
                if not etcd_cli then
                    error("failed to create etcd instance for key ["
                          .. self.key .. "]: " .. (err or "unknown"))
                end
                self.etcd_cli = etcd_cli
            end

            local ok, err = sync_data(self)
            if err then
                if err ~= "timeout" and err ~= "Key not found"
                    and self.last_err ~= err then
                    log.error("failed to fetch data from etcd: ", err, ", ",
                              tostring(self))
                end

                if err ~= self.last_err then
                    self.last_err = err
                    self.last_err_time = ngx_time()
                else
                    if ngx_time() - self.last_err_time >= 30 then
                        self.last_err = nil
                    end
                end

                ngx_sleep(self.resync_delay + rand() * 0.5 * self.resync_delay)
            elseif not ok then
                -- no error. reentry the sync with different state
                ngx_sleep(0.05)
            end

        end, debug.traceback)

        if not ok then
            log.error("failed to fetch data from etcd: ", err, ", ",
                      tostring(self))
            ngx_sleep(self.resync_delay + rand() * 0.5 * self.resync_delay)
            break
        end
    end

    if not exiting() and self.running then
        ngx_timer_at(0, _automatic_fetch, self)
    end
end


function _M.new(key, opts)
    local local_conf, err = config_local.local_conf()
    if not local_conf then
        return nil, err
    end

    local etcd_conf = local_conf.etcd
    local prefix = etcd_conf.prefix
    local resync_delay = etcd_conf.resync_delay
    if not resync_delay or resync_delay < 0 then
        resync_delay = 5
    end

    local automatic = opts and opts.automatic
    local item_schema = opts and opts.item_schema
    local filter_fun = opts and opts.filter
    local timeout = opts and opts.timeout
    local single_item = opts and opts.single_item
    local checker = opts and opts.checker

    local obj = setmetatable({
        etcd_cli = nil,
        key = key and prefix .. key,
        automatic = automatic,
        item_schema = item_schema,
        checker = checker,
        sync_times = 0,
        running = true,
        conf_version = 0,
        values = nil,
        need_reload = true,
        routes_hash = nil,
        prev_index = 0,
        last_err = nil,
        last_err_time = nil,
        resync_delay = resync_delay,
        timeout = timeout,
        single_item = single_item,
        filter = filter_fun,
    }, mt)

    if automatic then
        if not key then
            return nil, "missing `key` argument"
        end

        ngx_timer_at(0, _automatic_fetch, obj)

    else
        local etcd_cli, err = get_etcd()
        if not etcd_cli then
            return nil, "failed to start a etcd instance: " .. err
        end
        obj.etcd_cli = etcd_cli
    end

    if key then
        created_obj[key] = obj
    end

    return obj
end


function _M.close(self)
    self.running = false
end


function _M.fetch_created_obj(key)
    return created_obj[key]
end


local function read_etcd_version(etcd_cli)
    if not etcd_cli then
        return nil, "not inited"
    end

    local data, err = etcd_cli:version()
    if not data then
        return nil, err
    end

    local body = data.body
    if type(body) ~= "table" then
        return nil, "failed to read response body when try to fetch etcd "
                    .. "version"
    end

    return body
end


function _M.server_version(self)
    if not self.running then
        return nil, "stopped"
    end

    return read_etcd_version(self.etcd_cli)
end


return _M
