-- Copyright 2022-2023 sirpdboy
-- Licensed under the Apache License 2.0.

local sys = require "luci.sys"
local fs = require "nixio.fs"
local ifaces = sys.net:devices()
local WADM = require "luci.tools.webadmin"
local ipc = require "luci.ip"
local a, t, e

a = Map("speedlimiter", translate("SpeedLimiter"))
a.description = translate([[
<div style="margin-bottom:6px;">
  Limit internet speed per device (IP/MAC).
</div>

<div style="border:1px solid #d9534f;background:#f2dede;color:#a94442;
            padding:6px 8px;margin-bottom:6px;">
  <strong>Note:</strong>
  Please set wireless password and make sure your router timezone matches your country
  (go to System → System → Timezone).
</div>

<div style="margin-bottom:4px;">
  Contact:
  <a href="https://t.me/sopek23" target="_blank">Telegram @sopek23</a> ·
  <a href="https://www.sopeksemprit.xyz" target="_blank">www.sopeksemprit.xyz</a>
</div>
]])
a.template = "speedlimiter/index"

----------------------------------------------------------
-- MAIN CONFIG SECTION
----------------------------------------------------------

t = a:section(TypedSection, "speedlimiter")
t.anonymous = true

e = t:option(DummyValue, "speedlimiter_status", translate("Status"))
e.template = "speedlimiter/speedlimiter"
e.value = translate("Collecting data...")

e = t:option(Flag, "enabled", translate("Enable SpeedLimiter"))
e.rmempty = false
e.default = "0"

ipi = t:option(ListValue, "ifname", translate("Interface"),
    translate("Set the interface used for restriction, use pppoe-wan for dialing, use WAN hardware interface for DHCP mode (such as eth1), and use br-lan for bypass mode"))
ipi.default = "1"
ipi:value(1, translate("Automatic settings"))
ipi:value("br-lan", translate("br-lan (LAN Bridge)"))

----------------------------------------------------------
-- WAN DETECTION
----------------------------------------------------------

local function get_wan_interfaces()
    local result = {}
    local ubus = require "ubus"
    
    local conn = ubus.connect()
    if not conn then
        return result
    end

    local network_status = conn:call("network.interface", "dump", {})
    for _, iface in ipairs(network_status.interface) do
        if iface.interface:match("^wan") or iface.interface:match("^pppoe") or iface.proto == "pppoe" then
            local dev = iface.l3_device or iface.device
            if dev then
                table.insert(result, {
                    name = dev,
                    proto = iface.proto,
                    logical_name = iface.interface
                })
            end
        end
    end

    conn:close()
    return result
end

----------------------------------------------------------
-- LOG VIEW
----------------------------------------------------------

local log = t:option(TextValue, "_log", translate("SpeedLimiter log"))
log.rows = 12
log.readonly = "readonly"
function log.cfgvalue(self, section)
    return fs.readfile("/var/log/speedlimiter.log") or ""
end
function log.write(self, section, value)
    -- read-only
end

local wan_ifaces = get_wan_interfaces()
for _, iface in ipairs(wan_ifaces) do
    ipi:value(iface.name, translate(iface.name) .. (iface.proto == "pppoe" and " (PPPoE)" or " (WAN)"))
end

----------------------------------------------------------
-- DEVICE RULES SECTION
----------------------------------------------------------

t = a:section(TypedSection, "device")
t.template = "cbi/tblsection"
t.anonymous = true
t.addremove = true

comment = t:option(Value, "comment", translate("Comment"))
comment.size = 8

e = t:option(Flag, "enable", translate("Enabled"))
e.rmempty = false
e.size = 4

ip = t:option(Value, "mac", translate("IP/MAC"))
ip.size = 8

----------------------------------------------------------
-- DEVICE AUTO-DETECTION
----------------------------------------------------------

