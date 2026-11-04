#!/bin/sh
#
# Shared defaults/helpers for HiWiFi HC5962 (极路由4 / B70).
#
# Sourced by /etc/uci-defaults/90-hc5962 and /usr/sbin/hc5962-wifi.
# Only POSIX shell + uci are required; this also runs from the initramfs-free
# first-boot environment before netifd starts.
#

HC5962_AP_SSID="${HC5962_AP_SSID:-HC5962}"
HC5962_AP_KEY="${HC5962_AP_KEY:-12345678}"

# Print the wifi-device section whose "band" option matches $1 (2g/5g).
hc5962_radio_by_band() {
	local band="$1" radio
	for radio in $(uci -q show wireless 2>/dev/null | \
			sed -n "s/^wireless\.\([^.=]*\)=['\"]\{0,1\}wifi-device['\"]\{0,1\}$/\1/p"); do
		if [ "$(uci -q get "wireless.$radio.band")" = "$band" ]; then
			printf '%s\n' "$radio"
			return 0
		fi
	done
	return 1
}

hc5962_ensure_iface() {
	[ "$(uci -q get "wireless.$1")" = "wifi-iface" ] ||
		uci -q set "wireless.$1=wifi-iface"
}

hc5962_add_ap() {
	local sec="$1" radio="$2" ssid="$3" key="$4" disabled="$5"

	uci -q set "wireless.$sec=wifi-iface"
	uci -q set "wireless.$sec.device=$radio"
	uci -q set "wireless.$sec.mode=ap"
	uci -q set "wireless.$sec.ssid=$ssid"
	uci -q set "wireless.$sec.encryption=psk2+ccmp"
	uci -q set "wireless.$sec.key=$key"
	uci -q set "wireless.$sec.network=lan"
	uci -q set "wireless.$sec.isolate=0"
	uci -q set "wireless.$sec.disabled=$disabled"
}

hc5962_add_sta() {
	local sec="$1" radio="$2"

	uci -q set "wireless.$sec=wifi-iface"
	uci -q set "wireless.$sec.device=$radio"
	uci -q set "wireless.$sec.mode=sta"
	uci -q set "wireless.$sec.ssid=Upstream"
	uci -q set "wireless.$sec.encryption=none"
	uci -q set "wireless.$sec.network=wwan"
	uci -q set "wireless.$sec.disabled=1"
}

# First-boot wireless defaults:
#   2.4G -> AP "HC5962", 5G -> disabled STA (uplink placeholder)
# Both bands also get the opposite (disabled) role so "hc5962-wifi uplink"
# can switch bands without recreating sections.
hc5962_wifi_defaults() {
	local r2 r5

	[ -f /etc/config/wireless ] || /sbin/wifi config >/dev/null 2>&1

	r2=$(hc5962_radio_by_band 2g) || return 1
	r5=$(hc5962_radio_by_band 5g) || return 1

	uci -q set "wireless.$r2.country=CN"
	uci -q set "wireless.$r2.channel=auto"
	uci -q set "wireless.$r2.htmode=HT20"
	uci -q set "wireless.$r2.disabled=0"
	uci -q set "wireless.$r5.country=CN"
	uci -q set "wireless.$r5.channel=auto"
	uci -q set "wireless.$r5.htmode=VHT80"
	uci -q set "wireless.$r5.disabled=0"

	# This is only called on first boot or by "hc5962-wifi reset".
	while uci -q delete wireless.@wifi-iface[0]; do :; done

	hc5962_add_ap ap_2g "$r2" "$HC5962_AP_SSID" "$HC5962_AP_KEY" 0
	hc5962_add_ap ap_5g "$r5" "${HC5962_AP_SSID}-5G" "$HC5962_AP_KEY" 1
	hc5962_add_sta sta_2g "$r2"
	hc5962_add_sta sta_5g "$r5"

	uci -q commit wireless
	return 0
}

# Wired 802.1X and Wi-Fi STA are two independent uplinks.  The wired one has
# the lower metric and therefore wins while it has a lease.
hc5962_ensure_wwan() {
	uci -q set network.wwan=interface
	[ -n "$(uci -q get network.wwan.proto)" ] ||
		uci -q set network.wwan.proto=dhcp
	[ -n "$(uci -q get network.wwan.metric)" ] ||
		uci -q set network.wwan.metric=20
	uci -q delete network.wwan.device
	uci -q commit network
}

