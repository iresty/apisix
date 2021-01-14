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
local core      = require("apisix.core")
local http      = require "resty.http"
local sub_str   = string.sub
local type      = type
local ngx       = ngx
local plugin_name = "authz-keycloak"

local log = core.log

local schema = {
    type = "object",
    properties = {
        discovery = {type = "string", minLength = 1, maxLength = 4096},
        token_endpoint = {type = "string", minLength = 1, maxLength = 4096},
        permissions = {
            type = "array",
            items = {
                type = "string",
                minLength = 1, maxLength = 100
            },
            uniqueItems = true
        },
        grant_type = {
            type = "string",
            default="urn:ietf:params:oauth:grant-type:uma-ticket",
            enum = {"urn:ietf:params:oauth:grant-type:uma-ticket"},
            minLength = 1, maxLength = 100
        },
        timeout = {type = "integer", minimum = 1000, default = 3000},
        policy_enforcement_mode = {
            type = "string",
            enum = {"ENFORCING", "PERMISSIVE"},
            default = "ENFORCING"
        },
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool = {type = "integer", minimum = 1, default = 5},
        ssl_verify = {type = "boolean", default = true},
        client_id = {type = "string", minLength = 1, maxLength = 100},
        client_secret = {type = "string", minLength = 1, maxLength = 100},
    },
    anyOf = {
        {required = {"discovery"}},
        {required = {"token_endpoint"}}}
}


