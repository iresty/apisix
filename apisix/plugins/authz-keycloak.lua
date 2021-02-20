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

local require   = require
local core      = require("apisix.core")
local http      = require "resty.http"
local sub_str   = string.sub
local type      = type
local ngx       = ngx
local plugin_name = "authz-keycloak"

local log = core.log
local pairs = pairs

local schema = {
    type = "object",
    properties = {
        discovery = {type = "string", minLength = 1, maxLength = 4096},
        token_endpoint = {type = "string", minLength = 1, maxLength = 4096},
        resource_registration_endpoint = {type = "string", minLength = 1, maxLength = 4096},
        client_id = {type = "string", minLength = 1, maxLength = 100},
        audience = {type = "string", minLength = 1, maxLength = 100,
                    description = "Deprecated, use `client_id` instead."},
        client_secret = {type = "string", minLength = 1, maxLength = 100},
        grant_type = {
            type = "string",
            default="urn:ietf:params:oauth:grant-type:uma-ticket",
            enum = {"urn:ietf:params:oauth:grant-type:uma-ticket"},
            minLength = 1, maxLength = 100
        },
        policy_enforcement_mode = {
            type = "string",
            enum = {"ENFORCING", "PERMISSIVE"},
            default = "ENFORCING"
        },
        permissions = {
            type = "array",
            items = {
                type = "string",
                minLength = 1, maxLength = 100
            },
            uniqueItems = true
        },
        lazy_load_paths = {type = "boolean", default = false},
        http_method_as_scope = {type = "boolean", default = false},
        timeout = {type = "integer", minimum = 1000, default = 3000},
        ssl_verify = {type = "boolean", default = true},
        cache_ttl_seconds = {type = "integer", minimum = 1, default = 24 * 60 * 60},
        keepalive = {type = "boolean", default = true},
        keepalive_timeout = {type = "integer", minimum = 1000, default = 60000},
        keepalive_pool = {type = "integer", minimum = 1, default = 5}
    },
    allOf = {
        -- Require discovery or token endpoint.
        {
            anyOf = {
                {required = {"discovery"}},
                {required = {"token_endpoint"}}
            }
        },
        -- Require client_id or audience.
        {
            anyOf = {
                {required = {"client_id"}},
                {required = {"audience"}}
            }
        },
        -- If lazy_load_paths is true, require discovery or resource registration endpoint.
        {
            anyOf = {
                {
                    properties = {
                        lazy_load_paths = {enum = {false}},
                    }
                },
                {
                    properties = {
                        lazy_load_paths = {enum = {true}},
                    },
                    anyOf = {
                        {required = {"discovery"}},
                        {required = {"resource_registration_endpoint"}}
                    }
                }
            }
        }
    }
}


local _M = {
    version = 0.1,
    priority = 2000,
    name = plugin_name,
    schema = schema,
}


function _M.check_schema(conf)
    -- Check for deprecated audience attribute and emit warnings if used.
    if conf.audience then
        log.warn("Plugin attribute `audience` is deprecated, use `client_id` instead.")
        if conf.client_id then
            log.warn("Ignoring `audience` attribute in favor of `client_id`.")
        end
    end
    return core.schema.check(schema, conf)
end


-- Return the configured client ID parameter.
local function authz_keycloak_get_client_id(conf)
    if conf.client_id then
        -- Prefer client_id, if given.
        return conf.client_id
    end

    return conf.audience
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


-- Configure request parameters.
local function authz_keycloak_configure_params(params, conf)
    -- Keepalive options.
    if conf.keepalive then
        params.keepalive_timeout = conf.keepalive_timeout
        params.keepalive_pool = conf.keepalive_pool
    else
        params.keepalive = conf.keepalive
    end

    -- TLS verification.
    params.ssl_verify = conf.ssl_verify

    -- Decorate parameters, maybe, and return.
    return conf.http_request_decorator and conf.http_request_decorator(params) or params
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


-- Get and configure HTTP client.
local function authz_keycloak_get_http_client(conf)
    local httpc = http.new()
    authz_keycloak_configure_timeouts(httpc, conf.timeout)
    authz_keycloak_configure_proxy(httpc, conf.proxy_opts)
    return httpc
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


-- Get the Discovery metadata from the specified URL.
local function authz_keycloak_discover(conf)
    log.debug("authz_keycloak_discover: URL is: " .. conf.discovery)

    local json, err
    local v = authz_keycloak_cache_get("discovery", conf.discovery)

    if not v then
        log.debug("Discovery data not in cache, making call to discovery endpoint.")

        -- Make the call to the discovery endpoint.
        local httpc = authz_keycloak_get_http_client(conf)

        local params = authz_keycloak_configure_params({}, conf)

        local res, error = httpc:request_uri(conf.discovery, params)

        if not res then
            err = "Accessing discovery URL (" .. conf.discovery .. ") failed: " .. error
            log.error(err)
        else
            log.debug("Response data: " .. res.body)
            json, err = authz_keycloak_parse_json_response(res)
            if json then
                authz_keycloak_cache_set("discovery", conf.discovery, core.json.encode(json),
                                         conf.cache_ttl_seconds)
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


