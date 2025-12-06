#
# Copyright (C) 2006-2017 OpenWrt.org
# Copyright 2024-2025 sopeksemprit <sopeksemprit.xyz>
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

THEME_NAME:=FamilyControl
PKG_NAME:=luci-app-$(THEME_NAME)

PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=LuCI support for FamilyControl (time & URL control)
LUCI_DESCRIPTION:=LuCI support for easy Internet family control using nftables (time-based device control and URL web control).
LUCI_DEPENDS:=+bc +nftables +bash
LUCI_PKGARCH:=all

PKG_VERSION:=3.2.0
PKG_RELEASE:=20251129
PKG_MAINTAINER:=sopeksemprit <sopeksemprit.xyz>

define Build/Compile
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
rm -f /tmp/luci-*
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/familycontrol
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

