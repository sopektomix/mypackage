local fs = require "nixio.fs"
local uci = require "luci.model.uci".cursor()

local m = Map("nftttl", translate("TTL Settings"))

local support = m:section(SimpleSection)
support.template = "admin_support_info"

local s = m:section(NamedSection, "ttl", "ttl", translate("Settings"))
s.addremove = false
s:option(Flag, "enabled", translate("Enable"))

local val = s:option(Value, "value", translate("TTL / HopLimit Value"))
val.datatype = "uinteger"
val.default = 64
val.description = translate("Set the TTL (IPv4) / HopLimit (IPv6) value. Default is 64. " ..
    "Enabling this setting will modify all packet TTL values. " ..
    "After setting, click 'Save & Apply' â€” system will auto-apply rules and restart network.")

-- Log & Ping section
local logsec = m:section(SimpleSection)
logsec.template = "nftttl_logbox"

-- add custom actions for ping
local http = require "luci.http"
local sys = require "luci.sys"

function m.handle(action, ...)
    local args = {...}
    if action == "pingtest" then
        local res = sys.exec("ping -c 4 -W 1 google.com 2>&1")
        http.prepare_content("text/plain")
        http.write(res)
        return
    elseif action == "log" then
        local log_file = "/tmp/ttl_action.log"
        local data = fs.readfile(log_file) or "No log available."
        http.prepare_content("text/plain")
        http.write(data)
        return
    end
end

function m.on_commit(map)
    local enabled = uci:get("nftttl", "ttl", "enabled")
    local value = uci:get("nftttl", "ttl", "value") or "64"
    local nft_dir = "/etc/nftables.d/"
    local outfile = nft_dir .. "ttl64.nft"
    local log_file = "/tmp/ttl_action.log"

    local function log(msg)
        local f = io.open(log_file, "a")
        if f then
            f:write(os.date("[%H:%M:%S] ") .. msg .. "\n")
            f:close()
        end
    end

    for f in fs.dir(nft_dir) do
        if f:match("%.nft$") and f ~= "ttl64.nft" and f ~= "README" then
            fs.remove(nft_dir .. f)
        end
    end

    local function write_rule()
        local f = io.open(outfile, "w")
        if not f then return end
        local comment = function(line)
            return (enabled == "1") and line or ("# " .. line)
        end

        f:write(comment("chain mangle_prerouting_ttl64 {\n"))
        f:write(comment("  type filter hook prerouting priority 300; policy accept;\n"))
        f:write(comment("  counter\n"))
        f:write(comment("  ip ttl set " .. value .. "\n"))
        f:write(comment("}\n\n"))

        f:write(comment("chain mangle_postrouting_ttl64 {\n"))
        f:write(comment("  type filter hook postrouting priority 300; policy accept;\n"))
        f:write(comment("  counter\n"))
        f:write(comment("  ip ttl set " .. value .. "\n"))
        f:write(comment("}\n\n"))

        f:write(comment("chain mangle_prerouting_hoplimit64 {\n"))
        f:write(comment("  type filter hook prerouting priority 300; policy accept;\n"))
        f:write(comment("  counter\n"))
        f:write(comment("  ip6 hoplimit set " .. value .. "\n"))
        f:write(comment("}\n\n"))

        f:write(comment("chain mangle_postrouting_hoplimit64 {\n"))
        f:write(comment("  type filter hook postrouting priority 300; policy accept;\n"))
        f:write(comment("  counter\n"))
        f:write(comment("  ip6 hoplimit set " .. value .. "\n"))
        f:write(comment("}\n"))

        f:close()
    end

    write_rule()

    if enabled == "1" then
        log("TTL enabled (value " .. value .. "), applying rules...")
        os.execute("/etc/init.d/nft-custom-ttl enable >/dev/null 2>&1")
        os.execute("/etc/init.d/nft-custom-ttl start >/dev/null 2>&1 &")
    else
        log("TTL disabled, stopping rules...")
        os.execute("/etc/init.d/nft-custom-ttl stop >/dev/null 2>&1")
        os.execute("/etc/init.d/nft-custom-ttl disable >/dev/null 2>&1")
    end

    os.execute("sleep 1; /etc/init.d/firewall restart >/dev/null 2>&1 &")
    log("Firewall restarted.")
    os.execute("sleep 3; /etc/init.d/network restart >/dev/null 2>&1 &")
    log("Network interface restarted.")
end

return m


