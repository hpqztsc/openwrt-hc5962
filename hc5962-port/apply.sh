#!/bin/sh
#
# Apply HC5962 support/overlay on top of a clean OpenWrt tree.
#
# Usage: ./apply.sh <main|2512|2410|immortalwrt|lede> [path-to-openwrt]
#
# The device (ramips/mt7621/hiwifi_hc5962) is already present in every
# supported tree, so no board patch is required.  The patches/<source>/
# directories exist for future fixes; overlay files are copied from
# files/common (and files/<source> if it exists).
#
set -eu

SRC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE=${1:-}
OWRT_DIR=${2:-openwrt}

case "$SOURCE" in
main|2512|2410|immortalwrt|lede) ;;
*)
	echo "error: unknown source '$SOURCE'" >&2
	echo "use: main | 2512 | 2410 | immortalwrt | lede" >&2
	exit 1
	;;
esac

if [ ! -d "$OWRT_DIR/target/linux/ramips" ]; then
	echo "error: $OWRT_DIR does not look like an OpenWrt ramips tree" >&2
	exit 1
fi

cd "$OWRT_DIR"

if [ -d "$SRC_DIR/patches/$SOURCE" ]; then
	for p in "$SRC_DIR/patches/$SOURCE"/*.patch; do
		[ -e "$p" ] || continue
		echo "==> applying $(basename "$p")"
		git apply --check "$p"
		git apply "$p"
	done
fi

echo "==> installing common files"
mkdir -p "$OWRT_DIR/files"
cp -R "$SRC_DIR/files/common/." "$OWRT_DIR/files/"

if [ -d "$SRC_DIR/files/$SOURCE" ]; then
	echo "==> installing $SOURCE files"
	cp -R "$SRC_DIR/files/$SOURCE/." "$OWRT_DIR/files/"
fi

# Enable the 802.1X service in the image itself, so it also runs on the very
# first boot (uci-defaults "enable" is kept as a fallback for manual installs).
mkdir -p "$OWRT_DIR/files/etc/rc.d"
ln -sf ../init.d/8021x "$OWRT_DIR/files/etc/rc.d/S198021x"
ln -sf ../init.d/8021x "$OWRT_DIR/files/etc/rc.d/K898021x"

# When building as root (common on a build VM), do not leave the overlay
# files owned by the user that created the tarball.
if [ "$(id -u)" = 0 ]; then
	chown -R 0:0 \
		"$OWRT_DIR/files/etc/config/dot1x" \
		"$OWRT_DIR/files/etc/init.d/8021x" \
		"$OWRT_DIR/files/etc/uci-defaults/90-hc5962" \
		"$OWRT_DIR/files/usr/lib/hc5962" \
		"$OWRT_DIR/files/usr/sbin/8021x" \
		"$OWRT_DIR/files/usr/sbin/hc5962-wifi" \
		"$OWRT_DIR/files/etc/rc.d/S198021x" \
		"$OWRT_DIR/files/etc/rc.d/K898021x" 2>/dev/null || true
fi

echo "==> done"
