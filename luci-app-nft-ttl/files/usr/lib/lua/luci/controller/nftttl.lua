module("luci.controller.nftttl", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/nftttl") then return end
	entry({"admin", "modem", "nftttl"}, cbi("nftttl"), _("TTL Settings"), 60).acl_depends = { "luci-app-nft-ttl" }

	-- Tambah endpoint JSON untuk log & ping
	entry({"admin", "modem", "nftttl", "action"}, call("handle_action")).leaf = true
end

function handle_action()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local fs  = require "nixio.fs"
	local action = http.formvalue("status") or ""

	if action == "log" then
		local data = fs.readfile("/tmp/ttl_action.log") or "No log available."
		http.prepare_content("text/plain")
		http.write(data)
	elseif action == "pingtest" then
		local res = sys.exec("ping -c 4 -W 1 google.com 2>&1")
		http.prepare_content("text/plain")
		http.write(res)
	else
		http.status(400, "Invalid Request")
	end
end