-- Turn a discovery url set in the conf dictionary into the discovered information.
local function authz_keycloak_ensure_discovered_data(conf)
    local err
    if type(conf.discovery) == "string" then
        local discovery
        discovery, err = authz_keycloak_discover(conf)
        if not err then
            conf.discovery = discovery
        end
    end
    return err
end


-- Get an endpoint from the configuration.
local function authz_keycloak_get_endpoint(conf, endpoint)
    if conf and conf[endpoint] then
        -- Use explicit entry.
        return conf[endpoint]
    elseif conf and conf.discovery and type(conf.discovery) == "table" then
        -- Use discovery data.
        return conf.discovery[endpoint]
    end

    -- Unable to obtain endpoint.
    return nil
end


-- Return the token endpoint from the configuration.
local function authz_keycloak_get_token_endpoint(conf)
    return authz_keycloak_get_endpoint(conf, "token_endpoint")
end


-- Return the resource registration endpoint from the configuration.
local function authz_keycloak_get_resource_registration_endpoint(conf)
    return authz_keycloak_get_endpoint(conf, "resource_registration_endpoint")
end


-- Return access_token expires_in value (in seconds).
local function authz_keycloak_access_token_expires_in(conf, expires_in)
    return (expires_in or conf.access_token_expires_in or 300)
           - 1 - (conf.access_token_expires_leeway or 0)
end


-- Return refresh_token expires_in value (in seconds).
local function authz_keycloak_refresh_token_expires_in(conf, expires_in)
    return (expires_in or conf.refresh_token_expires_in or 3600)
           - 1 - (conf.refresh_token_expires_leeway or 0)
end


-- Ensure a valid service account access token is available for the configured client.
local function authz_keycloak_ensure_sa_access_token(conf)
    local client_id = authz_keycloak_get_client_id(conf)
    local ttl = conf.cache_ttl_seconds
    local token_endpoint = authz_keycloak_get_token_endpoint(conf)

    if not token_endpoint then
        log.error("Unable to determine token endpoint.")
        return 500, "Unable to determine token endpoint."
    end

    local session = authz_keycloak_cache_get("access_tokens", token_endpoint .. ":"
                                             .. client_id)

    if session then
        -- Decode session string.
        local err
        session, err = core.json.decode(session)

        if not session then
            -- Should never happen.
            return 500, err
        end

        local current_time = ngx.time()

        if current_time < session.access_token_expiration then
            -- Access token is still valid.
            log.debug("Access token is still valid.")
            return session.access_token
        else
            -- Access token has expired.
            log.debug("Access token has expired.")
            if session.refresh_token
               and (not session.refresh_token_expiration
                    or current_time < session.refresh_token_expiration) then
                -- Try to get a new access token, using the refresh token.
                log.debug("Trying to get new access token using refresh token.")

                local httpc = authz_keycloak_get_http_client(conf)

                local params = {
                    method = "POST",
                    body =  ngx.encode_args({
                        grant_type = "refresh_token",
                        client_id = client_id,
                        client_secret = conf.client_secret,
                        refresh_token = session.refresh_token,
                    }),
                    headers = {
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                    }
                }

                params = authz_keycloak_configure_params(params, conf)

                local res, err = httpc:request_uri(token_endpoint, params)

                if not res then
                    err = "Accessing token endpoint URL (" .. token_endpoint
                          .. ") failed: " .. err
                    log.error(err)
                    return nil, err
                end

                log.debug("Response data: " .. res.body)
                local json, err = authz_keycloak_parse_json_response(res)

                if not json then
                    err = "Could not decode JSON from token endpoint"
                          .. (err and (": " .. err) or '.')
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
                                + authz_keycloak_refresh_token_expires_in(conf,
                                                                          json.refresh_expires_in)
                    end

                    authz_keycloak_cache_set("access_tokens",
                                             token_endpoint .. ":" .. client_id,
                                             core.json.encode(session), ttl)
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
        local httpc = authz_keycloak_get_http_client(conf)

        local params = {
            method = "POST",
            body =  ngx.encode_args({
                grant_type = "client_credentials",
                client_id = client_id,
                client_secret = conf.client_secret,
            }),
            headers = {
                ["Content-Type"] = "application/x-www-form-urlencoded"
            }
        }

        params = authz_keycloak_configure_params(params, conf)

        local current_time = ngx.time()

        local res, err = httpc:request_uri(token_endpoint, params)

        if not res then
            err = "Accessing token endpoint URL (" .. token_endpoint .. ") failed: " .. err
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

        authz_keycloak_cache_set("access_tokens", token_endpoint .. ":" .. client_id,
                                 core.json.encode(session), ttl)
    end

    return session.access_token
