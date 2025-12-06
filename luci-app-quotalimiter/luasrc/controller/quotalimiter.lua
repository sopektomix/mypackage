-- Copyright 2024-2025 sopeksemprit <www.sopeksemprit.xyz>
module("luci.controller.quotalimiter", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/quotalimiter") then
		return
	end

	-- main page under Services
	entry({"admin", "services", "quotalimiter"},
		cbi("quotalimiter"),
		_("QuotaLimiter"), 60)
		
	-- log endpoint
	entry({"admin", "services", "quotalimiter", "log"},
		call("action_log"),
		nil).leaf = true
		
	-- clear log endpoint
	entry({"admin", "services", "quotalimiter", "clear_log"},
		call("action_clear_log"),
		nil).leaf = true
		
	-- service control endpoints (TAMBAHAN BARU)
	entry({"admin", "services", "quotalimiter", "start"},
		call("action_start"),
		nil).leaf = true
		
	entry({"admin", "services", "quotalimiter", "stop"},
		call("action_stop"),
		nil).leaf = true
		
	entry({"admin", "services", "quotalimiter", "restart"},
		call("action_restart"),
		nil).leaf = true
end

-- Function to get log
function action_log()
	local fs = require "nixio.fs"
	local http = require "luci.http"
	local uci = require "luci.model.uci".cursor()
	
	local log_path = uci:get("quotalimiter", "settings", "log_file") or "/var/log/quotalimiter.log"
	local data = ""
	
	if fs.access(log_path) then
		data = fs.readfile(log_path) or ""
	end
	
	http.prepare_content("text/plain")
	http.write(data or "")
end

-- Function to clear log
function action_clear_log()
	local fs = require "nixio.fs"
	local http = require "luci.http"
	local uci = require "luci.model.uci".cursor()
	
	local log_path = uci:get("quotalimiter", "settings", "log_file") or "/var/log/quotalimiter.log"
	
	fs.writefile(log_path, "")
	
	http.prepare_content("text/plain")
	http.write("Log cleared")
end

-- NEW: Function to start service
function action_start()
	local sys = require "luci.sys"
	local http = require "luci.http"
	
	-- Start the service
	sys.call("/etc/init.d/quotalimiter start >/dev/null 2>&1")
	
	-- Wait a bit
	sys.call("sleep 2")
	
	http.prepare_content("text/plain")
	http.write("Service started")
end

-- NEW: Function to stop service
function action_stop()
	local sys = require "luci.sys"
	local http = require "luci.http"
	
	-- Stop the service
	sys.call("/etc/init.d/quotalimiter stop >/dev/null 2>&1")
	
	http.prepare_content("text/plain")
	http.write("Service stopped")
end

-- NEW: Function to restart service
function action_restart()
	local sys = require "luci.sys"
	local http = require "luci.http"
	
	-- Restart the service
	sys.call("/etc/init.d/quotalimiter restart >/dev/null 2>&1")
	
	-- Wait a bit
	sys.call("sleep 2")
	
	http.prepare_content("text/plain")
	http.write("Service restarted")
end
