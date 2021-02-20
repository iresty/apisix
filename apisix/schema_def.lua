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
local schema       = require('apisix.core.schema')
local table_insert = table.insert
local table_concat = table.concat
local setmetatable = setmetatable
local error        = error

local _M = {version = 0.5}


local plugins_schema = {
    type = "object"
}

local id_schema = {
    anyOf = {
        {
            type = "string", minLength = 1, maxLength = 64,
            pattern = [[^[a-zA-Z0-9-_.]+$]]
        },
        {type = "integer", minimum = 1}
    }
}

local host_def_pat = "^\\*?[0-9a-zA-Z-._]+$"
local host_def = {
    type = "string",
    pattern = host_def_pat,
}
_M.host_def = host_def


local ipv4_seg = "([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])"
local ipv4_def_buf = {}
for i = 1, 4 do
    table_insert(ipv4_def_buf, ipv4_seg)
end
local ipv4_def = table_concat(ipv4_def_buf, [[\.]])
-- There is false negative for ipv6/cidr. For instance, `:/8` will be valid.
-- It is fine as the correct regex will be too complex.
local ipv6_def = "([a-fA-F0-9]{0,4}:){1,8}(:[a-fA-F0-9]{0,4}){0,8}"
                 .. "([a-fA-F0-9]{0,4})?"
local ip_def = {
    {title = "IPv4", type = "string", format = "ipv4"},
    {title = "IPv4/CIDR", type = "string", pattern = "^" .. ipv4_def .. "/([12]?[0-9]|3[0-2])$"},
    {title = "IPv6", type = "string", format = "ipv6"},
    {title = "IPv6/CIDR", type = "string", pattern = "^" .. ipv6_def .. "/[0-9]{1,3}$"},
}
_M.ip_def = ip_def


_M.uri_def = {type = "string", pattern = [=[^[^\/]+:\/\/([\da-zA-Z.-]+|\[[\da-fA-F:]+\])(:\d+)?]=]}


local timestamp_def = {
    type = "integer",
}

local remote_addr_def = {
    description = "client IP",
    type = "string",
    anyOf = ip_def,
}


local label_value_def = {
    description = "value of label",
    type = "string",
    pattern = [[^\S+$]],
    maxLength = 64,
    minLength = 1
}
_M.label_value_def = label_value_def


local rule_name_def = {
    type = "string",
    maxLength = 100,
    minLength = 1,
}


local health_checker = {
    type = "object",
    properties = {
        active = {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    enum = {"http", "https", "tcp"},
                    default = "http"
                },
                timeout = {type = "number", default = 1},
                concurrency = {type = "integer", default = 10},
                host = host_def,
                port = {
                    type = "integer",
                    minimum = 1,
                    maximum = 65535
                },
                http_path = {type = "string", default = "/"},
                https_verify_certificate = {type = "boolean", default = true},
                healthy = {
                    type = "object",
                    properties = {
                        interval = {type = "integer", minimum = 1, default = 1},
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599
                            },
                            uniqueItems = true,
                            default = {200, 302}
                        },
                        successes = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 2
                        }
                    }
                },
                unhealthy = {
                    type = "object",
                    properties = {
                        interval = {type = "integer", minimum = 1, default = 1},
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599
                            },
                            uniqueItems = true,
                            default = {429, 404, 500, 501, 502, 503, 504, 505}
                        },
                        http_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 5
                        },
                        tcp_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 2
                        },
                        timeouts = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 3
                        }
                    }
                },
                req_headers = {
                  type = "array",
                  minItems = 1,
                  items = {
                      type = "string",
                      uniqueItems = true,
                  },
                }
            }
        },
        passive = {
            type = "object",
            properties = {
                type = {
                    type = "string",
                    enum = {"http", "https", "tcp"},
                    default = "http"
                },
                healthy = {
                    type = "object",
                    properties = {
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599,
                            },
                            uniqueItems = true,
                            default = {200, 201, 202, 203, 204, 205, 206, 207,
                                       208, 226, 300, 301, 302, 303, 304, 305,
                                       306, 307, 308}
                        },
                        successes = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 5
                        }
                    }
                },
                unhealthy = {
                    type = "object",
                    properties = {
                        http_statuses = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "integer",
                                minimum = 200,
                                maximum = 599,
                            },
                            uniqueItems = true,
                            default = {429, 500, 503}
                        },
                        tcp_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 2
                        },
                        timeouts = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 7
                        },
                        http_failures = {
                            type = "integer",
                            minimum = 1,
                            maximum = 254,
                            default = 5
                        },
                    }
                }
            }
        }
    },
    additionalProperties = false,
    anyOf = {
        {required = {"active"}},
        {required = {"active", "passive"}},
    },
}