local _M = {
    version = 0.1,
    priority = 2000,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


-- Some auxiliary functions below heavily inspired by the excellent
-- lua-resty-openidc module; see https://github.com/zmartzone/lua-resty-openidc


-- Retrieve value from server-wide cache, if available.
local function authz_keycloak_cache_get(type, key)
  local dict = ngx.shared[type]
  local value
  if dict then
    value = dict:get(key)
    if value then log.debug("cache hit: type=", type, " key=", key) end
  end
  return value
end


-- Set value in server-wide cache, if available.
local function authz_keycloak_cache_set(type, key, value, exp)
  local dict = ngx.shared[type]
  if dict and (exp > 0) then
    local success, err, forcible = dict:set(key, value, exp)
    if err then
        log.error("cache set: success=", success, " err=", err, " forcible=", forcible)
    else
        log.debug("cache set: success=", success, " err=", err, " forcible=", forcible)
    end
  end
end


-- Configure timeouts.
local function authz_keycloak_configure_timeouts(httpc, timeout)
  if timeout then
    if type(timeout) == "table" then
      httpc:set_timeouts(timeout.connect or 0, timeout.send or 0, timeout.read or 0)
    else
      httpc:set_timeout(timeout)
    end
  end
end


-- Set outgoing proxy options.
local function authz_keycloak_configure_proxy(httpc, proxy_opts)
  if httpc and proxy_opts and type(proxy_opts) == "table" then
    log.debug("authz_keycloak_configure_proxy : use http proxy")
    httpc:set_proxy_options(proxy_opts)
  else
    log.debug("authz_keycloak_configure_proxy : don't use http proxy")
  end
end


-- Parse the JSON result from a call to the OP.
local function authz_keycloak_parse_json_response(response)
  local err
  local res

  -- Check the response from the OP.
  if response.status ~= 200 then
    err = "response indicates failure, status=" .. response.status .. ", body=" .. response.body
  else
    -- Decode the response and extract the JSON object.
    res, err = core.json.decode(response.body)

    if not res then
      err = "JSON decoding failed: " .. err
    end
  end

  return res, err
end


local function decorate_request(http_request_decorator, req)
  return http_request_decorator and http_request_decorator(req) or req
end


-- Get the Discovery metadata from the specified URL.
local function authz_keycloak_discover(url, ssl_verify, keepalive, timeout,
                                       exptime, proxy_opts, http_request_decorator)
  log.debug("authz_keycloak_discover: URL is: " .. url)

  local json, err
  local v = authz_keycloak_cache_get("discovery", url)
  if not v then

    log.debug("Discovery data not in cache, making call to discovery endpoint.")
    -- Make the call to the discovery endpoint.
    local httpc = http.new()
    authz_keycloak_configure_timeouts(httpc, timeout)
    authz_keycloak_configure_proxy(httpc, proxy_opts)
    local res, error = httpc:request_uri(url, decorate_request(http_request_decorator, {
      ssl_verify = (ssl_verify ~= "no"),
      keepalive = (keepalive ~= "no")
    }))
    if not res then
      err = "Accessing discovery url (" .. url .. ") failed: " .. error
      log.error(err)
    else
      log.debug("response data: " .. res.body)
      json, err = authz_keycloak_parse_json_response(res)
      if json then
        authz_keycloak_cache_set("discovery", url, core.json.encode(json), exptime or 24 * 60 * 60)
      else
        err = "could not decode JSON from Discovery data" .. (err and (": " .. err) or '')
        log.error(err)
      end
    end

  else
    json = core.json.decode(v)
  end

  return json, err
end


-- Turn a discovery url set in the opts dictionary into the discovered information.
local function authz_keycloak_ensure_discovered_data(opts)
  local err
  if type(opts.discovery) == "string" then
    local discovery
    discovery, err = authz_keycloak_discover(opts.discovery, opts.ssl_verify, opts.keepalive,
                                             opts.timeout, opts.jwk_expires_in, opts.proxy_opts,
                                             opts.http_request_decorator)
    if not err then
      opts.discovery = discovery
    end
  end
  return err
end


local function authz_keycloak_get_endpoint(conf, endpoint)
    if conf and conf[endpoint] then
        return conf[endpoint]
    elseif conf and conf.discovery and type(conf.discovery) == "table" then
        return conf.discovery[endpoint]
    end

    return nil
end


local function authz_keycloak_get_token_endpoint(conf)
    return authz_keycloak_get_endpoint(conf, "token_endpoint")
end


-- computes access_token expires_in value (in seconds)
local function authz_keycloak_access_token_expires_in(opts, expires_in)
  return (expires_in or opts.access_token_expires_in or 300)
         - 1 - (opts.access_token_expires_leeway or 0)
end


-- computes refresh_token expires_in value (in seconds)
local function authz_keycloak_refresh_token_expires_in(opts, expires_in)
  return (expires_in or opts.refresh_token_expires_in or 3600)
         - 1 - (opts.refresh_token_expires_leeway or 0)
end


local function authz_keycloak_ensure_sa_access_token(conf)
    local token_endpoint = authz_keycloak_get_token_endpoint(conf)

    if not token_endpoint then
      log.error("Unable to determine token endpoint.")
      return 500, "Unable to determine token endpoint."
    end

    local session = authz_keycloak_cache_get("access_tokens", token_endpoint .. ":" .. conf.client_id)

    if session then
        local current_time = ngx.time()

        if current_time < session.access_token_expiration then
            -- Access token is still valid.
            log.debug("Access token is still valid.")
            return session.access_token
        else
            -- Access token has expired.
            log.debug("Access token has expired.")
            if session.refresh_token and (not session.refresh_token_expiration or current_time < refresh_token_expiration) then
                -- Try to get a new access token, using the refresh token.
                log.debug("Trying to get new access token using refresh token.")

                local httpc = http.new()
                httpc:set_timeout(conf.timeout)

                local params = {
                    method = "POST",
                    body =  ngx.encode_args({
                        grant_type = "refresh_token",
                        client_id = conf.client_id,
                        refresh_token = session.refresh_token,
                    }),
                    ssl_verify = conf.ssl_verify,
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                }

                local current_time = ngx.time()

                local res, err = httpc:request_uri(token_endpoint, params)

                if not res then
                    err = "Accessing token endpoint url (" .. url .. ") failed: " .. error
                    log.error(err)
                    return nil, err
                end

                log.debug("Response data: " .. res.body)

                local json, err = authz_keycloak_parse_json_response(res)

                if not json then
                    err = "Could not decode JSON from token endpoint" .. (err and (": " .. err) or '.')
                    log.error(err)
                    return nil, err
                end

                if not json.access_token then
                    -- Clear session.
                    log.debug("Answer didn't contain a new access token. Clearing session.")
                    session = nil
                else
                    log.debug("Got new access token.")
                    -- Save access token.
                    session.access_token = json.access_token

                    -- Calculate and save access token expiry time.
                    session.access_token_expiration = current_time
                            + authz_keycloak_access_token_expires_in(conf, json.expires_in)

                    -- Save refresh token, maybe.
                    if json.refresh_token ~= nil then
                        log.debug("Got new refresh token.")
                        session.refresh_token = json.refresh_token

                        -- Calculate and save refresh token expiry time.
                        session.refresh_token_expiration = current_time
                                + authz_keycloak_refresh_token_expires_in(conf, json.refresh_expires_in)
                    end

                    authz_keycloak_cache_set("access_tokens", token_endpoint .. ":" .. conf.client_id,
                                           core.json.encode(session), 24 * 60 * 60)
                end
            else
                -- No refresh token available, or it has expired. Clear session.
                log.debug("No or expired refresh token. Clearing session.")
                session = nil
            end
        end
    end

    if not session then
        -- No session available. Create a new one.

        core.log.debug("Getting access token for Protection API from token endpoint.")
        local httpc = http.new()
        httpc:set_timeout(conf.timeout)

        local params = {
            method = "POST",
            body =  ngx.encode_args({
                grant_type = "client_credentials",
                client_id = conf.client_id,
                client_secret = conf.client_secret,
            }),
            ssl_verify = conf.ssl_verify,
            headers = {
                ["Content-Type"] = "application/x-www-form-urlencoded"
            }
        }

        local current_time = ngx.time()

        local res, err = httpc:request_uri(token_endpoint, params)

        if not res then
            err = "Accessing token endpoint url (" .. url .. ") failed: " .. error
            log.error(err)
            return nil, err
        end

        log.debug("Response data: " .. res.body)
        local json, err = authz_keycloak_parse_json_response(res)

        if not json then
          err = "Could not decode JSON from token endpoint" .. (err and (": " .. err) or '.')
          log.error(err)
          return nil, err
        end

        if not json.access_token then
            err = "Response does not contain access_token field."
            log.error(err)
            return nil, err
        end

        session = {}

        -- Save access token.
        session.access_token = json.access_token

        -- Calculate and save access token expiry time.
        session.access_token_expiration = current_time
                + authz_keycloak_access_token_expires_in(conf, json.expires_in)

        -- Save refresh token, maybe.
        if json.refresh_token ~= nil then
            session.refresh_token = json.refresh_token

            -- Calculate and save refresh token expiry time.
            session.refresh_token_expiration = current_time
                    + authz_keycloak_refresh_token_expires_in(conf, json.refresh_expires_in)
        end

        authz_keycloak_cache_set("access_tokens", token_endpoint .. ":" .. conf.client_id,
                                 core.json.encode(session), 24 * 60 * 60)
    end

    return session.access_token
end


local function is_path_protected(conf)
    -- TODO if permissions are empty lazy load paths from Keycloak
    if conf.permissions == nil then
        return false
    end
    return true
end


local function evaluate_permissions(conf, token)
    if not is_path_protected(conf) and conf.policy_enforcement_mode == "ENFORCING" then
        return 403
    end

    -- Ensure discovered data.
    local err = authz_keycloak_ensure_discovered_data(conf)
    if err then
      return 500, err
    end

    -- Ensure service account access token.
    local sa_access_token, err = authz_keycloak_ensure_sa_access_token(conf)
    if err then
      return 500, err
    end

    -- Get token endpoint URL.
    local token_endpoint = authz_keycloak_get_token_endpoint(conf)
    if not token_endpoint then
      log.error("Unable to determine token endpoint.")
      return 500, "Unable to determine token endpoint."
    end
    log.debug("Token endpoint: ", token_endpoint)

    local httpc = http.new()
    httpc:set_timeout(conf.timeout)

    local params = {
        method = "POST",
        body =  ngx.encode_args({
            grant_type = conf.grant_type,
            audience = conf.client_id,
            response_mode = "decision",
            permission = conf.permissions
        }),
        ssl_verify = conf.ssl_verify,
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = token
        }
    }

    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    else
        params.keepalive = conf.keepalive
    end

    local httpc_res, httpc_err = httpc:request_uri(token_endpoint, params)

    if not httpc_res then
        log.error("error while sending authz request to ", token_endpoint, ": ", httpc_err)
        return 500, httpc_err
    end

    if httpc_res.status >= 400 then
        log.error("status code: ", httpc_res.status, " msg: ", httpc_res.body)
        return httpc_res.status, httpc_res.body
    end
end


local function fetch_jwt_token(ctx)
    local token = core.request.header(ctx, "Authorization")
    if not token then
        return nil, "authorization header not available"
    end

    local prefix = sub_str(token, 1, 7)
    if prefix ~= 'Bearer ' and prefix ~= 'bearer ' then
        return "Bearer " .. token
    end
    return token
end


function _M.access(conf, ctx)
    log.debug("hit keycloak-auth access")
    local jwt_token, err = fetch_jwt_token(ctx)
    if not jwt_token then
        log.error("failed to fetch JWT token: ", err)
        return 401, {message = "Missing JWT token in request"}
    end

    local status, body = evaluate_permissions(conf, jwt_token)
    if status then
        return status, body
    end
end


return _M
