# SPDX-License-Identifier: GPL-3.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-netspeedtest
PKG_VERSION:=5.1.0
PKG_RELEASE:=20251108
PKG_MAINTAINER:=sirpdboy

LUCI_TITLE:=LuCI Support for NetSpeedTest
LUCI_PKGARCH:=all

# SAFE DEPENDS
LUCI_DEPENDS:=+speedtest-cli +homebox +netspeedtest +iperf3

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

