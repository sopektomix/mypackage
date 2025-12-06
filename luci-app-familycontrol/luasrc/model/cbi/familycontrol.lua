-- Copyright 2024-2025 sopeksemprit <sopeksemprit.xyz>
-- Licensed under the Apache License 2.0.

local sys  = require "luci.sys"
local ipc  = require "luci.ip"
local a, t, e

a = Map("familycontrol", translate("Internet Family Control"))

-- ================== NEW DESCRIPTION (NOTE + CONTACT) ==================
a.description = translate([[
<div style="margin-bottom:6px;">
  Limit Internet access for family devices using time-based rules and URL web control.
</div>

<div style="border:1px solid #d9534f;background:#f2dede;color:#a94442;
            padding:6px 8px;margin-bottom:6px;">
  <strong>Note:</strong>
  Please set wireless password and make sure your router timezone matches your country
  (go to System → System → Timezone).
</div>

<div>
  Contact:
  <a href="https://t.me/sopek23" target="_blank">Telegram @sopek23</a> ·
  <a href="https://www.sopeksemprit.xyz" target="_blank">www.sopeksemprit.xyz</a>
</div>
]])

a.template    = "familycontrol/index"

-- ========= Global settings =========

t = a:section(TypedSection, "familycontrol", translate("Global Settings"))
t.anonymous = true

-- Main switch
e = t:option(Flag, "enabled", translate("Enable family control"))
e.rmempty = false
e.default = "0"

-- Status box
local st = t:option(DummyValue, "familycontrol_status", translate("Service Status"))
st.template = "familycontrol/status"
st.value    = translate("Collecting data...")

-- Control mode
e = t:option(ListValue, "list_type",
	translate("Control mode"),
	translate("blacklist: Block the target address from accessing the network. whitelist: Only allow traffic for the target address and block all other addresses.")
)
e.rmempty = false
e:value("blacklist", translate("blacklist"))
-- e:value("whitelist", translate("whitelist"))
e.default = "blacklist"

-- Control intensity (chain)
e = t:option(ListValue, "chain",
	translate("Control intensity"),
	translate("Select which firewall chain to apply blocking rules to.")
)
e.rmempty = false
e:value("forward", translate("Block Internet access (forward chain)"))
e:value("input",   translate("Block access to router only (input chain)"))
e.default = "forward"

-- Log viewer
local logopt = t:option(DummyValue, "_log", translate("Control log"))
logopt.template = "familycontrol/logview"
logopt.value    = ""

-- ========= Device time control =========

t = a:section(TypedSection, "device", translate("Device time control"))
t.template = "cbi/tblsection"
t.anonymous = true
t.addremove = true

local comment = t:option(Value, "comment", translate("Comment"))
comment.size = 16

e = t:option(Flag, "enable", translate("Enabled"))
e.rmempty = false
e.size = 4

local ip = t:option(Value, "mac", translate("IP/MAC"))
ip.size = 16

-- Auto device list (IP+MAC) with no duplicate IPs
local function get_devices()
	local devices  = {}
	local seen_ips = {}
	local ubus     = require "ubus"
	local conn     = ubus.connect()

	local function trim(s)
		return (s:gsub("^%s*(.-)%s*$", "%1"))
	end

	local function safe_display(ipaddr, mac, hostname)
		ipaddr   = tostring(ipaddr or "?")
		mac      = tostring(mac or "?")
		hostname = tostring(hostname or "unknown")
		return string.format("%s (%s) - %s", ipaddr, mac, hostname)
	end

	local function get_hostname(ipaddr)
		local f = io.popen("nslookup "..ipaddr.." 2>/dev/null | grep 'name =' | cut -d'=' -f2 | sed 's/\\.$//'")
		if f then
			local name = f:read("*l")
			f:close()
			if name and name ~= "" then
				return trim(name)
			end
		end

		local leases_file = io.open("/tmp/dhcp.leases", "r")
		if leases_file then
			for line in leases_file:lines() do
				local ts, mac, ip_lease, hostname = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
				if ip_lease == ipaddr and hostname and hostname ~= "*" then
					leases_file:close()
					return hostname
				end
			end
			leases_file:close()
		end

		return "unknown"
	end

	-- DHCP leases dari ubus
	if conn then
		local leases = conn:call("dhcp", "ipv4leases", {}) or {}
		for _, lease in ipairs(leases) do
			if lease.ipaddr and lease.mac then
				local ipaddr   = lease.ipaddr
				local mac      = (lease.mac or ""):upper()
				local hostname = lease.hostname or get_hostname(ipaddr)

				if not seen_ips[ipaddr] then
					local display = safe_display(ipaddr, mac, hostname)

					devices[#devices + 1] = {
						ip       = ipaddr,
						mac      = mac,
						hostname = hostname,
						display  = display
					}
					seen_ips[ipaddr] = true
				end
			end
		end
		conn:close()
	end

	-- ARP fallback
	local arp_cmd = io.popen("ip -4 neigh show dev br-lan 2>/dev/null")
	if arp_cmd then
		for line in arp_cmd:lines() do
			local ip_addr, mac = line:match("^(%S+)%s+.+%s+(%S+)%s+")
			if ip_addr and mac and mac ~= "00:00:00:00:00:00" and not seen_ips[ip_addr] then
				mac = mac:upper()
				local hostname = get_hostname(ip_addr)
				local display  = safe_display(ip_addr, mac, hostname)

				devices[#devices + 1] = {
					ip       = ip_addr,
					mac      = mac,
					hostname = hostname,
					display  = display
				}
				seen_ips[ip_addr] = true
			end
		end
		arp_cmd:close()
	end

	table.sort(devices, function(a, b) return (a.ip or "") < (b.ip or "") end)

	return devices
end

local devices = get_devices()
for _, dev in ipairs(devices) do
	ip:value(dev.ip or "", dev.display or (dev.ip or "unknown"))
end

-- Time validation
local function validate_time(self, value, section)
	local hh, mm = value:match("^(%d?%d):(%d%d)$")
	hh = tonumber(hh)
	mm = tonumber(mm)
	if hh and mm and hh <= 23 and mm <= 59 then
		return value
	else
		return nil, translate("Time must be in HH:MM format")
	end
end

e = t:option(Value, "timestart", translate("Start control time"))
e.placeholder = "00:00"
e.default     = "00:00"
e.validate    = validate_time
e.rmempty     = true
e.size        = 6

e = t:option(Value, "timeend", translate("Stop control time"))
e.placeholder = "00:00"
e.default     = "00:00"
e.validate    = validate_time
e.rmempty     = true
e.size        = 6

local week = t:option(Value, "week", translate("Week Day (1~7)"))
week.rmempty = true
week:value("0", translate("Everyday"))
week:value(1, translate("Monday"))
week:value(2, translate("Tuesday"))
week:value(3, translate("Wednesday"))
week:value(4, translate("Thursday"))
week:value(5, translate("Friday"))
week:value(6, translate("Saturday"))
week:value(7, translate("Sunday"))
week:value("1,2,3,4,5", translate("Workday"))
week:value("6,7", translate("Rest Day"))
week.default = "0"
week.size    = 8

return a

