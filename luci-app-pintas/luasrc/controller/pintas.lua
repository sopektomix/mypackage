module("luci.controller.pintas", package.seeall)

function index()
    entry({"admin", "modem", "pintas"}, alias("admin", "modem", "pintas", "main"), _("Pintas AT Command"), 60)
    entry({"admin", "modem", "pintas", "main"}, cbi("pintas/main"), _("Main Interface"), 1)
    entry({"admin", "modem", "pintas", "log"}, call("action_log"), _("Live Log"), 2)
    entry({"admin", "modem", "pintas", "run"}, call("action_run_command"), nil)
end

local function execute_at_command(command)
    local uci = require "luci.model.uci".cursor()
    local device = uci:get("pintas", "config", "device") or "/dev/ttyUSB2"
    
    local util = require "luci.util"
    local result = util.exec(string.format('echo "%s" | atinout - %s - 2>&1', command, device))
    
    return result or ""
end

function action_run_command()
    local http = require "luci.http"
    local command = http.formvalue("command")
    
    if command then
        local result = execute_at_command(command)
        http.prepare_content("application/json")
        http.write_json({ success = true, output = result })
    else
        http.status(400, "Bad Request")
        http.prepare_content("application/json")
        http.write_json({ success = false, error = "No command provided" })
    end
end

function action_log()
    luci.template.render("pintas/log", {})
end