# Join an existing network on $3 (5g by default) and serve clients on the
# other radio.
hc5962_wifi_uplink() {
	local ssid="$1" key="$2" band="${3:-5g}" other r_sta r_ap

	case "$band" in
		2g|5g) ;;
		*) return 1 ;;
	esac
	[ "$band" = "2g" ] && other="5g" || other="2g"

	r_sta=$(hc5962_radio_by_band "$band") || return 1
	r_ap=$(hc5962_radio_by_band "$other") || return 1

	uci -q set "wireless.$r_sta.disabled=0"
	uci -q set "wireless.$r_ap.disabled=0"

	hc5962_ensure_iface "sta_$band"
	hc5962_ensure_iface "ap_$other"
	hc5962_ensure_iface "ap_$band"
	hc5962_ensure_iface "sta_$other"

	uci -q set "wireless.sta_$band.device=$r_sta"
	uci -q set "wireless.sta_$band.mode=sta"
	uci -q set "wireless.sta_$band.ssid=$ssid"
	uci -q set "wireless.sta_$band.network=wwan"
	uci -q set "wireless.sta_$band.disabled=0"
	if [ -n "$key" ]; then
		uci -q set "wireless.sta_$band.encryption=psk2"
		uci -q set "wireless.sta_$band.key=$key"
	else
		uci -q set "wireless.sta_$band.encryption=none"
		uci -q delete "wireless.sta_$band.key"
	fi

	uci -q set "wireless.ap_$other.device=$r_ap"
	uci -q set "wireless.ap_$other.mode=ap"
	uci -q set "wireless.ap_$other.network=lan"
	uci -q set "wireless.ap_$other.disabled=0"
	if [ -z "$(uci -q get "wireless.ap_$other.ssid")" ]; then
		case "$other" in
			2g) uci -q set "wireless.ap_$other.ssid=$HC5962_AP_SSID" ;;
			5g) uci -q set "wireless.ap_$other.ssid=${HC5962_AP_SSID}-5G" ;;
		esac
	fi
	if [ -z "$(uci -q get "wireless.ap_$other.key")" ]; then
		uci -q set "wireless.ap_$other.encryption=psk2+ccmp"
		uci -q set "wireless.ap_$other.key=$HC5962_AP_KEY"
	fi

	uci -q set "wireless.ap_$band.disabled=1"
	uci -q set "wireless.sta_$other.disabled=1"

	hc5962_ensure_wwan
	uci -q commit wireless
	return 0
}

hc5962_network_defaults() {
	local i=0 zone=

	if [ "$(uci -q get network.lan)" != "interface" ]; then
		uci -q set network.lan=interface
		uci -q set network.lan.device=br-lan
		uci -q set network.lan.proto=static
	fi
	uci -q delete network.lan.ipaddr
	uci -q add_list network.lan.ipaddr=192.168.123.1/24
	uci -q set network.lan.ip6assign=60

	if [ "$(uci -q get network.wan)" != "interface" ]; then
		uci -q set network.wan=interface
		uci -q set network.wan.device=wan
		uci -q set network.wan.proto=dhcp
	fi
	uci -q set network.wan.metric=10

	hc5962_ensure_wwan
	uci -q set network.wwan6=interface
	uci -q set network.wwan6.proto=dhcpv6
	uci -q set network.wwan6.device='@wwan'
	uci -q set network.wwan6.metric=20

	if [ "$(uci -q get dhcp.lan)" = "dhcp" ]; then
		uci -q set dhcp.lan.start=100
		uci -q set dhcp.lan.limit=150
		uci -q set dhcp.lan.leasetime=12h
	fi

	# Put the Wi-Fi STA uplink into the same firewall zone as the wired WAN.
	while uci -q get "firewall.@zone[$i]" >/dev/null 2>&1; do
		if [ "$(uci -q get "firewall.@zone[$i].name")" = "wan" ]; then
			zone="@zone[$i]"
			break
		fi
		i=$((i + 1))
	done
	if [ -n "$zone" ]; then
		uci -q del_list "firewall.$zone.network=wwan"
		uci -q add_list "firewall.$zone.network=wwan"
		uci -q del_list "firewall.$zone.network=wwan6"
		uci -q add_list "firewall.$zone.network=wwan6"
	fi

	uci -q commit network
	uci -q commit dhcp
	uci -q commit firewall
}

hc5962_system_defaults() {
	if uci -q get system.@system[0] >/dev/null 2>&1; then
		uci -q set system.@system[0].hostname=HC5962
		uci -q set system.@system[0].timezone=CST-8
		uci -q set system.@system[0].zonename=Asia/Shanghai
	fi

	uci -q delete system.ntp.server
	uci -q add_list system.ntp.server=ntp.aliyun.com
	uci -q add_list system.ntp.server=cn.pool.ntp.org
	uci -q set system.ntp.enabled=1
	uci -q commit system

	# Default the LuCI language to Chinese when the language pack is present.
	if [ "$(uci -q get luci.main)" = "core" ]; then
		uci -q set luci.main.lang=zh-cn
		uci -q commit luci
	fi
}
