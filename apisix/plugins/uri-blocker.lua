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

local require = require
local core = require("apisix.core")
local re_compile = require("resty.core.regex").re_match_compile
local re_find = ngx.re.find
local ipairs = ipairs

local schema = {
    type = "object",
    properties = {
        block_rules = {
            type = "array",
            items = {
                type = "string",
                minLength = 1,
                maxLength = 4096,
            },
            uniqueItems = true
        },
        rejected_code = {
            type = "integer",
            minimum = 200,
            default = 403
        },
    },
    required = {"block_rules"},
}


local plugin_name = "uri-blocker"

local _M = {
    version = 0.1,
    priority = 2900,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    for i, re_rule in ipairs(conf.block_rules) do
        local ok, err = re_compile(re_rule, "j")
        -- core.log.warn("ok: ", tostring(ok), " err: ", tostring(err),
        --               " re_rule: ", re_rule)
        if not ok then
            return false, err
        end
    end

    return true
end


function _M.rewrite(conf, ctx)
    core.log.info("uri: ", ctx.var.request_uri)
    core.log.info("block uri rules: ", conf.block_rules_concat)

    if not conf.block_rules_concat then
        local block_rules = {}
        for i, re_rule in ipairs(conf.block_rules) do
            block_rules[i] = re_rule
        end

        conf.block_rules_concat = core.table.concat(block_rules, "|")
        core.log.info("concat block_rules: ", conf.block_rules_concat)
    end

    local from = re_find(ctx.var.request_uri, conf.block_rules_concat, "jo")
    if from then
        return conf.rejected_code
    end
end


return _M
