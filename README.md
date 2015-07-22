# lua-modfin-srv-proxy

A dynamic SRV record proxy replacing nginx proxy_pass and static upstreams built for 
[OpenResty](http://openresty.org/) / [ngx_lua](https://github.com/chaoslawful/lua-nginx-module).

It was design to work together with DNS services like consul

# Status

A first implementation is ready for testing. It seams ready for at least simpler use cases.

# Features

* Multiple resolvers
* Custom resolver port
* SRV and A record caching
* HTTP proxying
* Proxying selection strategies
    * Round Robin
    * Random
    * IP Hashing

# Dependencies 

* [ngx_lua](https://github.com/chaoslawful/lua-nginx-module)
* [resty.dns.resolver](https://github.com/openresty/lua-resty-dns)
* cjson
* [resty.http](https://github.com/pintsized/lua-resty-http) (not included in OpenResty)

# Config

Using OpenResty it should be fairly straight forward to implement.
* Add resty.http lua files to your lualib dir, eg. /usr/local/openresty/lualib/resty/
* Add modfin.srv_proxy lua file to your lualib dir, eg. /usr/local/openresty/lualib/modfin/

## Nginx config example
```` lua
    lua_shared_dict srv_proxy_cache 2m;                           
    server {
        location /api/a-backend {

            set $srv_resolvers "8.8.8.8 127.0.0.1 192.168.2.6:8600";  
            set $srv_service "_a-backend._http.service.consul";       

            rewrite /api/a-backend/(.*) /$1  break;

            content_by_lua "
                     local proxy = require 'modfin.srv_proxy'                              
                     proxy.set('resolvers', ngx.var.srv_resolvers)
                     proxy.pass(ngx.var.srv_service)                                      
            ";

        }
        listen 80;
    }
````

#API 

## set

syntax:```proxy.set("key", "value")```
It is used to set settings for the srv-proxy
* ``"resolvers"`` - ip addresses to the resolvers used 
* ``"ttl"`` - The ttl in seconds for the cached srv records. DNS ttl is ignored (default ``60``)
* ``"strategy"`` - The proxy strategy. ``"round_robin"``, ``"random"``, ``"ip_hash"`` (default ``"round_robin"``) 
* ``"dns_protocol"`` - ``"udp"``, ``"tcp"`` (default ``"udp"``)
* ``"dns_timeout"`` - in ms (default ``200``)
* ``"dns_retrys"`` - number of retrys if timeout exp (default ``2``)
* ``"http_timeout"`` - in ms, timeout establishing a connection (default ``500``)
* ``"proxy_timeout"`` - in ms, timeout for backend to produce output (default ``2000``)


## pass

``` symtax: proxy.pass("_a-servic._protocol.domain") ```

Starts the process of and sets the content of the nginx response. 

# TODO

* Testing, non implemented yet
* Implementing other selection strategies, using weights and priority. Maybe something with server location as well






