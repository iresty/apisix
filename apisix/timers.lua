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
local process = require("ngx.process")
local pairs = pairs
local unpack = unpack
local thread_spawn = ngx.thread.spawn
local thread_wait = ngx.thread.wait

local check_interval = 0.5

local timers = {}


local _M = {}


local function background_timer()
    local threads = {}
    for name, timer in pairs(timers) do
        core.log.info("run timer[", name, "]")

        local th, err = thread_spawn(timer)
        if not th then
            core.log.error("failed to spawn thread for timer [", name, "]: ", err)
            goto continue
        end

        core.table.insert(threads, th)

::continue::
    end

    local ok, err = thread_wait(unpack(threads))
    if not ok then
        core.log.error("failed to wait threads: ", err)
    end
end


local function is_privileged()
    return process.type() == "privileged agent" or process.type() == "single"
end


function _M.init_worker()
    local opts = {
        check_interval = check_interval,
    }
    local timer, err = core.timer.new("background", background_timer, opts)
    if not timer then
        core.log.error("failed to create background timer: ", err)
        return
    end

    core.log.notice("succeed to create background timer")
end


function _M.register_timer(name, f, privileged)
    if privileged and not is_privileged() then
        return
    end

    timers[name] = f
end


function _M.unregister_timer(name, privileged)
    if privileged and not is_privileged() then
        return
    end

    timers[name] = nil
end


function _M.check_interval()
    return check_interval
end


return _M
