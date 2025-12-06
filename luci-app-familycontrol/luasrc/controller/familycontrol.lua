module("luci.controller.familycontrol", package.seeall)

function index()
	local fs = require "nixio.fs"
	if not fs.access("/etc/config/familycontrol") then
		return
	end

	-- main menu
	entry({"admin", "control"}, firstchild(), "Control", 44).dependent = false
	local e = entry({"admin", "control", "familycontrol"}, firstchild(), _("Internet Family Control"), 2)
	e.dependent   = false
	e.acl_depends = { "luci-app-FamilyControl" }

	-- Family time control (model: /usr/lib/lua/luci/model/cbi/familycontrol.lua)
	entry({"admin", "control", "familycontrol", "device"},
		cbi("familycontrol"), _("Family time control"), 10).leaf = true

	-- Web URL control (model: /usr/lib/lua/luci/model/cbi/weburl.lua)
	entry({"admin", "control", "familycontrol", "weburl"},
		cbi("weburl"), _("Web URL control"), 20).leaf = true

	-- TAK ADA LAGI tab Control log – log hanya dalam page Family time control

	-- Status endpoint untuk JS di template index
	entry({"admin", "control", "familycontrol", "status"},
		call("status")).leaf = true
end

function status()
	local sys  = require "luci.sys"
	local http = require "luci.http"

	local e = {}

	-- Guna pidof, confirm process daemon hidup
	e.status = (sys.call("pidof familycontrolctrl >/dev/null 2>&1") == 0)

	http.prepare_content("application/json")
	http.write_json(e)
end

