local core = require "sys.core"
local socket = require "sys.socket"
local dns = require "sys.dns"
local json = require "sys.json"
local crypto = require "sys.crypto"
local iconv = require "iconv"
local format = string.format
local match = string.match

local M = {}
local mt = {__index = M, __gc = function(obj)
	if obj.fd then
		socket.close(fd)
	end
end}
function M:create(conf)
	local ip = dns.resolve(conf.addr)
	local port = conf.port
	local obj = {
		idx = 0,
		fd = socket.connect(ip .. ":" .. port),
		user = conf.user,
		passwd = conf.passwd,
	}
	local ret = socket.readline(obj.fd)
	return setmetatable(obj, mt)
end

function M:close()
	socket.close(self.fd)
	self.fd = nil
end

local function split(str)
	local fields = {}
	for s in str:gmatch('([^%s]+)') do
		fields[#fields + 1] = s
	end
	return fields
end

local function readresponse(fd)
	local left = 0
	local res = socket.readline(fd, "\n")
	--io.stdout:write(">:", res)
	if res:find("(", 1, true) then
		left = 1
	end
	if res:find(")", 1, true) then
		left = 0
	end
	local buf = split(res)
	if left > 0 then
		while left > 0 do
			local l = socket.readline(fd, "\n")
			--io.stdout:write(">:", l)
			if l:find("(", 1, true) then
				left = left + 1
			end
			if l:find(")", 1, true) then
				left = left - 1
			end
			l = l:sub(1, -3)
			buf[#buf + 1] = l
		end
	end
	return buf
end

local function rfc3501(self, cmd, ...)
	local ret = {}
	local fd = self.fd
	local idx = 1 + self.idx
	self.idx = idx
	local id = format("%s", idx)
	local cmd = table.concat({id, cmd, ...}, " ")
	socket.write(fd, cmd .. "\n")
	while true do
		local fields = readresponse(fd)
		if not fields then
			return
		end
		ret[#ret + 1] = fields
		if fields[1] == id then
			assert(fields[2] == "OK", cmd)
			break
		end
	end
	return ret
end

function M:login()
	rfc3501(self, "login", self.user, self.passwd)
	rfc3501(self, "id", '("name" "silly" "version" "0.3.0")')
end

function M:select(box)
	rfc3501(self, "select", box)
end

function M:search(text, time)
	local list = {}
	local date = os.date("%d-%b-%Y", time)
	local ret = rfc3501(self, "SEARCH CHARSET UTF-8",
		"SUBJECT", text, "since", date)
	for _, v in pairs(ret) do
		if v[1] == "*" and v[2] == "SEARCH" then
			table.move(v, 3, #v, #list+1, list)
		end
	end
	return list
end


local decode_pattern = "=%?([^%?]+)%?(%a)%?([^%?]+)%?="

local function toutf8(charset, encode, str)
	assert(encode == "B")
	local cd = iconv.open("utf-8", charset)
	return cd:iconv(crypto.base64decode(str))
end

local function skip(list, start)
	for i = start, #list do
		local l = list[i]
		if not l:find("^[%s]") then
			return i
		end
	end
	return #list + 1
end

local function multiline(list, start)
	local buf = {list[start]}
	start = start + 1
	while start <= #list do
		local l = list[start]
		if not l:find("^[%s]") then
			break
		end
		start = start + 1
		buf[#buf + 1] = l
	end
	return start, table.concat(buf)
end

local function from(obj, list, start)
	local l = list[start]
	obj.from = l:gsub(decode_pattern, toutf8)
	return start + 1
end

local function date(obj, list, start)
	local l = list[start]
	obj.date = l:match('Date:%s+([^%s]+)')
	return start + 1
end

local function subject(obj, list, start)
	local start, l = multiline(list, start)
	obj.subject = l:gsub(decode_pattern, toutf8)
	return start
end

local function content_type(obj, list, start)
	local typ = "Content-Type:"
	local start, l = multiline(list, start)
	local f1 = l:sub(1, #typ)
	assert(f1 == typ)
	local f2, f3 = l:match("Content%-Type:%s*([^;]+);%s*([^%s]+)")
	--print(l, f2, f3)
	if f2:find("multipart") then
		local key, val = f3:match('([^=]+)="([^"]+)"')
		assert(key == "boundary")
		obj.boundary = "--" .. val
	elseif f2 == "text/html" then
		local key, val = f3:match([[([^=]+)="?([^'"%s]+)"?]])
		--print("charset", f3, val)
		assert(key == "charset", f3)
		obj.charset = val
	else
		assert(false, typ)
	end
	return start
end

local function encoding(obj, list, start)
	local l = list[start]
	obj.encoding = l:match('Content%-Transfer%-Encoding:%s*([^%s]+)')
	return start + 1
end

local switch = {
	["From:"] = from,
	["Date:"] = date,
	["Subject:"] = subject,
	["Content-Type:"] = content_type,
	["Content-Transfer-Encoding:"] = encoding,
}

local function parseheader(obj, list, start)
	--header
	while start <= #list do
		local l = list[start]
		if l == "" then
			--body
			start = start + 1
			break
		end
		local field = l:match("^([^%s]+)")
		local cb = switch[field]
		if not cb then
			start = skip(list, start+1)
		else
			start = cb(obj, list, start)
		end
	end
	return start
end

local switch_decoding = {
	["base64"] = crypto.base64decode,
	["quoted-printable"] = function(l)
		local char = string.char
		local tonumber = tonumber
		return l:gsub("=+(%x%x)", function(str)
			return char(tonumber(str, 16))
		end)
	end
}

local function rfc822(list, start)
	local obj = {
		from = false,
		date = false,
		subject = false,
		content_type = false,
		boundary = false,
		charset = false,
		encoding = false,
	}
	local body = {}
	start = parseheader(obj, list, start)
	if obj.boundary then --mutipart
		assert(list[start] == obj.boundary, list[start])
		start = parseheader(obj, list, start+1)
	end
	for i = start, #list do
		local l = list[i]
		if obj.boundary and l:find(obj.boundary) then
			break
		elseif l == ")" then
			break
		end
		body[#body + 1] = l
	end
	body = table.concat(body)
	local decoding = switch_decoding[obj.encoding]
	assert(decoding, obj.encoding)
	body = decoding(body)
	local charset = body:match("charset=([%w%-%d]+)")
	obj.charset = charset or obj.charset
	assert(obj.charset, charset)
	obj.charset = obj.charset:lower()
	local cd = iconv.open("utf-8", obj.charset)
	obj.body = cd:iconv(body)
	return obj
end

function M:fetch(num)
	local ret = rfc3501(self, "fetch", num, "rfc822")
	return rfc822(ret[1], 6)
end

return M