local function get_devices()
    local devices = {}
    local seen_ips = {}
    local ubus = require "ubus"
    local conn = ubus.connect()

    --- hostname resolver
    local function get_hostname(ip)
        local f = io.popen("nslookup "..ip.." 2>/dev/null | grep 'name =' | cut -d'=' -f2 | sed 's/\\.$//'")
        if f then
            local name = f:read("*l")
            f:close()
            if name and name ~= "" then
                return name:match("^%s*(.-)%s*$")
            end
        end
        
        local leases_file = io.open("/tmp/dhcp.leases", "r")
        if leases_file then
            for line in leases_file:lines() do
                local mac, ip_lease, _, hostname = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
                if ip_lease == ip and hostname ~= "*" then
                    leases_file:close()
                    return hostname
                end
            end
            leases_file:close()
        end

        return "unknown"
    end

    --- DHCP
    if conn then
        local leases = conn:call("dhcp", "ipv4leases", {}) or {}
        for _, lease in ipairs(leases) do
            if lease.ipaddr and lease.mac then
                local hostname = lease.hostname or get_hostname(lease.ipaddr)
                devices[#devices+1] = {
                    ip = lease.ipaddr,
                    mac = lease.mac:upper(),
                    hostname = hostname,
                    display = string.format("%s (%s) - %s",
                        lease.ipaddr, lease.mac:upper(), hostname)
                }
                seen_ips[lease.ipaddr] = true
            end
        end
        conn:close()
    end

    --- ARP fallback
    local arp_cmd = io.popen("ip -4 neigh show dev br-lan 2>/dev/null")
    if arp_cmd then
        for line in arp_cmd:lines() do
            local ip_addr, mac = line:match("^(%S+)%s+.+%s+(%S+)%s+")
            if ip_addr and mac and mac ~= "00:00:00:00:00:00" and not seen_ips[ip_addr] then
                mac = mac:upper()
                local hostname = get_hostname(ip_addr)
                devices[#devices+1] = {
                    ip = ip_addr,
                    mac = mac,
                    hostname = hostname,
                    display = string.format("%s (%s) - %s",
                        ip_addr, mac, hostname)
                }
                seen_ips[ip_addr] = true
            end
        end
        arp_cmd:close()
    end

    table.sort(devices, function(a, b) return a.ip < b.ip end)
    return devices
end

local devices = get_devices()
for _, dev in ipairs(devices) do
    ip:value(dev.ip, dev.display)
end

----------------------------------------------------------
-- DOWNLOAD / UPLOAD LIMITS
----------------------------------------------------------

dl = t:option(Value, "download", translate("Downloads"))
dl.default = '0.1'
dl.size = 4

ul = t:option(Value, "upload", translate("Uploads"))
ul.default = '0.1'
ul.size = 4

----------------------------------------------------------
-- TIME VALIDATION
----------------------------------------------------------

function validate_time(self, value, section)
    local hh, mm
    hh, mm = string.match(value, "^(%d?%d):(%d%d)$")
    hh = tonumber(hh)
    mm = tonumber(mm)
    if hh and mm and hh <= 23 and mm <= 59 then
        return value
    else
        return nil, "Time HH:MM or space"
    end
end

e = t:option(Value, "timestart", translate("Start control time"))
e.placeholder = '00:00'
e.default = '00:00'
e.validate = validate_time
e.rmempty = true
e.size = 4

e = t:option(Value, "timeend", translate("Stop control time"))
e.placeholder = '00:00'
e.default = '00:00'
e.validate = validate_time
e.rmempty = true
e.size = 4

----------------------------------------------------------
-- WEEK SELECTOR
----------------------------------------------------------

week = t:option(Value, "week", translate("Week Day(1~7)"))
week.rmempty = true
week:value('0', translate("Everyday"))
week:value(1, translate("Monday"))
week:value(2, translate("Tuesday"))
week:value(3, translate("Wednesday"))
week:value(4, translate("Thursday"))
week:value(5, translate("Friday"))
week:value(6, translate("Saturday"))
week:value(7, translate("Sunday"))
week:value('1,2,3,4,5', translate("Workday"))
week:value('6,7', translate("Rest Day"))
week.default = '0'
week.size = 6

----------------------------------------------------------
return a
----------------------------------------------------------

