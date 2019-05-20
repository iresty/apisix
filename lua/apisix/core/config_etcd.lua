-- Copyright (C) Yuansheng Wang

local core = require("apisix.core")
local etcd = require("resty.etcd")
local new_tab = require("table.new")
local json_encode = require("cjson.safe").encode
local exiting = ngx.worker.exiting
local insert_tab = table.insert
local type = type
local ipairs = ipairs
local setmetatable = setmetatable
local ngx_sleep = ngx.sleep
local ngx_timer_at = ngx.timer.at
local sub_str = string.sub


local _M = {version = 0.1}
local mt = {__index = _M}


local function readdir(etcd_cli, key)
    if not etcd_cli then
        return nil, "not inited"
    end

    local data, err = etcd_cli:readdir(key, true)
    if not data then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    local body = data.body

    if type(body) ~= "table" then
        return nil, "failed to read etcd dir"
    end

    if body.message then
        return nil, body.message
    end

    return body.node
end

local function waitdir(etcd_cli, key, modified_index)
    if not etcd_cli then
        return nil, "not inited"
    end

    local data, err = etcd_cli:waitdir(key, modified_index)
    if not data then
        -- log.error("failed to get key from etcd: ", err)
        return nil, err
    end

    local body = data.body or {}

    if body.message then
        return nil, body.message
    end

    return body.node
end


local function short_key(self, str)
    return sub_str(str, #self.key + 2)
end


function _M.fetch(self)
    if self.values == nil then
        local dir_res, err = readdir(self.etcd_cli, self.key)
        if not dir_res then
            return nil, err
        end

        if not dir_res.dir then
            return nil, self.key .. " is not a dir"
        end

        self.values = new_tab(#dir_res.nodes, 0)
        self.values_hash = new_tab(0, #dir_res.nodes)

        for _, item in ipairs(dir_res.nodes) do
            insert_tab(self.values, item)
            local key = short_key(self, item.key)
            self.values_hash[key] = #self.values

            if not self.prev_index or item.modifiedIndex > self.prev_index then
                self.prev_index = item.modifiedIndex
            end
        end

        return self.values
    end

    local dir_res, err = waitdir(self.etcd_cli, self.key, self.prev_index + 1)
    if not dir_res then
        return nil, err
    end

    if dir_res.dir then
        core.log.error("todo: support for parsing `dir` response structures. ",
                       json_encode(dir_res))
        return self.values
    end
    -- log.warn("waitdir: ", require("cjson").encode(dir_res))

    if not self.prev_index or dir_res.modifiedIndex > self.prev_index then
        self.prev_index = dir_res.modifiedIndex
    end

    local key = short_key(self, dir_res.key)
    local pre_index = self.values_hash[key]
    if pre_index then
        if dir_res.value then
            self.values[pre_index] = dir_res

        else
            self.values[pre_index] = false
        end

        return self.values
    end

    if dir_res.value then
        insert_tab(self.values, dir_res)
        self.values_hash[key] = #self.values
    end

    -- avoid space waste
    self.sync_times = self.sync_times + 1
    if self.sync_times > 100 then
        local idx = 0
        for i = 1, #self.values do
            local val = self.values[i]
            self.values[i] = nil
            if val then
                idx = idx + 1
                self.values[idx] = val
            end
        end

        for i = 1, #self.values do
            key = short_key(self, self.values[i].key)
            self.values_hash[key] = i
        end
    end

    return self.values
end


function _M.get(self, key)
    local arr_idx = self.values_hash[tostring(key)]
    if not arr_idx then
        return nil
    end

    return self.values[arr_idx]
end


local function _automatic_fetch(premature, self)
    if premature then
        return
    end

    while not exiting() do
        local ok, err = pcall(self.fetch, self)
        if not ok then
            core.log.error("failed to fetch data from etcd: ", err)
            ngx_sleep(10)
        end
    end
end


function _M.new(key, opts)
    if not key then
        return nil, "missing `key` argument"
    end

    local local_conf, err = core.config.local_conf()
    if not local_conf then
        return nil, err
    end

    local etcd_cli
    etcd_cli, err = etcd.new(local_conf.etcd)
    if not etcd_cli then
        return nil, err
    end

    local automatic = opts and opts.automatic

    local obj = setmetatable({
        etcd_cli = etcd_cli,
        values = nil,
        routes_hash = nil,
        prev_index = nil,
        key = key,
        automatic = automatic,
        sync_times = 0,
    }, mt)

    if automatic then
        ngx_timer_at(0, _automatic_fetch, obj)
    end

    return obj
end


return _M
