module("luci.controller.speedlimiter", package.seeall)
--copyright 2024-2025 sopeksemprit <sopeksemprit.xyz>
--Licensed under the Apache License 2.0.
function index()
    if not nixio.fs.access("/etc/config/speedlimiter") then return end
    entry({"admin", "control"}, firstchild(), "Control", 44).dependent = false

    local e = entry({"admin","control","speedlimiter"}, cbi("speedlimiter"), _("SpeedLimiter"), 10)
    e.dependent=false
    e.acl_depends = { "luci-app-speedlimiter" }
    entry({"admin","control","speedlimiter","status"}, call("act_status")).leaf = true
end

function act_status()
    local sys  = require "luci.sys"
    local e = {} 
     e.status = sys.call(" busybox ps -w | grep speedlimiter | grep -v grep  >/dev/null ") == 0  
    luci.http.prepare_content("application/json")
    luci.http.write_json(e)
end
