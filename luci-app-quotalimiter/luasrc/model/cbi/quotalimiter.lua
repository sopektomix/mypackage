-- Copyright 2024-2025 sopeksemprit <www.sopeksemprit.xyz>

local sys  = require "luci.sys"
local fs   = require "nixio.fs"
local uci  = require "luci.model.uci".cursor()

local m = Map("quotalimiter", translate("QuotaLimiter"),
	translate("Limit internet data usage per device (IP/MAC)."))
	
-- restart daemon setiap kali apply
function m.on_after_commit(self)
	sys.call("/etc/init.d/quotalimiter restart >/dev/null 2>&1")
end

-- ===== NOTICE HEADER =====
local s_notice = m:section(SimpleSection)
s_notice.template = "quotalimiter/notice"

-- ===== GLOBAL SETTINGS =====
local s = m:section(NamedSection, "settings", "global", translate("Global Settings"))
s.anonymous = true

-- Enable service
local enabled = s:option(Flag, "enabled", translate("Enable QuotaLimiter"))
enabled.rmempty = false

-- Backend selection
local backend = s:option(ListValue, "backend", translate("Firewall backend"))
backend:value("auto", translate("Auto detect"))
backend:value("iptables", "iptables")
backend:value("nftables", "nftables")
backend.default = "auto"

-- Poll interval
local poll = s:option(Value, "poll_interval", translate("Update interval (seconds)"))
poll.datatype  = "uinteger"
poll.default   = "30"
poll.rmempty   = false

-- Log file path (FIXED typo)
local logfile = s:option(Value, "log_file", translate("Log file path"))
logfile.default = "/var/log/quotalimiter.log"
logfile.rmempty = false

-- Reset button
local reset_btn = s:option(Button, "_reset_quota", translate("Reset all quota usage"))
reset_btn.inputtitle = translate("Reset now")
reset_btn.inputstyle = "apply"
function reset_btn.write(self, section)
	sys.call("/usr/bin/quotalimiter.sh reset >/dev/null 2>&1")
	luci.http.redirect(luci.dispatcher.build_url("admin/services/quotalimiter"))
end

-- ===== STATUS SECTION =====
local s_status = m:section(SimpleSection, nil, translate("Service Status"))
s_status.template = "quotalimiter/status"

-- ===== DEVICE AUTO-DETECTION =====
local function collect_clients()
    local clients = {}
    local seen = {}
    
    -- Use the shell script to detect devices
    local detected = sys.exec("/usr/bin/quotalimiter.sh devices 2>/dev/null") or ""
    
    for line in detected:gmatch("[^\r\n]+") do
        if not line:match("^#") and line ~= "" then
            local ip, status, hostname, mac = line:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)")
            if ip and mac then
                local key = mac .. "|" .. ip
                if not seen[key] then
                    seen[key] = true
                    table.insert(clients, {
                        mac = mac,
                        ip = ip,
                        hostname = hostname,
                        status = status,
                        display = string.format("%s (%s) - %s", ip, status, hostname)
                    })
                end
            end
        end
    end
    
    -- If still no devices, show sample devices
    if #clients == 0 then
        table.insert(clients, {
            mac = "AA:BB:CC:DD:EE:01",
            ip = "192.168.1.100",
            hostname = "John-Phone.lan",
            status = "REACHABLE",
            display = "192.168.1.100 (REACHABLE) - John-Phone.lan"
        })
        table.insert(clients, {
            mac = "11:22:33:44:55:66",
            ip = "192.168.1.150",
            hostname = "Living-Room-TV.lan",
            status = "REACHABLE",
            display = "192.168.1.150 (REACHABLE) - Living-Room-TV.lan"
        })
    end
    
    -- Sort by IP
    table.sort(clients, function(a, b)
        return (a.ip or "") < (b.ip or "")
    end)
    
    return clients
end

local online_clients = collect_clients()

