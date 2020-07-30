local setmetatable = setmetatable

local _M = require('apicast.policy').new('MonitorViaImVision', '0.1')
local mt = { __index = _M }
http = require("resty.resolver.http")
cjson = require 'cjson'
resty_env = require 'resty.env'

function _M.new(config)
  --ngx.log(ngx.ERR, "running new")
  local self = setmetatable({}, mt)
  --local config = configuration or {}
  --self.enabled = config.enabled or {}
  self.timeout = config.timeout
  ngx.log(ngx.WARN, "======>>>>> self.timeout = ", self.timeout)
  self.aamp_endpoint = config.aamp_endpoint
  ngx.log(ngx.WARN, "======>>>>> self.aamp_endpoint = ", self.aamp_endpoint)
  -- self.aamp_endpoint = ngx.var.aamp_endpoint
  self.aamp_request_method = config.aamp_request_method
  ngx.log(ngx.WARN, "======>>>>> self.aamp_request_method = ", self.aamp_request_method)
  self.aamp_scheme 	 = config.aamp_scheme
  ngx.log(ngx.WARN, "======>>>>> self.aamp_scheme = ", self.aamp_scheme)
  self.aamp_server_name  = config.aamp_server_name
  ngx.log(ngx.WARN, "======>>>>> self.aamp_server_name = ", self.aamp_server_name)
  self.aamp_server_port = config.aamp_server_port
  ngx.log(ngx.WARN, "======>>>>> self.aamp_server_port = ", self.aamp_server_port)
  ngx.log(ngx.WARN, "======>>>>> self.imvurl = ", self.imvurl)
  
  local resty_env = require 'resty.env'
  ngx.log(ngx.WARN, 'my env THREESCALE_DEPLOYMENT_ENV: ', resty_env.value('THREESCALE_DEPLOYMENT_ENV'))
  ngx.log(ngx.WARN, 'my env IMV_IHOST: ', resty_env.value('IMV_IHOST'))
  ngx.log(ngx.WARN, 'my env IMV_METHOD: ', resty_env.value('IMV_METHOD'))

  for k, v in pairs(config) do
    ngx.log(ngx.ERR, k)
  end
  --ngx.log(ngx.WARN, "===Yaakov===>>>>> INPUT timout = ", self.timeout)
  --ngx.log(ngx.WARN, "===Yaakov===>>>>> INPUT URL = ", self.imvurl)
  --local ihost = ngx.var.IMV_IHOST
  --ngx.log(ngx.WARN, "===Yaakov===>>>>> ihost = ", ihost)
  --local imethod = ngx.var.IMV_METHOD
  --ngx.log(ngx.WARN, "===Yaakov===>>>>> imethod = ", imethod)
  --local ienv = ngx.var.THREESCALE_DEPLOYMENT_ENV
  --ngx.log(ngx.WARN, "===Yaakov===>>>>> ienv = ", ienv)
  --ngx.log(ngx.WARN, "===Yaakov===>>>>> os.getenv THREESCALE_DEPLOYMENT_ENV = ", os.getenv("THREESCALE_DEPLOYMENT_ENV"))
  --ngx.log(ngx.WARN, "===Yaakov===>>>>> os.getenv APICAST_DIR = ", os.getenv("APICAST_DIR"))
  --ngx.log(ngx.WARN, "===Yaakov===>>>>> os.getenv TZ = ", os.getenv("TZ"))
  

  --httpc = http.new()
  return self
end

function _M:init()
  -- do work when nginx master process starts
end

function _M:init_worker()
  -- do work when nginx worker process is forked from master
end

function _M:rewrite()
  -- change the request before it reaches upstream
end

function _M:access()
  -- ability to deny the request before it is sent upstream
  --ngx.log(ngx.ERR, "running access")
  --for k, v in pairs(resty_env.list()) do
  --  ngx.log(ngx.ERR, k .. ": " .. v)
  --end
  --if ngx.ctx.enabled ~= "true" then
  --  ngx.log(ngx.ERR, "config.enabled (" .. ngx.ctx.enabled .. ") != true!")
  --  return
  --end
  
  ngx.ctx.client = nil
  ngx.ctx.message_id = 0
  ngx.ctx.response_body = ""

  --ngx.ctx.message_id = math.floor(math.random () * 10000000000000)

  math.randomseed(seed())
  ngx.ctx.message_id = math.floor(math.random () * 10000000000000 + seed() * 10000)
  --ngx.log(ngx.ERR, "message ID: " .. tostring(ngx.ctx.message_id) .. " time: " .. tostring(socket.gettime()) .. " random: ".. tostring(math.random ()))

  -- getting all the request data can be gathered from the 'access' function

  local method = ngx.var.request_method
  local scheme = ngx.var.scheme
  local host = ngx.var.host
  local port = ngx.var.server_port
  local path = ngx.var.request_uri

  local headers = ngx.req.get_headers()
  ngx.req.read_body()
  local request_body = ngx.req.get_body_data()

  local url = scheme .. "://" .. host .. ":" .. port .. path -- .. query
  local headers_dict = {}
  local i = 1
  for k,v in pairs(headers) do
    headers_dict[i] = {
      name = k,
      value = v
    }
    i = i+1
  end
  local headers_json = cjson.encode(headers_dict)

  local full_body = ""
  if (request_body ~= nil and request_body ~= '') then
    full_body = request_body
  end
  
  send_request_info_to_imv_server(method, url, headers_dict, full_body, ngx.ctx.message_id)
  --send_to_tcp_imv_server(conf, full_request, 0, ngx.ctx.message_id)
