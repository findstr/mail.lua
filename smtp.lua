local socket = require "socket"
local dns = require "dns"
local crypt = require "crypt"
local format = string.format
local match = string.match

local smtp = {}

local function try(func, ...)
	local ok, res1, res2 = pcall(func, ...)
	if not ok then
		err = match(res1, ".*:(.*)")
	else
		ok, res1 = res1, res2
	end
	return ok, res1
end

local function checkstatus(fd, line, status, err)
	local s = match(line, "([0-9]+)")
	if s ~= status then
		socket.close(fd)
		assert(false, err .. s)
	end
end

local function connect(msg)
	local port = 25
	local from = msg["FROM"]
	local ip = match(from, ".*@(.*)")
	assert(ip, "invalid email addr")
	ip = "smtp." .. ip
	if dns.isdomain(ip) then
		ip = dns.query(ip)
		if not ip then
			assert(false, "smtp server domain resolve fail")
		end
	end
	ip = format("%s@%s", ip, port)
	local s = socket.connect(ip)
	assert(s, "connect fail")
	local l = socket.readline(s)
	assert(l, "socket read disconnect")
	checkstatus(s, l, "220", "stmp server status:")
	return s
end

local function quit(s)
	local n = "QUIT\r\n"
	local ok = socket.write(s, n)
	assert(ok, "quit socket disconnect")
	local l = socket.readline(s)
	assert(l, "quit socket disconnect")
	socket.close(s)
end

local function hello(s)
	local cmd = format("HELO %d \r\n", math.random(1, 4096))
	local ok = socket.write(s, cmd)
	assert(ok, "smtp hello write disconnect")
	local l = socket.readline(s)
	assert(l, "smtp hello read disconnect")
	checkstatus(s, l, "250", "smtp hello read error:")
end

local function login(s, msg)
	local usr = msg["FROM"]
	usr = match(usr, "(.*)@")
	local passwd = msg["PASSWD"]
	local ok = socket.write(s, "AUTH LOGIN\r\n")
	assert(ok, "smtp login write disconnect")
	local l = socket.readline(s)
	assert(l, "smtp login read disconnect")
	checkstatus(s, l, "334", "smtp login command error:")
	--user
	local usr = crypt.base64encode(usr) .. "\r\n"
	ok= socket.write(s, usr)
	assert(ok, "smtp login write disconnect")
	l = socket.readline(s)
	assert(l, "smtp login read disconnect")
	checkstatus(s, l, "334", "stmp login user error:")
	--passwd
	local passwd = crypt.base64encode(passwd) .. "\r\n"
	ok = socket.write(s, passwd)
	assert(ok, "smtp login passwd write disconnect")
	l = socket.readline(s)
	assert(l, "smtp login passwd read  disconnect")
	checkstatus(s, l, "235", "stmp login auth:")
end

local function addrinfo(s, msg)
	local ok, l
	--from
	local from = format("MAIL FROM: <%s>\r\n", msg["FROM"])
	ok = socket.write(s, from)
	assert(ok, "smtp from write disconnect")
	l = socket.readline(s)
	checkstatus(s, l, "250", "smtp from:")
	--to
	local to = msg["TO"]
	to = format("RCPT TO:<%s>\r\n", to)
	ok = socket.write(s, to)
	assert(ok, "smtp to write disconnect")
	l = socket.readline(s)
	assert(l, "smtp to read disconnect")
	checkstatus(s, l, "250", "smtp from to err:")
end

local function body(s, msg)
	local ok, l
	ok = socket.write(s, "DATA\r\n")
	assert(ok, "smtp body write disconnect")
	l = socket.readline(s)
	assert(l, "smtp body read disconnect")
	checkstatus(s, l, "354", "smtp body head")
	local subject = format("From: <%s>\r\nTo:<%s>\r\nSubject:%s\r\n\r\n",
		msg["FROM"], msg["TO"], msg["SUBJECT"])
	subject = subject .. msg["CONTENT"] .. "\r\n.\r\n"
	ok = socket.write(s, subject)
	assert(ok, "smtp body send disconnect")
	l = socket.readline(s)
	assert(l, "smtp body read ack disconnect")
	checkstatus(s, l, "250", "smtp body subject")
end

local function smtp_process(msg)
	local fd = connect(msg)
	hello(fd)
	login(fd, msg)
	addrinfo(fd, msg)
	body(fd, msg)
	quit(fd)
	return true
end

function smtp.send(msg)
	return try(smtp_process, msg)
end

return smtp