-- ===== QUOTA RULES =====
local q = m:section(TypedSection, "quota", translate("Quota Rules"))
q.template = "cbi/tblsection"
q.anonymous = true
q.addremove = true
q.sortable = false

-- Enable rule
local q_enabled = q:option(Flag, "enabled", translate("Enable"))
q_enabled.rmempty = false

-- Comment
local comment = q:option(Value, "comment", translate("Device Name"))
comment.placeholder = "e.g., John's Phone"
comment.rmempty = true

-- Device selector dropdown
local dev = q:option(ListValue, "_device", translate("Device (hostname / MAC / IP)"))
dev.rmempty = true
dev:value("", "-- custom --")

-- Add all detected clients
for _, client in ipairs(online_clients) do
    dev:value(client.mac .. "|" .. client.ip, client.display)
end

function dev.cfgvalue(self, section)
    local mac = m:get(section, "mac") or ""
    local ip = m:get(section, "ip") or ""
    if mac ~= "" and ip ~= "" then
        return mac .. "|" .. ip
    end
    return ""
end

function dev.write(self, section, value)
    if value and value ~= "" then
        local mac, ip = value:match("^(.-)|(.*)$")
        if mac and mac ~= "" then
            m:set(section, "mac", mac:upper())
        end
        if ip and ip ~= "" then
            m:set(section, "ip", ip)
        end
    end
end

-- MAC Address
local mac_addr = q:option(Value, "mac", translate("MAC Address"))
mac_addr.placeholder = "AA:BB:CC:DD:EE:FF"
mac_addr.rmempty = true
mac_addr:depends("_device", "")

-- IP Address
local ip_addr = q:option(Value, "ip", translate("IP Address"))
ip_addr.placeholder = "192.168.1.100"
ip_addr.datatype = "ipaddr"
ip_addr.rmempty = true
ip_addr:depends("_device", "")

-- Quota limit
local limit = q:option(Value, "limit", translate("Limit"))
limit.datatype = "uinteger"
limit.default = "1"
limit.rmempty = false

-- Unit
local unit = q:option(ListValue, "unit", translate("Unit"))
unit:value("MB", "MB")
unit:value("GB", "GB")
unit.default = "GB"

-- Period
local period = q:option(ListValue, "period", translate("Reset Period"))
period:value("hour", translate("Hourly"))
period:value("day", translate("Daily"))
period:value("week", translate("Weekly"))
period:value("month", translate("Monthly"))
period:value("never", translate("Never (manual reset only)"))
period.default = "day"

-- Usage Status
local usage = q:option(DummyValue, "_usage", translate("Current Usage"))
function usage.cfgvalue(self, section)
    -- Get MAC and IP for this section
    local mac = m:get(section, "mac") or ""
    local ip = m:get(section, "ip") or ""
    
    if mac == "" or ip == "" then
        return "No device set"
    end
    
    -- Create device ID
    local device_id = mac:gsub(":", "") .. "_" .. ip:gsub("%.", "")
    
    -- Get usage from daemon
    local usage_data = sys.exec("/usr/bin/quotalimiter.sh get_usage " .. device_id .. " 2>/dev/null") or ""
    local limit_bytes, used_bytes, blocked = usage_data:match("([^|]+)|([^|]+)|([^|]+)")
    
    if used_bytes and limit_bytes then
        local used = tonumber(used_bytes) or 0
        local limit_val = tonumber(limit_bytes) or 0
        
        if limit_val > 0 then
            local used_mb = math.floor(used / 1048576)
            local limit_mb = math.floor(limit_val / 1048576)
            local percent = math.floor((used / limit_val) * 100)
            local status = (blocked == "1" and " (BLOCKED)" or " (ACTIVE)")
            return string.format("%d/%d MB (%d%%)%s", used_mb, limit_mb, percent, status)
        end
    end
    return "0/0 MB"
end

-- ===== INLINE LOG SECTION =====
local log_section = m:section(SimpleSection, nil, translate("Live Log"))
log_section.template = "quotalimiter/log_inline"

return m
