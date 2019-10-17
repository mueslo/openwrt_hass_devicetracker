#
# Copyright (c) 2018 Johannes Falke
# This is free software, licensed under the GNU General Public License v3.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=hass-tracker
PKG_VERSION:=0.1.3
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0+
PKG_MAINTAINER:=Johannes Falke <johannesfalke@gmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/hass-tracker
	SECTION:=net
	CATEGORY:=Network
	TITLE:=Wireless device tracker for Home Assistant
	DEPENDS:=+hostapd-utils +curl
	PKGARCH:=all
endef

define Package/hass-tracker/description
Wireless device tracker for Home Assistant (home-assistant.io). Monitors wifi APs for devices via hooking into hostapd events. The info is then sent to the Home Assistant API via a simple POST.

endef

define Package/hass-tracker/conffiles
/etc/config/hass-tracker
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/hass-tracker/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/hass-trackerd.sh $(1)/usr/bin/

	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_DIR) $(1)/usr/lib/hass-tracker
	$(INSTALL_BIN) ./files/functions.sh $(1)/usr/lib/hass-tracker/
	$(INSTALL_BIN) ./files/push_event.sh $(1)/usr/lib/hass-tracker/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/hass-tracker.init $(1)/etc/init.d/hass-tracker

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/hass-tracker.conf $(1)/etc/config/hass-tracker

endef

$(eval $(call BuildPackage,hass-tracker))
