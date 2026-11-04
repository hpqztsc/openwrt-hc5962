#!/bin/sh
#
# Build HC5962 firmware from one of the supported OpenWrt trees.
#
#   ./scripts/build.sh                 # list sources
#   ./scripts/build.sh 2512            # openwrt-25.12
#   ./scripts/build.sh main            # openwrt/openwrt main
#   ./scripts/build.sh 2410            # openwrt-24.10
#   ./scripts/build.sh immortalwrt     # immortalwrt/immortalwrt master
#   ./scripts/build.sh lede            # coolsnowwolf/lede master
#
# Options:
#   SRC=/path/to/openwrt   use an existing tree
#   DL_DIR=/path/to/dl     shared download cache (default: <repo>/dl)
#   JOBS=16                parallel make jobs
#
# OpenWrt cannot be built on macOS; run this on Linux.
#
set -eu

# OpenWrt host tools (tar, etc.) refuse to configure as root unless this is set.
export FORCE_UNSAFE_CONFIGURE=1

# LEDE image recipes write progress to fd 8; keep it open for sub-makes.
exec 8>&1 9>&2

# GNU tar < 1.35 produces different git-archive tarballs than the OpenWrt
# build farm, which makes PKG_HASH checks fail for git-sourced packages.
if ! tar --version 2>/dev/null | head -n1 | grep -qE ' 1\.(3[5-9]|[4-9][0-9])'; then
	echo "WARNING: GNU tar >= 1.35 is recommended (found: $(tar --version 2>/dev/null | head -n1))" >&2
	echo "         Ubuntu 22.04 ships 1.34; build/install tar 1.35 first." >&2
fi

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE=${1:-}

usage() {
	cat <<EOF
Usage: $0 <main|2512|2410|immortalwrt|lede>

  main         openwrt/openwrt main            (kernel 6.18, apk)
  2512         openwrt/openwrt openwrt-25.12   (kernel 6.12, apk)
  2410         openwrt/openwrt openwrt-24.10   (kernel 6.6, opkg)
  immortalwrt  immortalwrt/immortalwrt master  (kernel 6.18, apk)
  lede         coolsnowwolf/lede master        (kernel 6.18, opkg)
EOF
}

case "$SOURCE" in
main)
	REPO_URL=https://github.com/openwrt/openwrt
	REPO_BRANCH=main
	;;
2512)
	REPO_URL=https://github.com/openwrt/openwrt
	REPO_BRANCH=openwrt-25.12
	;;
2410)
	REPO_URL=https://github.com/openwrt/openwrt
	REPO_BRANCH=openwrt-24.10
	;;
immortalwrt)
	REPO_URL=https://github.com/immortalwrt/immortalwrt
	REPO_BRANCH=master
	;;
lede)
	REPO_URL=https://github.com/coolsnowwolf/lede
	REPO_BRANCH=master
	;;
*)
	usage
	exit 1
	;;
esac

SRC=${SRC:-"$ROOT/build/$SOURCE/openwrt"}
DL_DIR=${DL_DIR:-"$ROOT/dl"}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}

if [ ! -d "$SRC/.git" ]; then
	echo "==> cloning $REPO_URL ($REPO_BRANCH) into $SRC"
	mkdir -p "$(dirname "$SRC")"
	# Full clone: OpenWrt's base-files version uses "git describe".  A
	# shallow clone yields "~unknown", which apk rejects as an invalid
	# package version.
	git clone -b "$REPO_BRANCH" "$REPO_URL" "$SRC"
fi

mkdir -p "$DL_DIR"
[ -e "$SRC/dl" ] || ln -s "$DL_DIR" "$SRC/dl"

echo "==> updating feeds"
cd "$SRC"
./scripts/feeds update -a
./scripts/feeds install -a

echo "==> applying HC5962 overlay ($SOURCE)"
sh "$ROOT/hc5962-port/apply.sh" "$SOURCE" "$SRC"

echo "==> writing .config"
cat "$ROOT/hc5962-port/config/common.config" \
    "$ROOT/hc5962-port/config/$SOURCE.config" > .config

make defconfig

# Fail early if the device or a critical package disappeared.
for sym in \
	CONFIG_PACKAGE_wpad-openssl=y
do
	grep -qx "$sym" .config || {
		echo "ERROR: $sym missing from .config" >&2
		exit 1
	}
done

grep -qE '^CONFIG_PACKAGE_luci-ssl(-openssl)?=y$' .config || {
	echo "ERROR: luci-ssl / luci-ssl-openssl missing from .config" >&2
	exit 1
}

grep -qE '^CONFIG_TARGET_(DEVICE_)?ramips_mt7621_DEVICE_hiwifi_hc5962=y$' .config || {
	echo "ERROR: hiwifi_hc5962 device not selected" >&2
	exit 1
}

if grep -qx 'CONFIG_PACKAGE_wpad-basic-mbedtls=y' .config; then
	echo "ERROR: wpad-basic-mbedtls is still selected next to wpad-openssl" >&2
	exit 1
fi

if [ "${DEFCONFIG_ONLY:-0}" = "1" ]; then
	echo "==> defconfig only (DEFCONFIG_ONLY=1)"
	exit 0
fi

echo "==> downloading"
make download -j"$JOBS" || make download -j1 V=s

echo "==> building with $JOBS jobs"
make -j"$JOBS" || make -j1 V=s

echo
echo "==> images ($SOURCE):"
find bin/targets/ramips/mt7621 -maxdepth 1 -type f -printf '%f %s\n' 2>/dev/null || \
	ls -lh bin/targets/ramips/mt7621/