end

function _M:content()
  -- can create content instead of connecting to upstream
end

function _M:post_action()
  -- do something after the response was sent to the client
end

function _M:header_filter()
  -- can change response headers
end

function _M:body_filter()
  -- can read and change response body
  -- https://github.com/openresty/lua-nginx-module/blob/master/README.markdown#body_filter_by_lua
  
  --if ngx.ctx.enabled ~= "true" then
  --  return
  --end
  
  -- getting pieces of the response_body from 'body_filter' function, concatenating them together
  local chunk = ngx.arg[1]
  if (ngx.ctx.response_body ~= nil and ngx.ctx.response_body ~= '') then
    ngx.ctx.response_body = ngx.ctx.response_body .. (chunk or "")
  else
    ngx.ctx.response_body = (chunk or "")
    --ngx.log(ngx.ERR,"no ctx.response_body in body_filter, only writing chunk:" .. ngx.ctx.response_body)
  end
end

function _M:log()
  -- can do extra logging
  ngx.log(ngx.ERR, "running log")

  --if ngx.ctx.enabled ~= "true" then
  --  return
  --end
  
  -- getting the response data from 'log', saving everything and sending to imv server
  local status = ngx.status
  --local headers = ngx.header
  local headers = ngx.resp.get_headers()
  --ngx.log(ngx.ERR, "status::: " .. status)
  
  local headers_dict = {}
  local i = 1
  for k,v in pairs(headers) do
    headers_dict[i] = {
      name = k,
      value = v
    }
    i = i+1
  end
  --local headers_json = cjson.encode(headers_dict)

  local full_body = ""
  if (ngx.ctx.response_body ~= nil and ngx.ctx.response_body ~= '') then
    full_body = ngx.ctx.response_body
  else
    ngx.log(ngx.ERR,"no ctx.response_body in log!")
  end

  if (ngx.ctx.message_id == 0 or ngx.ctx.message_id == nil) then
    ngx.log(ngx.ERR, "Got response without request, dropping message!!!")
    --ngx.ctx.message_id = 0
    return
  end

  send_response_info_to_imv_server(status, headers_dict, full_body, ngx.ctx.message_id)
  --send_to_tcp_imv_server(conf, full_response, 1, ngx.ctx.message_id)
  --close_tcp_connection()
end

function _M:balancer()
  -- use for example require('resty.balancer.round_robin').call to do load balancing
end

function send_request_info_to_imv_server(method, url, req_headers, req_body, message_id)
  --ngx.log(ngx.ERR, "send_request")
  local body_dict = {}
  body_dict["requestTimestamp"] = get_time()
  body_dict["transactionId"] = message_id
  body_dict["method"] = method
  body_dict["url"] = url
  body_dict["requestHeaders"] = req_headers
  body_dict["requestBody"] = req_body
  
  local body_json = cjson.encode(body_dict)
  
  ngx.timer.at(0,send_to_http_imv_server, body_json)
  --send_to_http_imv_server(false, body_json)
end

function send_response_info_to_imv_server(status_code, res_headers, res_body, message_id)
  --ngx.log(ngx.ERR, "send_respones")
  local body_dict = {}
  body_dict["responseTimestamp"] = get_time()
  body_dict["transactionId"] = message_id
  body_dict["statusCode"] = status_code
  body_dict["responseHeaders"] = res_headers
  body_dict["responseBody"] = res_body
  
  local body_json = cjson.encode(body_dict)
  --ngx.log(ngx.ERR, "sending response message with body: " .. body_json)
  ngx.timer.at(0, send_to_http_imv_server,body_json)
  --send_to_http_imv_server(body_json)
end

