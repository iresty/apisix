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

local require        = require
local config_local   = require("apisix.core.config_local")
local core_str       = require("apisix.core.string")
local table          = require("apisix.core.table")
local json           = require("apisix.core.json")
local log            = require("apisix.core.log")
local string         = require("apisix.core.string")
local ngx_re         = require("ngx.re")
local dns_client     = require("resty.dns.client")
local ipmatcher      = require("resty.ipmatcher")
local ffi            = require("ffi")
local base           = require("resty.core.base")
local open           = io.open
local math           = math
local sub_str        = string.sub
local str_byte       = string.byte
local tonumber       = tonumber
local tostring       = tostring
local re_gsub        = ngx.re.gsub
local type           = type
local io_popen       = io.popen
local C              = ffi.C
local ffi_string     = ffi.string
local get_string_buf = base.get_string_buf
local exiting        = ngx.worker.exiting
local ngx_sleep      = ngx.sleep

local hostname
local dns_resolvers
local current_inited_resolvers
local max_sleep_interval = 1

ffi.cdef[[
    int ngx_escape_uri(char *dst, const char *src,
        size_t size, int type);
]]


local _M = {
    version = 0.2,
    parse_ipv4 = ipmatcher.parse_ipv4,
    parse_ipv6 = ipmatcher.parse_ipv6,
}


function _M.get_seed_from_urandom()
    local frandom, err = open("/dev/urandom", "rb")
    if not frandom then
        return nil, 'failed to open /dev/urandom: ' .. err
    end

    local str = frandom:read(8)
    frandom:close()
    if not str then
        return nil, 'failed to read data from /dev/urandom'
    end

    local seed = 0
    for i = 1, 8 do
        seed = 256 * seed + str:byte(i)
    end

    return seed
end


function _M.split_uri(uri)
    return ngx_re.split(uri, "/")
end


local function dns_parse(domain)
    if dns_resolvers ~= current_inited_resolvers then
        local local_conf = config_local.local_conf()
        local valid = table.try_read_attr(local_conf, "apisix", "dns_resolver_valid")

        local opts = {
            ipv6 = true,
            nameservers = table.clone(dns_resolvers),
            retrans = 5,  -- 5 retransmissions on receive timeout
            timeout = 2000,  -- 2 sec
            order = {"last", "A", "AAAA", "CNAME"}, -- avoid querying SRV (we don't support it yet)
            validTtl = valid,
        }
        local ok, err = dns_client.init(opts)
        if not ok then
            return nil, "failed to init the dns client: " .. err
        end

        current_inited_resolvers = dns_resolvers
    end

    -- this function will dereference the CNAME records
    local answers, err = dns_client.resolve(domain)
    if not answers then
        return nil, "failed to query the DNS server: " .. err
    end

    if answers.errcode then
        return nil, "server returned error code: " .. answers.errcode
                    .. ": " .. answers.errstr
    end

    local idx = math.random(1, #answers)
    local answer = answers[idx]
    local dns_type = answer.type
    if dns_type == dns_client.TYPE_A or dns_type == dns_client.TYPE_AAAA then
        log.info("dns resolve ", domain, ", result: ", json.delay_encode(answer))
        return table.deepcopy(answer)
    end

    return nil, "unsupport DNS answer"
end
_M.dns_parse = dns_parse


function _M.set_resolver(resolvers)
    dns_resolvers = resolvers
end


function _M.get_resolver(resolvers)
    return dns_resolvers
end


local function rfind_char(s, ch, idx)
    local b = str_byte(ch)
    for i = idx or #s, 1, -1 do
        if str_byte(s, i, i) == b then
            return i
        end
    end
    return nil
end


-- parse_addr parses 'addr' into the host and the port parts. If the 'addr'
-- doesn't have a port, 80 is used to return. For malformed 'addr', the entire
-- 'addr' is returned as the host part. For IPv6 literal host, like [::1],
-- the square brackets will be kept.
function _M.parse_addr(addr)
    local default_port = 80
    if str_byte(addr, 1) == str_byte("[") then
        -- IPv6 format
        local right_bracket = str_byte("]")
        local len = #addr
        if str_byte(addr, len) == right_bracket then
            -- addr in [ip:v6] format
            return addr, default_port
        else
            local pos = rfind_char(addr, ":", #addr - 1)
            if not pos or str_byte(addr, pos - 1) ~= right_bracket then
                -- malformed addr
                return addr, default_port
            end

            -- addr in [ip:v6]:port format
            local host = sub_str(addr, 1, pos - 1)
            local port = sub_str(addr, pos + 1)
            return host, tonumber(port)
        end

    else
        -- IPv4 format
        local pos = rfind_char(addr, ":", #addr - 1)
        if not pos then
            return addr, default_port
        end

        local host = sub_str(addr, 1, pos - 1)
        local port = sub_str(addr, pos + 1)
        return host, tonumber(port)
    end
end


function _M.uri_safe_encode(uri)
    local count_escaped = C.ngx_escape_uri(nil, uri, #uri, 0)
    local len = #uri + 2 * count_escaped
    local buf = get_string_buf(len)
    C.ngx_escape_uri(buf, uri, #uri, 0)

    return ffi_string(buf, len)
end


function _M.validate_header_field(field)
    for i = 1, #field do
        local b = str_byte(field, i, i)
        -- '!' - '~', excluding ':'
        if not (32 < b and b < 127) or b == 58 then
            return false
        end
    end
    return true
end


function _M.validate_header_value(value)
    if type(value) ~= "string" then
        return true
    end

    for i = 1, #value do
        local b = str_byte(value, i, i)
        -- control characters
        if b < 32 or b >= 127 then
            return false
        end
    end
    return true
end


-- only use this method in init/init_worker phase.
function _M.gethostname()
    if hostname then
        return hostname
    end

    local hd = io_popen("/bin/hostname")
    local data, err = hd:read("*a")
    if err == nil then
        hostname = data
        if string.has_suffix(hostname, "\r\n") then
            hostname = sub_str(hostname, 1, -3)
        elseif string.has_suffix(hostname, "\n") then
            hostname = sub_str(hostname, 1, -2)
        end

    else
        hostname = "unknown"
        log.error("failed to read output of \"/bin/hostname\": ", err)
    end

    return hostname
end


local function sleep(sec)
    if sec <= max_sleep_interval then
        return ngx_sleep(sec)
    end
    ngx_sleep(max_sleep_interval)
    if exiting() then
        return
    end
    sec = sec - max_sleep_interval
    return sleep(sec)
end


_M.sleep = sleep


local resolve_var
do
    local _ctx
    local pat = [[(?<!\\)\$\{?(\w+)\}?]]

    local function resolve(m)
        local v = _ctx[m[1]]
        if v == nil then
            return ""
        end
        return tostring(v)
    end

    function resolve_var(tpl, ctx)
        if not tpl then
            return tpl
        end

        local from = core_str.find(tpl, "$")
        if not from then
            return tpl
        end

        -- avoid creating temporary function
        _ctx = ctx
        local res, _, err = re_gsub(tpl, pat, resolve, "jo")
        _ctx = nil
        if not res then
            return nil, err
        end

        return res
    end
end
-- Resolve ngx.var in the given string
_M.resolve_var = resolve_var


return _M
