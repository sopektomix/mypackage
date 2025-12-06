m = Map("pintas", translate("Pintas AT Command Manager"), 
    translate("Manage your modem through AT commands with real-time feedback"))

s = m:section(TypedSection, "config", translate("Configuration"))
s.addremove = false
s.anonymous = true

device = s:option(Value, "device", translate("Modem Device"))
device.default = "/dev/ttyUSB2"
device.rmempty = false

-- IMEI Section
imei_section = m:section(TypedSection, "imei", translate("IMEI Management"))
imei_section.anonymous = true

check_imei = imei_section:option(Button, "_check_imei", translate("Check IMEI"))
check_imei.inputstyle = "apply"
check_imei.write = function(self, section, value)
    local result = luci.util.exec('echo "AT+EGMR=0,7" | atinout - /dev/ttyUSB2 - 2>&1')
    self.description = string.format('<div class="alert-message success"><strong>Result:</strong><br><pre>%s</pre></div>', 
        luci.util.pcdata(result))
end

new_imei = imei_section:option(Value, "new_imei", translate("New IMEI"))
new_imei.datatype = "string"

set_imei = imei_section:option(Button, "_set_imei", translate("Set IMEI"))
set_imei.inputstyle = "apply"
set_imei.write = function(self, section, value)
    local imei = m:formvalue("cbid.pintas.imei.new_imei")
    if imei and imei:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d$") then
        local cmd = string.format('AT+EGMR=1,7,"%s"', imei)
        local result = luci.util.exec(string.format('echo "%s" | atinout - /dev/ttyUSB2 - 2>&1', cmd))
        self.description = string.format('<div class="alert-message success"><strong>Result:</strong><br><pre>%s</pre></div>', 
            luci.util.pcdata(result))
    else
        self.description = '<div class="alert-message error">Invalid IMEI format (must be 15 digits)</div>'
    end
end

-- Network Lock Section
net_section = m:section(TypedSection, "network", translate("Network Mode Lock"))
net_section.anonymous = true

net_modes = {
    ["5G+LTE"] = 'AT+QNWPREFCFG="mode_pref",NR5G+LTE',
    ["5G Only"] = 'AT+QNWPREFCFG="mode_pref",NR5G',
    ["LTE Only"] = 'AT+QNWPREFCFG="mode_pref",LTE',
    ["Auto"] = 'AT+QNWPREFCFG="mode_pref",AUTO'
}

for name, cmd in pairs(net_modes) do
    local btn = net_section:option(Button, "_lock_" .. name:gsub("%s+", "_"), translate("Lock: ") .. name)
    btn.inputstyle = "apply"
    btn.write = function(self, section, value)
        local result = luci.util.exec(string.format('echo "%s" | atinout - /dev/ttyUSB2 - 2>&1', cmd))
        self.description = string.format('<div class="alert-message success"><strong>Result:</strong><br><pre>%s</pre></div>', 
            luci.util.pcdata(result))
    end
end

-- USB Mode Section
usb_section = m:section(TypedSection, "usb", translate("USB Mode"))
usb_section.anonymous = true

qmi_btn = usb_section:option(Button, "_qmi", translate("Set QMI Mode"))
qmi_btn.inputstyle = "apply"
qmi_btn.write = function(self, section, value)
    local result = luci.util.exec('echo "AT+QCFG=\"usbnet\",0" | atinout - /dev/ttyUSB2 - 2>&1')
    self.description = string.format('<div class="alert-message success"><strong>Result:</strong><br><pre>%s</pre></div>', 
        luci.util.pcdata(result))
end

mbim_btn = usb_section:option(Button, "_mbim", translate("Set MBIM Mode"))
mbim_btn.inputstyle = "apply"
mbim_btn.write = function(self, section, value)
    local result = luci.util.exec('echo "AT+QCFG=\"usbnet\",2" | atinout - /dev/ttyUSB2 - 2>&1')
    self.description = string.format('<div class="alert-message success"><strong>Result:</strong><br><pre>%s</pre></div>', 
        luci.util.pcdata(result))
end

-- Reset Section
reset_section = m:section(TypedSection, "reset", translate("Module Reset"))
reset_section.anonymous = true

reset_btn = reset_section:option(Button, "_reset", translate("Reset Module"))
reset_btn.inputstyle = "save"
reset_btn.write = function(self, section, value)
    local result = luci.util.exec('echo "AT+CFUN=1,1" | atinout - /dev/ttyUSB2 - 2>&1')
    self.description = string.format('<div class="alert-message warning"><strong>Module reset initiated:</strong><br><pre>%s</pre></div>', 
        luci.util.pcdata(result))
end

-- Custom Command Section
custom_section = m:section(TypedSection, "custom", translate("Custom AT Command"))
custom_section.anonymous = true

custom_cmd = custom_section:option(Value, "command", translate("AT Command"))
custom_cmd.placeholder = "AT+COMMAND"

custom_exec = custom_section:option(Button, "_execute", translate("Execute"))
custom_exec.inputstyle = "apply"
custom_exec.write = function(self, section, value)
    local cmd = m:formvalue("cbid.pintas.custom.command")
    if cmd and cmd ~= "" then
        local result = luci.util.exec(string.format('echo "%s" | atinout - /dev/ttyUSB2 - 2>&1', cmd))
        self.description = string.format('<div class="alert-message"><strong>Result:</strong><br><pre>%s</pre></div>', 
            luci.util.pcdata(result))
    end
end

return m