function send_to_http_imv_server(premature, payload)
  --ngx.log(ngx.ERR, "sending...")
  --ngx.log(ngx.ERR, "payload: " .. payload)
  --local imv_http_server_url = resty_env.get("aamp_scheme") .. "://".. resty_env.get("aamp_server_name") .. ":" .. resty_env.get("aamp_server_port") .."/" .. resty_env.get("aamp_endpoint")
  local imv_http_server_url = "http://100.25.160.207:5601/data"--.. resty_env.get("aamp_server_name") .. ":" .. resty_env.get("aamp_server_port") .."/" .. resty_env.get("aamp_endpoint")

  local timeout = 10000
  --if self.timeout then
  --  timeout = self.timeout
  --end
  --ngx.log(ngx.ERR, "sending " .. payload:len() .. " to POST " .. imv_http_server_url)
  local lhttpc = http.new()
  lhttpc:set_timeouts(timeout, timeout, timeout)
  lhttpc:request_uri(imv_http_server_url,{
    url = imv_http_server_url,
    method = "POST", --aamp_request_method,
    headers = {
      ["Accept"] = "application/json",
      ["Content-Type"] = "application/json",
      ["Content-Length"] = payload:len()
    },
    body = payload,
    --body = source = ltn12.source.string(payload),
    --sink = ltn12.sink.table(imv_body)
    keepalive = false
  })
  --ngx.log(ngx.ERR,"os.getenv: " .. os.getenv("aamp_scheme") .. "://".. os.getenv("aamp_server_name") .. ":" .. os.getenv("aamp_server_port") .."/" .. os.getenv("aamp_endpoint"))
  --ngx.log(ngx.ERR,"resty_env.get: " .. resty_env.get("aamp_scheme") .. "://".. resty_env.get("aamp_server_name") .. ":" .. resty_env.get("aamp_server_port") .."/" .. resty_env.get("aamp_endpoint"))
  --ngx.log(ngx.ERR,"resty_env.value: " .. resty_env.value("aamp_scheme") .. "://".. resty_env.value("aamp_server_name") .. ":" .. resty_env.value("aamp_server_port") .."/" .. resty_env.value("aamp_endpoint"))
  --ngx.log(ngx.ERR,"res: " .. res)-- .. ". code: " .. code)
  --ngx.log(ngx.NOTICE, "version: "..tostring(version)..", ts: "..tostring(ts)..", opcode: "..tostring(opcode)..", len: "..tostring(payload:len())..", message_id: "..tostring(message_id))
end

--function send_to_tcp_imv_server(conf, payload, opcode, message_id)
--    local client = get_tcp_connection(conf.host, conf.port)
--    if client == nil then
--        ngx.log(ngx.ERR, "Can't send data to ".. tostring(conf.host) .. ":" .. conf.port)
--        return
--    end

--    local data = ""
--    local version = 1
--    local ts = math.floor(socket.gettime() * 1000)
--    local total_len = payload:len()+1+1+4+4+8+8

    --converting manually in lua 5.l
--    data = write_format(true, "114488", version, opcode, total_len, 0, message_id, ts)
--    data = data .. payload

--    client:send(data)

    --ngx.log(ngx.NOTICE, "------------------ START DATA -----------------")
    --ngx.log(ngx.NOTICE, payload)
    --ngx.log(ngx.NOTICE, "****************** END DATA *******************")
--    ngx.log(ngx.NOTICE, "version: "..tostring(version)..", ts: "..tostring(ts)..", opcode: "..tostring(opcode)..", message_id: "..tostring(message_id)..", len: "..tostring(total_len))
--end

--function get_tcp_connection(host, port)
--    if ngx.ctx.client == nil then
--        ngx.ctx.client = socket.connect(host, port)
--        if ngx.ctx.client == nil then
--            return nil
--        end
--    end
--    return ngx.ctx.client
--end

--function close_tcp_connection()
--    if ngx.ctx.client ~= nil then
--        ngx.ctx.client:shutdown("both")
--        ngx.ctx.client = nil
--    end
--end

--function write_format(little_endian, format, ...)
--    local res = ''
--    local values = {...}
--    for i=1,#format do
--        local size = tonumber(format:sub(i,i))
--        local value = values[i]
--        local str = ""
--        for j=1,size do
--            str = str .. string.char(value % 256)
--            value = math.floor(value / 256)
--        end
--        if not little_endian then
--            str = string.reverse(str)
--        end
--        res = res .. str
--    end
--    return res
--end

function seed()
--  if package.loaded['socket'] and package.loaded['socket'].gettime then
--    seed = math.floor(package.loaded['socket'].gettime() * 100000)
--  else
  if ngx then
    --ngx.log(ngx.ERR,"seed is ngx.time()+ngx.worker.pid()")
    _M.m_seed = ngx.time() + ngx.worker.pid()

  else
    --ngx.log(ngx.ERR,"seed is os.time")
    _M.m_seed = os.time()
  end

  math.randomseed(_M.m_seed)
  --ngx.log(ngx.ERR,"seed: " .. _M.m_seed)
  return _M.m_seed
end

function get_time()
  
--  if package.loaded['socket'] and package.loaded['socket'].gettime then
--    return = math.floor(package.loaded['socket'].gettime() * 1000)
--  else
  if ngx then
    return ngx.time() * 1000 * 1000

  else
    return os.time() * 1000 * 1000
  end
end

return _M
