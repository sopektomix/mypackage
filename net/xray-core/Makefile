# SPDX-License-Identifier: GPL-3.0-or-later
include $(TOPDIR)/rules.mk

PKG_NAME:=xray-core
PKG_VERSION:=25.10.15-stdrx
PKG_RELEASE:=1

PKG_MAINTAINER:=Paka <you@example.com>
PKG_LICENSE:=MPL-2.0
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/xray-core
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Xray Core (STDSTRX Custom Build)
  URL:=https://github.com/XTLS/Xray-core
  DEPENDS:=+libpthread +libmbedtls
endef

define Package/xray-core/description
Custom Xray-core build (version 25.10.15-stdrx) by @STDSTRX.
This package installs a prebuilt Xray binary, init script, and config files.
endef

define Build/Prepare
	# No source to extract, binary already included
endef

define Build/Compile
	# Nothing to compile (prebuilt binary)
endef

define Package/xray-core/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/xray $(1)/usr/bin/xray

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/xray $(1)/etc/init.d/xray

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/xray $(1)/etc/config/xray
endef

$(eval $(call BuildPackage,xray-core))

