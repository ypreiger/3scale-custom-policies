local setmetatable = setmetatable

local _M = require('apicast.policy').new('MonitorViaImVision', '0.1')
local mt = { __index = _M }
socket = require("luasocket")
--http = require("socket.http")

function _M.new()
  return setmetatable({}, mt)
end

function _M:init()
  -- do work when nginx master process starts
  --socket.TIMEOUT = config.timeout
  socket.TIMEOUT = 60
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

  math.randomseed(math.floor(socket.gettime() * 100000))
  ngx.ctx.message_id = math.floor(math.random () * 10000000000000 + socket.gettime() * 10000)
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

  local method = ngx.var.aamp_request_method
  local scheme = ngx.var.aamp_scheme
  local host = ngx.var.aamp_server_name
  local port = ngx.var.aamp_server_port
  local path = ngx.var.aamp_request_uri
  
  local args, err = ngx.req.get_uri_args()
  if err == "truncated" then
    -- one can choose to ignore or reject the current request here
    return
  end
  local query = ""
  for key, val in pairs(args) do
    if len(query)>0 then
      query = query .. "&"
    if type(val) == "table" then
      query = query .. key .. "=" .. table.concat(val, "&" .. key .. "=")
    else
      query = query .. key .. "=" .. val
    end
      end
  end
  --query = cjson.table2json(query)   path.. "?" .. query
  --ngx.log(ngx.ERR, "Can  query ".. tostring(query))
  local headers = ngx.req.get_headers()
  ngx.req.read_body()
  local request_body = ngx.req.get_body_data()

  local full_request = method .. " " .. scheme .. "://" .. host .. ":" .. port .. "/" .. path .. "?" .. query .. " HTTP/1.1\n"
  local is_chunked = false
  for k,v in pairs(headers) do
    if (k == "Transfer-Encoding" or k == "transfer-encoding") and v == "chunked" then
      is_chunked = true
    end
    full_request = full_request .. k .. ": ".. v .. "\n"
  end

  if (request_body ~= nil and request_body ~= '') then
    if is_chunked then
      local hex_len = string.format("%x", request_body:len())
      full_request = full_request .. "\n" .. hex_len .."\n" .. request_body .. "\n0\n"
    else
      full_request = full_request .. "\n" .. request_body
    end
  end
  
  --send_to_http_imv_server(conf, full_request, 0, ngx.ctx.message_id)
  send_to_tcp_imv_server(conf, full_request, 0, ngx.ctx.message_id)
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
  
  local full_response = "HTTP/1.1 " .. tostring(status) .. "\n"
  local is_chunked = false
  headers["transfer-encoding"] = "chunked"
  for k,v in pairs(headers) do
    if (k == "Transfer-Encoding" or k == "transfer-encoding") and v == "chunked" then
      is_chunked = true
    end
    full_response = full_response .. k .. ": ".. v .. "\n"
  
  end
  full_response = full_response .. "Content-Type" .. ": ".. "application/json" .. "\n"

  if (ngx.ctx.response_body ~= nil and ngx.ctx.response_body ~= '') then
    if is_chunked then
      local hex_len = string.format("%x", ngx.ctx.response_body:len())
      full_response = full_response .. "\n" .. hex_len .."\n" .. ngx.ctx.response_body .. "\n0\n"
    else
      full_response = full_response .. "\n" .. ngx.ctx.response_body
    end

  end

  if ngx.ctx.message_id == 0 then
    ngx.log(ngx.ERR, "Got response without request, sending with message id 0")
  end

  --send_to_http_imv_server(conf, full_response, 1, ngx.ctx.message_id)
  send_to_tcp_imv_server(conf, full_response, 1, ngx.ctx.message_id)
  close_tcp_connection()
end

function _M:balancer()
  -- use for example require('resty.balancer.round_robin').call to do load balancing
end

function send_to_http_imv_server(conf, payload, opcode, message_id)

    local imv_http_server_url = "http://".. conf.host .. ":" .. conf.port .."/"
    local ts = math.floor(socket.gettime() * 1000)

    local data = {}
    data["version"] = 1
    data["opcode"] = opcode
    data["flags"] = 0
    data["message_id"] = message_id
    data["timestamp"] = ts
    data["message"] = payload

    local data_json = cjson.encode(data)

    local imv_response_body = { }
    local res, code, response_headers, status = http.request {
      url = imv_http_server_url,
      method = "POST",
      headers = {
          ["Content-Type"] = "application/json",
          ["Content-Length"] = data_json:len()
      },
      source = ltn12.source.string(data_json),
      sink = ltn12.sink.table(imv_response_body)
    }
    --ngx.log(ngx.NOTICE, "version: "..tostring(version)..", ts: "..tostring(ts)..", opcode: "..tostring(opcode)..", len: "..tostring(payload:len())..", message_id: "..tostring(message_id))
end

function send_to_tcp_imv_server(conf, payload, opcode, message_id)
    local client = get_tcp_connection(conf.host, conf.port)
    if client == nil then
        ngx.log(ngx.ERR, "Can't send data to ".. tostring(conf.host) .. ":" .. conf.port)
        return
    end

    local data = ""
    local version = 1
    local ts = math.floor(socket.gettime() * 1000)
    local total_len = payload:len()+1+1+4+4+8+8

    --converting manually in lua 5.l
    data = write_format(true, "114488", version, opcode, total_len, 0, message_id, ts)
    data = data .. payload

    client:send(data)

    --ngx.log(ngx.NOTICE, "------------------ START DATA -----------------")
    --ngx.log(ngx.NOTICE, payload)
    --ngx.log(ngx.NOTICE, "****************** END DATA *******************")
    ngx.log(ngx.NOTICE, "version: "..tostring(version)..", ts: "..tostring(ts)..", opcode: "..tostring(opcode)..", message_id: "..tostring(message_id)..", len: "..tostring(total_len))
end

function get_tcp_connection(host, port)
    if ngx.ctx.client == nil then
        ngx.ctx.client = socket.connect(host, port)
        if ngx.ctx.client == nil then
            return nil
        end
    end
    return ngx.ctx.client
end

function close_tcp_connection()
    if ngx.ctx.client ~= nil then
        ngx.ctx.client:shutdown("both")
        ngx.ctx.client = nil
    end
end

function write_format(little_endian, format, ...)
    local res = ''
    local values = {...}
    for i=1,#format do
        local size = tonumber(format:sub(i,i))
        local value = values[i]
        local str = ""
        for j=1,size do
            str = str .. string.char(value % 256)
            value = math.floor(value / 256)
        end
        if not little_endian then
            str = string.reverse(str)
        end
        res = res .. str
    end
    return res
end

return _M