local nodes_schema = {
    anyOf = {
        {
            type = "object",
            patternProperties = {
                [".*"] = {
                    description = "weight of node",
                    type = "integer",
                    minimum = 0,
                }
            },
        },
        {
            type = "array",
            items = {
                type = "object",
                properties = {
                    host = host_def,
                    port = {
                        description = "port of node",
                        type = "integer",
                        minimum = 1,
                    },
                    weight = {
                        description = "weight of node",
                        type = "integer",
                        minimum = 0,
                    },
                    metadata = {
                        description = "metadata of node",
                        type = "object",
                    }
                },
                required = {"host", "port", "weight"},
            },
        }
    }
}


local upstream_schema = {
    type = "object",
    properties = {
        create_time = timestamp_def,
        update_time = timestamp_def,
        nodes = nodes_schema,
        retries = {
            type = "integer",
            minimum = 0,
        },
        timeout = {
            type = "object",
            properties = {
                connect = {type = "number", exclusiveMinimum = 0},
                send = {type = "number", exclusiveMinimum = 0},
                read = {type = "number", exclusiveMinimum = 0},
            },
            required = {"connect", "send", "read"},
        },
        type = {
            description = "algorithms of load balancing",
            type = "string",
            enum = {"chash", "roundrobin", "ewma", "least_conn"}
        },
        checks = health_checker,
        hash_on = {
            type = "string",
            default = "vars",
            enum = {
              "vars",
              "header",
              "cookie",
              "consumer",
              "vars_combinations",
            },
        },
        key = {
            description = "the key of chash for dynamic load balancing",
            type = "string",
        },
        scheme = {
            default = "http",
            enum = {"grpc", "grpcs", "http", "https"}
        },
        labels = {
            description = "key/value pairs to specify attributes",
            type = "object",
            patternProperties = {
                [".*"] = label_value_def
            },
            maxProperties = 16
        },
        discovery_type = {
            description = "discovery type",
            type = "string",
        },
        pass_host = {
            description = "mod of host passing",
            type = "string",
            enum = {"pass", "node", "rewrite"},
            default = "pass"
        },
        upstream_host = host_def,
        name = rule_name_def,
        desc = {type = "string", maxLength = 256},
        service_name = rule_name_def,
        id = id_schema,
        -- deprecate fields, will be removed soon
        enable_websocket = {
            description = "enable websocket for request",
            type        = "boolean",
        },
    },
    oneOf = {
        {required = {"type", "nodes"}},
        {required = {"type", "service_name", "discovery_type"}},
    },
    additionalProperties = false,
}

-- TODO: add more nginx variable support
_M.upstream_hash_vars_schema = {
    type = "string",
    pattern = [[^((uri|server_name|server_addr|request_uri|remote_port]]
               .. [[|remote_addr|query_string|host|hostname)]]
               .. [[|arg_[0-9a-zA-z_-]+)$]],
}

-- validates header name, cookie name.
-- a-z, A-Z, 0-9, '_' and '-' are allowed.
-- when "underscores_in_headers on", header name allow '_'.
-- http://nginx.org/en/docs/http/ngx_http_core_module.html#underscores_in_headers
_M.upstream_hash_header_schema = {
    type = "string",
    pattern = [[^[a-zA-Z0-9-_]+$]]
}

