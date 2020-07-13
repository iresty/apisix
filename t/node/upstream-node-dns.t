#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX 'no_plan';
use Cwd qw(cwd);

repeat_each(1);
log_level('info');
no_root_location();
no_shuffle();

my $apisix_home = $ENV{APISIX_HOME} || cwd();

sub read_file($) {
    my $infile = shift;
    open my $in, "$apisix_home/$infile"
        or die "cannot open $infile for reading: $!";
    my $data = do { local $/; <$in> };
    close $in;
    $data;
}

my $yaml_config = read_file("conf/config.yaml");
$yaml_config =~ s/node_listen: 9080/node_listen: 1984/;
$yaml_config =~ s/enable_heartbeat: true/enable_heartbeat: false/;
$yaml_config =~ s/admin_key:/disable_admin_key:/;
$yaml_config =~ s/dns_resolver_valid: 30/dns_resolver_valid: 1/;

add_block_preprocessor(sub {
    my ($block) = @_;

    $block->set_value("yaml_config", $yaml_config);
});

run_tests();

__DATA__

=== TEST 1: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "upstream": {
                        "nodes": {
                            "test.com:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 2: hit route, parse upstream node address by DNS
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    utils.dns_parse = function (resolvers, domain)  -- mock: DNS parser
        if domain == "test.com" then
            return {address = "127.0.0.2"}
        end

        error("unkown domain: " .. domain)
    end
--- request
GET /hello
--- response_body
hello world
--- no_error_log
[error]



=== TEST 3: dns cached expired, reparse the domain in upstream node
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    local count = 0
    utils.dns_parse = function (resolvers, domain)  -- mock: DNS parser
        count = count + 1

        if domain == "test.com" then
            return {address = "127.0.0." .. count}
        end

        error("unkown domain: " .. domain)
    end

--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        core.log.info("call /hello")
        local code, body = t('/hello', ngx.HTTP_GET)

        ngx.sleep(1.1)  -- cache expired
        core.log.info("call /hello")
        local code, body = t('/hello', ngx.HTTP_GET)
        local code, body = t('/hello', ngx.HTTP_GET)

        ngx.sleep(1.1)  -- cache expired
        core.log.info("call /hello")
        local code, body = t('/hello', ngx.HTTP_GET)
    }
}

--- request
GET /t
--- grep_error_log eval
qr/dns resolver domain: test.com to 127.0.0.\d|call \/hello|proxy to 127.0.0.\d:1980/
--- grep_error_log_out
call /hello
dns resolver domain: test.com to 127.0.0.1
proxy to 127.0.0.1:1980
call /hello
dns resolver domain: test.com to 127.0.0.2
proxy to 127.0.0.2:1980
proxy to 127.0.0.2:1980
call /hello
dns resolver domain: test.com to 127.0.0.3
proxy to 127.0.0.3:1980
