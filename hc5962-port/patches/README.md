# No board patches are currently required.
#
# Every supported tree already carries:
#   - target/linux/ramips/dts/mt7621_hiwifi_hc5962.dts
#   - Device/hiwifi_hc5962 in target/linux/ramips/image/mt7621.mk
#   - the mt7603/mt76x2 drivers and firmware
#
# If a future tree needs a fix, drop NN-name.patch files into
# patches/<main|2512|2410|immortalwrt|lede>/; apply.sh applies them with
# "git apply" before copying the overlay.
