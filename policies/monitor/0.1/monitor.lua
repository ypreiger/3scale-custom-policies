local setmetatable = setmetatable

local _M = require('apicast.policy').new('MonitorViaImVision', '0.1')
local mt = { __index = _M }
require("http")

function _M.new()
  httpc = http.new()
  return setmetatable({}, mt)
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
  if config.enabled ~= "true" then
    return
  end
  
  ngx.ctx.client = nil
  ngx.ctx.message_id = 0
  ngx.ctx.response_body = ""

  --ngx.ctx.message_id = math.floor(math.random () * 10000000000000)

  math.randomseed(seed())
  ngx.ctx.message_id = math.floor(math.random () * 10000000000000 + seed() * 10000)
  --ngx.log(ngx.ERR, "message ID: " .. tostring(ngx.ctx.message_id) .. " time: " .. tostring(socket.gettime()) .. " random: ".. tostring(math.random ()))

  -- getting all the request data can be gathered from the 'access' function
  --local method = kong.request.get_method()
  --local scheme = kong.request.get_scheme()
  --local host = kong.request.get_host()
  --local port = kong.request.get_port()
  --local path = kong.request.get_path()
  --local query = kong.request.get_raw_query()
  --local headers = kong.request.get_headers()
  --local request_body = kong.request.get_raw_body()
  
  local method = ngx.var.request_method
  local scheme = ngx.var.scheme
  local host = ngx.var.server_name
  local port = ngx.var.server_port
  local path = ngx.var.request_uri
  
  local args, err = ngx.req.get_uri_args()
  if err == "truncated" then
    -- one can choose to ignore or reject the current request here
    return
  end
  local query = ""
  for key, val in pairs(args) do
    if len(query)>0 then
      query = query .. "&"
    end
    if type(val) == "table" then
      query = query .. key .. "=" .. table.concat(val, "&" .. key .. "=")
    else
      query = query .. key .. "=" .. val
    end
  end
  --query = cjson.table2json(query)   path.. "?" .. query
  --ngx.log(ngx.ERR, "Can  query ".. tostring(query))
  local headers = ngx.req.get_headers()
  ngx.req.read_body()
  local request_body = ngx.req.get_body_data()

  local url = scheme .. "://" .. host .. ":" .. port .. "/" .. path .. "?" .. query
  local headers_json = "["
  for k,v in pairs(headers) do
    if first == true then
      first = false
    else
      headers_json = headers_json .. ","
    end
    headers_json = headers_json .. "{\"name\": " .. k .. ", \"value\": " .. v .. "}"
  end
  headers_json = headers_json .. "]"

  local full_body = ""
  if (request_body ~= nil and request_body ~= '') then
    full_body = request_body
  end
  
  send_request_info_to_imv_server(method, url, headers_json, full_body, ngx.ctx.message_id)
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
  
  if config.enabled ~= "true" then
    return
  end
  
  -- getting pieces of the response_body from 'body_filter' function, concatenating them together
  local chunk = ngx.arg[1]
  ngx.ctx.response_body = ngx.ctx.response_body .. (chunk or "")
end

function _M:log()
  -- can do extra logging
  
  if config.enabled ~= "true" then
    return
  end
  
  -- getting the response data from 'log', saving everything and sending to imv server
  local status = ngx.status
  --local headers = ngx.header
  local headers = ngx.resp.get_headers()
  --ngx.log(ngx.ERR, "status::: " .. status)
  
  local is_chunked = false
  local first = true
  local headers_json = "["
  for k,v in pairs(headers) do
    if first == true then
      first = false
    else
      headers_json = headers_json .. ","
    end
    headers_json = headers_json .. "{\"name\": " .. k .. ", \"value\": " .. v .. "}"
  end
  headers_json = headers_json .. "]"

  local full_body = ""
  if (ngx.ctx.response_body ~= nil and ngx.ctx.response_body ~= '') then
    full_body = ngx.ctx.response_body
  end

  if ngx.ctx.message_id == 0 then
    ngx.log(ngx.ERR, "Got response without request, sending with message id 0")
  end

  send_response_info_to_imv_server(status, headers_json, full_body, ngx.ctx.message_id)
  --send_to_tcp_imv_server(conf, full_response, 1, ngx.ctx.message_id)
  --close_tcp_connection()
end

function _M:balancer()
  -- use for example require('resty.balancer.round_robin').call to do load balancing
end

function send_request_info_to_imv_server(method, url, req_headers, req_body, message_id)
  local body_dict = {}
  body_dict["requestTimestamp"] = get_time()
  body_dict["transactionId"] = message_id
  body_dict["method"] = method
  body_dict["url"] = url
  body_dict["requestHeaders"] = req_headers
  body_dict["requestBody"] = req_body
  
  local body_json = cjson.encode(body_dict)
  
  send_to_http_imv_server(body_json)
end

function send_response_info_to_imv_server(status_code, res_headers, res_body, message_id)
  local body_dict = {}
  body_dict["responseTimestamp"] = get_time()
  body_dict["transactionId"] = message_id
  body_dict["statusCode"] = status_code
  body_dict["responseHeaders"] = res_headers
  body_dict["responseBody"] = res_body
  
  local body_json = cjson.encode(body_dict)
  
  send_to_http_imv_server(body_json)
end

function send_to_http_imv_server(payload)

  local imv_http_server_url = aamp_scheme .. "://".. aamp_server_name .. ":" .. aamp_server_port .."/" .. aamp_endpoint

  local imv_body = { }
  local res, code, response_headers, status = httpc.request {
    url = imv_http_server_url,
    method = aamp_request_method,
    headers = {
      ["Accept"] = "application/json",
      ["Content-Type"] = "application/json",
      ["Content-Length"] = data_json:len()
    },
    body = payload
    --body = source = ltn12.source.string(payload),
    --sink = ltn12.sink.table(imv_body)
  }
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

function _M.seed()
  if seed then
    math.randomseed(seed)
    return math.randomseed(seed)
  end
--  if package.loaded['socket'] and package.loaded['socket'].gettime then
--    seed = math.floor(package.loaded['socket'].gettime() * 100000)
--  else
  if ngx then
    seed = ngx.time() + ngx.worker.pid()

  else
    seed = os.time()
  end

  math.randomseed(seed)

  return math.randomseed(seed)
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
