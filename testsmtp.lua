local core = require "silly.core"
local smtp = require "smtp"

core.start(function()
	local msg = {
		["FROM"] = "findstr@sina.com",
		["TO"] = "909601686@qq.com",
		["SUBJECT"] = "auth",
		["CONTENT"] = "hello test",
		["PASSWD"] = "testpasswd",
	}
	local ok, err = smtp.send(msg)
	print(ok, err)
end)

