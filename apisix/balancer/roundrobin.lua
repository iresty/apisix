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
local roundrobin  = require("resty.roundrobin")
local core = require("apisix.core")
local nkeys = core.table.nkeys


local _M = {}


function _M.new(up_nodes, upstream)
    local picker = roundrobin:new(up_nodes)
    local nodes_count = nkeys(up_nodes)
    return {
        upstream = upstream,
        get = function (ctx)
            if ctx.balancer_tried_servers and ctx.balancer_tried_servers_count == nodes_count then
                return nil, "all upstream servers tried"
            end

            local server, err
            while true do
                server, err = picker:find()
                if not server then
                    return nil, err
                end
                if ctx.balancer_tried_servers then
                    if not ctx.balancer_tried_servers[server] then
                        break
                    end
                else
                    break
                end
            end

            return server
        end,
        after_balance = function (ctx, before_retry)
            if not before_retry then
                if ctx.balancer_tried_servers then
                    core.tablepool.release("balancer_tried_servers", ctx.balancer_tried_servers)
                    ctx.balancer_tried_servers = nil
                end

                return nil
            end

            if not ctx.balancer_tried_servers then
                ctx.balancer_tried_servers = core.tablepool.fetch("balancer_tried_servers", 0, 2)
            end

            ctx.balancer_tried_servers[ctx.balancer_server] = true
            ctx.balancer_tried_servers_count = (ctx.balancer_tried_servers_count or 0) + 1
        end
    }
end


return _M
