#
# Copyright (C) 2006-2017 OpenWrt.org
# Copyright (C) 2024-2025 sopeksemprit <www.sopeksemprit.xyz>
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for QuotaLimiter
LUCI_DESCRIPTION:=Per-device internet data quota limiter with MAC/IP selection and logging
LUCI_DEPENDS:=+luci-compat +luci-lib-ipkg +bash +conntrack +arp-scan
LUCI_PKGARCH:=all
PKG_NAME:=luci-app-quotalimiter
PKG_VERSION:=2.0.0
PKG_RELEASE:=20251201
PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=sopeksemprit <www.sopeksemprit.xyz>

define Package/$(PKG_NAME)/conffiles
/etc/config/quotalimiter
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/quotalimiter enable >/dev/null 2>&1
	/etc/init.d/quotalimiter restart >/dev/null 2>&1
}
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/quotalimiter stop >/dev/null 2>&1
	/etc/init.d/quotalimiter disable >/dev/null 2>&1
}
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