-- validates string only
_M.upstream_hash_vars_combinations_schema = {
    type = "string"
}


_M.route = {
    type = "object",
    properties = {
        create_time = timestamp_def,
        update_time = timestamp_def,
        uri = {type = "string", minLength = 1, maxLength = 4096},
        uris = {
            type = "array",
            items = {
                description = "HTTP uri",
                type = "string",
            },
            minItems = 1,
            uniqueItems = true,
        },
        name = rule_name_def,
        desc = {type = "string", maxLength = 256},
        priority = {type = "integer", default = 0},

        methods = {
            type = "array",
            items = {
                description = "HTTP method",
                type = "string",
                enum = {"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD",
                        "OPTIONS", "CONNECT", "TRACE"}
            },
            uniqueItems = true,
        },
        host = host_def,
        hosts = {
            type = "array",
            items = host_def,
            minItems = 1,
            uniqueItems = true,
        },
        remote_addr = remote_addr_def,
        remote_addrs = {
            type = "array",
            items = remote_addr_def,
            minItems = 1,
            uniqueItems = true,
        },
        vars = {
            type = "array",
            items = {
                description = "Nginx builtin variable name and value",
                type = "array",
                maxItems = 4,
                minItems = 2,
            },
        },
        filter_func = {
            type = "string",
            minLength = 10,
            pattern = [[^function]],
        },

        -- The 'script' fields below are used by dashboard for plugin orchestration
        script = {type = "string", minLength = 10, maxLength = 102400},
        script_id = id_schema,

        plugins = plugins_schema,
        upstream = upstream_schema,

        labels = {
            description = "key/value pairs to specify attributes",
            type = "object",
            patternProperties = {
                [".*"] = label_value_def
            },
            maxProperties = 16
        },

        service_id = id_schema,
        upstream_id = id_schema,
        service_protocol = {
            enum = {"grpc", "http"}
        },

        enable_websocket = {
            description = "enable websocket for request",
            type        = "boolean",
        },

        id = id_schema,

        status = {
            description = "route status, 1 to enable, 0 to disable",
            type = "integer",
            enum = {1, 0},
            default = 1
        },
    },
    allOf = {
        {
            oneOf = {
                {required = {"uri"}},
                {required = {"uris"}},
            },
        },
        {
            oneOf = {
                {["not"] = {
                    anyOf = {
                        {required = {"host"}},
                        {required = {"hosts"}},
                    }
                }},
                {required = {"host"}},
                {required = {"hosts"}}
            },
        },
        {
            oneOf = {
                {["not"] = {
                    anyOf = {
                        {required = {"remote_addr"}},
                        {required = {"remote_addrs"}},
                    }
                }},
                {required = {"remote_addr"}},
                {required = {"remote_addrs"}}
            },
        },
    },
    anyOf = {
        {required = {"plugins", "uri"}},
        {required = {"upstream", "uri"}},
        {required = {"upstream_id", "uri"}},
        {required = {"service_id", "uri"}},
        {required = {"plugins", "uris"}},
        {required = {"upstream", "uris"}},
        {required = {"upstream_id", "uris"}},
        {required = {"service_id", "uris"}},
        {required = {"script", "uri"}},
        {required = {"script", "uris"}},
    },
    ["not"] = {
        anyOf = {
            {required = {"script", "plugins"}}
        }
    },
    additionalProperties = false,
}


_M.service = {
    type = "object",
    properties = {
        id = id_schema,
        plugins = plugins_schema,
        upstream = upstream_schema,
        upstream_id = id_schema,
        name = rule_name_def,
        desc = {type = "string", maxLength = 256},
        script = {type = "string", minLength = 10, maxLength = 102400},
        labels = {
            description = "key/value pairs to specify attributes",
            type = "object",
            patternProperties = {
                [".*"] = label_value_def
            },
            maxProperties = 16
        },
        create_time = timestamp_def,
        update_time = timestamp_def,
        enable_websocket = {
            description = "enable websocket for request",
            type        = "boolean",
        },

    },
    additionalProperties = false,
}


