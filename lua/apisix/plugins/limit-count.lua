local limit_count_new = require("resty.limit.count").new
local core = require("apisix.core")
local plugin_name = "limit-count"


local schema = {
    type = "object",
    properties = {
        count = {type = "integer", minimum = 0},
        time_window = {type = "integer",  minimum = 0},
        key = {type = "string", enum = {"remote_addr"}},
        rejected_code = {type = "integer", minimum = 200},
    },
    required = {"count", "time_window", "key", "rejected_code"}
}


local _M = {
    version = 0.1,
    priority = 1002,        -- TODO: add a type field, may be a good idea
    name = plugin_name,
}


function _M.check_args(conf)
    local ok, err = core.schema.check_args(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


local function create_limit_obj(conf)
    core.log.info("create new limit-count plugin instance")
    return limit_count_new("plugin-limit-count", conf.count, conf.time_window)
end


function _M.access(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)
    local lim, err = core.lrucache.plugin_ctx(plugin_name, ctx,
                                           create_limit_obj, conf)
    if not lim then
        core.log.error("failed to fetch limit.count object: ", err)
        return 500
    end

    local key = ctx.var[conf.key]
    local rejected_code = conf.rejected_code

    local delay, remaining = lim:incoming(key, true)
    if not delay then
        local err = remaining
        if err == "rejected" then
            return rejected_code
        end

        core.log.error("failed to limit req: ", err)
        return 500
    end

    core.response.set_header("X-RateLimit-Limit", conf.count,
                             "X-RateLimit-Remaining", remaining)
end


return _M