end


-- Resolve a URI to one or more resource IDs.
local function authz_keycloak_resolve_resource(conf, uri, sa_access_token)
    -- Get resource registration endpoint URL.
    local resource_registration_endpoint = authz_keycloak_get_resource_registration_endpoint(conf)

    if not resource_registration_endpoint then
        local err = "Unable to determine registration endpoint."
        log.error(err)
        return 500, err
    end

    log.debug("Resource registration endpoint: ", resource_registration_endpoint)

    local httpc = authz_keycloak_get_http_client(conf)

    local params = {
        method = "GET",
        query = {uri = uri, matchingUri = "true"},
        headers = {
            ["Authorization"] = "Bearer " .. sa_access_token
        }
    }

    params = authz_keycloak_configure_params(params, conf)

    local res, err = httpc:request_uri(resource_registration_endpoint, params)

    if not res then
        err = "Accessing resource registration endpoint URL (" .. resource_registration_endpoint
              .. ") failed: " .. err
        log.error(err)
        return nil, err
    end

    log.debug("Response data: " .. res.body)
    res.body = '{"resources": ' .. res.body .. '}'
    local json, err = authz_keycloak_parse_json_response(res)

    if not json then
      err = "Could not decode JSON from resource registration endpoint"
            .. (err and (": " .. err) or '.')
      log.error(err)
      return nil, err
    end

    return json.resources
end


local function evaluate_permissions(conf, ctx, token)
    -- Ensure discovered data.
    local err = authz_keycloak_ensure_discovered_data(conf)
    if err then
        return 500, err
    end

    local permission

    if conf.lazy_load_paths then
        -- Ensure service account access token.
        local sa_access_token, err = authz_keycloak_ensure_sa_access_token(conf)
        if err then
            return 500, err
        end

        -- Resolve URI to resource(s).
        permission, err = authz_keycloak_resolve_resource(conf, ctx.var.request_uri,
                                                          sa_access_token)

        -- Check result.
        if permission == nil then
            -- No result back from resource registration endpoint.
            return 500, err
        end
    else
        -- Use statically configured permissions.
        permission = conf.permissions
    end

    -- Return 403 if permission is empty and enforcement mode is "ENFORCING".
    if #permission == 0 and conf.policy_enforcement_mode == "ENFORCING" then
        -- Return Keycloak-style message for consistency.
        return 403, '{"error":"access_denied","error_description":"not_authorized"}'
    end

    -- Determine scope from HTTP method, maybe.
    local scope
    if conf.http_method_as_scope then
        scope = ctx.var.request_method
    end

    if scope then
        -- Loop over permissions and add scope.
        for k, v in pairs(permission) do
            if v:find("#", 1, true) then
                -- Already contains scope.
                permission[k] = v .. ", " .. scope
            else
                -- Doesn't contain scope yet.
                permission[k] = v .. "#" .. scope
            end
        end
    end

    for k, v in pairs(permission) do
        log.debug("Requesting permission ", v, ".")
    end

    -- Get token endpoint URL.
    local token_endpoint = authz_keycloak_get_token_endpoint(conf)
    if not token_endpoint then
        err = "Unable to determine token endpoint."
        log.error(err)
        return 500, err
    end
    log.debug("Token endpoint: ", token_endpoint)

    local httpc = authz_keycloak_get_http_client(conf)

    local params = {
        method = "POST",
        body =  ngx.encode_args({
            grant_type = conf.grant_type,
            audience = authz_keycloak_get_client_id(conf),
            response_mode = "decision",
            permission = permission
        }),
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = token
        }
    }

    params = authz_keycloak_configure_params(params, conf)

    local res, err = httpc:request_uri(token_endpoint, params)

    if not res then
        err = "Error while sending authz request to " .. token_endpoint .. ": " .. err
        log.error(err)
        return 500, err
    end

    log.debug("Response status: ", res.status, ", data: ", res.body)

    if res.status == 403 then
        -- Request permanently denied, e.g. due to lacking permissions.
        log.debug('Request denied: HTTP 403 Forbidden. Body: ', res.body)
        return res.status, res.body
    elseif res.status == 401 then
        -- Request temporarily denied, e.g access token not valid.
        log.debug('Request denied: HTTP 401 Unauthorized. Body: ', res.body)
        return res.status, res.body
    elseif res.status >= 400 then
        -- Some other error. Log full response.
        log.error('Request denied: Token endpoint returned an error (status: ',
                  res.status, ', body: ', res.body, ').')
        return res.status, res.body
    end

    -- Request accepted.
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

    local status, body = evaluate_permissions(conf, ctx, jwt_token)
    if status then
        return status, body
    end
end


return _M
