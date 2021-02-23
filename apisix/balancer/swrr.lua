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
local core = require("apisix.core")
local nkeys = core.table.nkeys
local pairs = pairs
local next = next
local _M = {}

local function find(self, tried)
    local number = #self.nodes
    if number == 1 then
        return self.nodes[1].host
    end
    local best, peer, skip
    local total = 0
    for i = 1, number do
        peer = self.nodes[i]
        skip = tried and tried[peer.host]
        if not skip then
            peer.current_weight = peer.current_weight + peer.weight
            total = total + peer.weight

            if best == nil or peer.current_weight > best.current_weight then
                best = peer
            end
        end
    end
    if best then
        best.current_weight = best.current_weight - total
        return best.host
    else
        return nil, "all upstream servers tried"
    end
end


local function swrr(nodes)
    if not nodes
      or not next(nodes) then
        return nil,"empty nodes"
    end

    local newnodes = {}
    for host, weight in pairs(nodes) do
        core.table.insert(newnodes, {
            host = host,
            weight = weight,
            current_weight = 0,
        })
    end

    local self = {
        nodes = newnodes,
        find = find
    }
    return self
end


function _M.new(up_nodes, upstream)
    local picker, err = swrr(up_nodes)
    if not picker then
        return nil, err
    end
    local nodes_count = nkeys(up_nodes)
    return {
        upstream = upstream,
        get = function (ctx)
            if ctx.balancer_tried_servers and ctx.balancer_tried_servers_count == nodes_count then
                return nil, "all upstream servers tried"
            end

            return picker:find( ctx.balancer_tried_servers)
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
