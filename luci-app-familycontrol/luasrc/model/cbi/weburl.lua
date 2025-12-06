-- Web URL control page for FamilyControl (dnsmasq + nft backend)
-- 2024-2025 sopeksemprit <sopeksemprit.xyz>

local sys = require "luci.sys"
local ipc = require "luci.ip"

local a, t, e

a = Map("familycontrol", translate("Internet Family Control - URL web control"))

a.description = translate([[
<div style="margin-bottom:6px;">
  Limit Internet access for family devices using time-based rules and URL web control.
</div>
<div style="border:1px solid #d9534f;background:#f2dede;color:#a94442;padding:6px 8px;margin-bottom:6px;">
  <strong>Note:</strong> Please set wireless password and make sure your router timezone matches your country (go to System → System → Timezone).
</div>
<div>
  Contact:
  <a href="https://t.me/sopek23" target="_blank">Telegram @sopek23</a> ·
  <a href="https://www.sopeksemprit.xyz" target="_blank">https://www.sopeksemprit.xyz</a>
</div>
]])

a.template = "familycontrol/index"

-- ================= STATUS + LOG (MATCH FAMILY TIME CONTROL) =================

t = a:section(TypedSection, "familycontrol", translate("Service status"))
t.anonymous = true

-- Status display
e = t:option(DummyValue, "_status", translate("Current status"))
e.template = "familycontrol/familycontrol"
e.value    = translate("Collecting data...")

-- Log display (same position as FamilyControl)
local logopt = t:option(DummyValue, "_log", translate("Control log"))
logopt.template = "familycontrol/logview"
logopt.value    = ""

-- ================= Helper: Auto device list =================

local function get_devices()
	local devices  = {}
	local seen_ips = {}
	local ubus     = require "ubus"
	local conn     = ubus.connect()

	local function trim(s)
		return (s:gsub("^%s*(.-)%s*$", "%1"))
	end

	local function get_hostname(ipaddr)
		local f = io.popen("nslookup "..ipaddr.." 2>/dev/null | grep 'name =' | cut -d'=' -f2 | sed 's/\\.$//'")
		if f then
			local name = f:read("*l")
			f:close()
			if name and #trim(name) > 0 then
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

	if conn then
		local leases = conn:call("dhcp", "ipv4leases", {}) or {}
		for _, lease in ipairs(leases) do
			if lease.ipaddr and lease.mac then
				local ipaddr   = lease.ipaddr
				local mac      = (lease.mac or ""):upper()
				local hostname = lease.hostname or get_hostname(ipaddr)

				if not seen_ips[ipaddr] then
					devices[#devices + 1] = {
						ip       = ipaddr,
						mac      = mac,
						hostname = hostname,
						display  = string.format("%s (%s) - %s", ipaddr, mac, hostname)
					}
					seen_ips[ipaddr] = true
				end
			end
		end
		conn:close()
	end

	local arp_cmd = io.popen("ip -4 neigh show dev br-lan 2>/dev/null")
	if arp_cmd then
		for line in arp_cmd:lines() do
			local ip_addr, mac = line:match("^(%S+)%s+.+%s+(%S+)%s+")
			if ip_addr and mac and mac ~= "00:00:00:00:00:00" and not seen_ips[ip_addr] then
				mac = mac:upper()
				local hostname = get_hostname(ip_addr)
				devices[#devices + 1] = {
					ip       = ip_addr,
					mac      = mac,
					hostname = hostname,
					display  = string.format("%s (%s) - %s", ip_addr, mac, hostname)
				}
				seen_ips[ip_addr] = true
			end
		end
		arp_cmd:close()
	end

	table.sort(devices, function(a, b) return a.ip < b.ip end)
	return devices
end

-- ======================== URL WEB CONTROL TABLE ========================

local u = a:section(TypedSection, "urlcontrol", translate("URL Web Control"))
u.template  = "cbi/tblsection"
u.anonymous = true
u.addremove = true

local u_comment = u:option(Value, "comment", translate("Comment"))
u_comment.size = 16

local u_enable = u:option(Flag, "enable", translate("Enabled"))
u_enable.rmempty = false

local u_device = u:option(Value, "device", translate("IP/MAC (reference device)"))
u_device.size = 24

local devices = get_devices()
for _, dev in ipairs(devices) do
	u_device:value(dev.ip, dev.display)
end

local u_timestart = u:option(Value, "timestart", translate("Start control time"))
u_timestart.placeholder = "00:00"
u_timestart.default     = "00:00"
u_timestart.rmempty     = true
u_timestart.size        = 6

local u_timeend = u:option(Value, "timeend", translate("Stop control time"))
u_timeend.placeholder = "00:00"
u_timeend.default     = "00:00"
u_timeend.rmempty     = true
u_timeend.size        = 6

-- ✔ FIXED: Weekday dropdown identical to Family Time Control
local u_week = u:option(Value, "week", translate("Week Day (1~7)"))
u_week.rmempty = true
u_week:value("0", translate("Everyday"))
u_week:value("1,2,3,4,5", translate("Workday"))
u_week:value("6,7", translate("Rest Day"))
u_week:value("1", translate("Monday"))
u_week:value("2", translate("Tuesday"))
u_week:value("3", translate("Wednesday"))
u_week:value("4", translate("Thursday"))
u_week:value("5", translate("Friday"))
u_week:value("6", translate("Saturday"))
u_week:value("7", translate("Sunday"))
u_week.default = "0"
u_week.size = 8

local u_top = u:option(ListValue, "topdomain", translate("Quick block popular site"))
u_top:value("", translate("-- none --"))
u_top:value("facebook.com", "Facebook")
u_top:value("youtube.com", "YouTube")
u_top:value("tiktok.com", "TikTok")
u_top:value("instagram.com", "Instagram")
u_top:value("twitter.com", "Twitter / X")
u_top:value("netflix.com", "Netflix")
u_top:value("whatsapp.com", "WhatsApp")
u_top:value("mobilelegends.com", "Mobile Legends")
u_top:value("minecraft.net", "Minecraft")
u_top:value("roblox.com", "Roblox")
u_top:value("pubgmobile.com", "PUBG Mobile")

local u_domains = u:option(Value, "domains", translate("Blocked domains / apps"))
u_domains.rmempty     = true
u_domains.size        = 32
u_domains.description = translate("Enter domain names separated by commas, e.g. facebook.com,youtube.com")

-- Auto rebuild on commit
function a.on_after_commit(self)
	sys.call("/usr/bin/familycontrol url >/dev/null 2>&1 &")
end

return a

