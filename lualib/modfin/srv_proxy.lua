local dns_api = require "resty.dns.resolver"
local http = require "resty.http"
local cjson = require "cjson"

local cache = ngx.shared.srv_proxy_cache


function hash(value)
	local h = 0

	if (h == 0 and #value > 0) then
			for i = 1, #value do
  			local c = value:sub(i,i)
  			h = 31 * h + string.byte(c)
			end
  end
  return h;
end


local function split(inputstr, sep)
        if sep == nil then
          sep = "%s"
        end
        local t={} ; i=1
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                t[i] = str
                i = i + 1
        end
        return t
end


function cache_get(service) 
	local json = cache:get("srv_"..service)
	if not json then
		return
	end	
	return cjson.decode(json)
end

local function cache_set(service, records, ttl)
	local json = cjson.encode(records)
	cache:set("srv_"..service, json, ttl)
end


function records_comparator(a, b)
	if a["priority"]+a["weight"] == b["weight"]+b["priority"] 
		and a["host"] == b["host"]
	then
		return a["port"] > b["port"]
	end

	if a["priority"]+a["weight"] == b["weight"]+b["priority"] 
	then
		return a["host"] > b["host"]
	end

	return a["priority"]+a["weight"] > b["weight"]+b["priority"]
end



local function get_records (resolvers, service, ttl, dns_timeout, dns_retrys, dns_protocol)
	local records = cache_get(service)
	
	-- cache hit
  if records then
		return records
	end

	local resolvers = split(resolvers, " ")
	local dns, err
	for i = 1, #resolvers do
		local resolver = split(resolvers[i], ":")
    resolver[2] = tonumber(resolver[2]) or 53
		
		
		dns, err = dns_api:new{
			nameservers = {resolver}, 
			retrans = dns_retrys, 
			timeout = dns_timeout
		}

		-- continue to next resolver
		if not dns then
			goto continue
		end

		if dns_protocol == "tcp" then
			records, err = dns:tcp_query(service, {qtype = dns.TYPE_SRV})
		else
			records, err = dns:query(service, {qtype = dns.TYPE_SRV})
		end

		-- continue to next resolver, if no records were found 
		if not records then
			goto continue
		end

		-- continue to next resolver, if no records were found 
		if records.errcode then
			goto continue
		end
		
		-- Records were found an there for exiting
		if true then
			break
		end

		::continue::
	end

	-- Adding ip to the record, querying the dns for A record
	if records then 
		for i = 1, #records do
			local record = records[i]
			if record.port then
				local a_records 

				if dns_protocol == "tcp" then
					a_records, err = dns:tcp_query(record.target)
				else
					a_records, err = dns:query(record.target)
				end

				-- only takes the first address in to account, no multiple A records are considerd
				record.host = a_records[1].address
			end
		end

		-- Sorts it in order to allow ip_hashing as selection strategy
		table.sort(records, records_comparator)

		cache_set(service, records, ttl)
		
		return records		
	end
	
	

end



function order_records_by_strategy(records, strategy)
	local ordered = {}

	if (strategy == "random") then
		for i = 1, #records do
			local index = math.random(#records)
			table.insert(ordered, table.remove(records, index))
		end

	elseif(strategy == "ip_hash") then
		local index = hash(ngx.var.remote_addr) % #records
		table.insert(orderd, table.remove(records, index))

		for i = 1, #records do
			order = order .. index
			table.insert(ordered, table.remove(records))
		end
		
	else -- round_robin
		local inc = cache:get("var_rr_inc");
		if not inc then inc = 1 end
		cache:set("var_rr_inc", inc+1);
		
		for i = 1, #records do
			local index = (inc+i) % #records + 1
			ordered[i] = records[index]
		end

	end

	return ordered;
end


function proxy_pass(records, strategy, proxy_timeout, http_timeout)
	local ok, err

	records = order_records_by_strategy(records, strategy)
	
	for i = 1, #records do
		local rec = records[i]
		local httpc = http.new()

		if  not rec.port then
			goto continue
		end

		httpc:set_timeout(http_timeout)
		ok, err = httpc:connect(rec.host, rec.port)

		if not ok then
			ngx.log(ngx.ERR, err)
			goto continue
		end

		httpc:set_timeout(proxy_timeout)
		httpc:proxy_response(httpc:proxy_request())
		httpc:set_keepalive()
		if true then
			return
		end

		::continue::
	end
  -- Could not do the proxy request
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)

end


local _M = {
    _VERSION = '0.01',
}


_M.settings = {}

function _M.set(key, value)
	if not value then
		return
	end
	_M.settings[key] = value
end


_M.set("ttl", 60)                 -- srv records cache ttl in seconud
_M.set("strategy", "round_robin") -- round_robin, random, ip_hash
_M.set("dns_protocol", "udp")     -- udp, tcp
_M.set("dns_timeout", 200)        -- in ms
_M.set("dns_retrys", 2)           -- number of retrys if timeout exp.
_M.set("http_timeout", 500)       -- in ms
_M.set("proxy_timeout", 2000)     -- in ms

function _M.pass(service)
	local records = get_records	(
																_M.settings.resolvers, 
																service, 
																_M.settings.ttl, 
																_M.settings.dns_timeout,
																_M.settings.dns_retrys,
																_M.settings.dns_protocol
															)

	if not records then
		ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
		return
	end

	proxy_pass(
							records, 
							_M.settings.strategy, 
							_M.settings.proxy_timeout, 
							_M.settings.http_timeout
						)
end




return _M