_M.consumer = {
    type = "object",
    properties = {
        username = {
            type = "string", minLength = 1, maxLength = 32,
            pattern = [[^[a-zA-Z0-9_]+$]]
        },
        plugins = plugins_schema,
        labels = {
            description = "key/value pairs to specify attributes",
            type = "object",
            patternProperties = {
                [".*"] = label_value_def
            },
            maxProperties = 16
        },
        create_time = timestamp_def,
        update_time = timestamp_def,
        desc = {type = "string", maxLength = 256},
        -- deprecate fields, will be removed soon
        id = id_schema,
    },
    required = {"username"},
    additionalProperties = false,
}


_M.upstream = upstream_schema


_M.ssl = {
    type = "object",
    properties = {
        id = id_schema,
        cert = {
            type = "string", minLength = 128, maxLength = 64*1024
        },
        key = {
            type = "string", minLength = 128, maxLength = 64*1024
        },
        sni = {
            type = "string",
            pattern = [[^\*?[0-9a-zA-Z-.]+$]],
        },
        snis = {
            type = "array",
            items = {
                type = "string",
                pattern = [[^\*?[0-9a-zA-Z-.]+$]],
            },
            minItems = 1,
        },
        certs = {
            type = "array",
            items = {
                type = "string",
                minLength = 128,
                maxLength = 64*1024,
            }
        },
        keys = {
            type = "array",
            items = {
                type = "string",
                minLength = 128,
                maxLength = 64*1024,
            }
        },
        exptime = {
            type = "integer",
            minimum = 1588262400,  -- 2020/5/1 0:0:0
        },
        labels = {
            description = "key/value pairs to specify attributes",
            type = "object",
            patternProperties = {
                [".*"] = label_value_def
            },
            maxProperties = 16
        },
        status = {
            description = "ssl status, 1 to enable, 0 to disable",
            type = "integer",
            enum = {1, 0},
            default = 1
        },
        validity_end = timestamp_def,
        validity_start = timestamp_def,
        create_time = timestamp_def,
        update_time = timestamp_def
    },
    oneOf = {
        {required = {"sni", "key", "cert"}},
        {required = {"snis", "key", "cert"}}
    },
    additionalProperties = false,
}



_M.proto = {
    type = "object",
    properties = {
        content = {
            type = "string", minLength = 1, maxLength = 1024*1024
        }
    },
    required = {"content"},
    additionalProperties = false,
}


_M.global_rule = {
    type = "object",
    properties = {
        id = id_schema,
        plugins = plugins_schema,
        create_time = timestamp_def,
        update_time = timestamp_def
    },
    required = {"plugins"},
    additionalProperties = false,
}


_M.stream_route = {
    type = "object",
    properties = {
        id = id_schema,
        remote_addr = remote_addr_def,
        server_addr = {
            description = "server IP",
            type = "string",
            anyOf = ip_def,
        },
        server_port = {
            description = "server port",
            type = "integer",
        },
        upstream = upstream_schema,
        upstream_id = id_schema,
        plugins = plugins_schema,
    }
}


_M.plugins = {
    type = "array",
    items = {
        type = "object",
        properties = {
            name = {
                type = "string",
                minLength = 1,
            },
            stream = {
                type = "boolean"
            },
            additionalProperties = false,
        },
        required = {"name"}
    }
}


_M.id_schema = id_schema


_M.plugin_injected_schema = {
    ["$comment"] = "this is a mark for our injected plugin schema",
    disable = {
        type = "boolean",
    }
}


setmetatable(_M, {
    __index = schema,
    __newindex = function() error("no modification allowed") end,
})


return _M
