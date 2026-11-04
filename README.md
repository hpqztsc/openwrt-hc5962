# HC5962 multi-source OpenWrt build

HiWiFi HC5962（极路由4 / B70，MT7621A + MT7603 + MT7612，128M NAND）的多源码 OpenWrt 构建配方。

支持：

| id | 源码 | 分支 | 内核 | 包管理器 |
|---|---|---|---|---|
| `main` | `openwrt/openwrt` | `main` | 6.18 | apk |
| `2512` | `openwrt/openwrt` | `openwrt-25.12` | 6.12 | apk |
| `2410` | `openwrt/openwrt` | `openwrt-24.10` | 6.6 | opkg |
| `immortalwrt` | `immortalwrt/immortalwrt` | `master` | 6.18 | apk |
| `lede` | `coolsnowwolf/lede` | `master` | 6.18 | opkg |

设计参考 `hpqztsc/openwrt-c526a` 的 `c526a-main-port` 分支：`apply.sh` + `patches/` + `files/common` + per-source config + CI matrix。HC5962 的 DTS/镜像/驱动在五个树里都已上游化，所以当前没有 board patch。

## 快速开始

```sh
# 本地 Linux 构建（macOS 不能构建 OpenWrt）
./scripts/build.sh 2512
./scripts/build.sh main
./scripts/build.sh 2410
./scripts/build.sh immortalwrt
./scripts/build.sh lede
```

镜像：`build/<source>/openwrt/bin/targets/ramips/mt7621/`。

GitHub Actions：推仓库后运行 **Build OpenWrt for HC5962**，matrix 会并行构建五个源码，每个源码单独 artifact。

## 功能

- 2.4G AP + 5G STA（或对调），`hc5962-wifi uplink "SSID" "密码" [2g|5g]`
- 有线 802.1X：`wpad-openssl` full + `wpa_supplicant -D wired`，支持 PEAP/TTLS/TLS/PWD
- 有线 metric 10 / Wi-Fi STA metric 20，自动主备
- LuCI HTTPS + 中文、证书、USB 存储/文件系统、常用诊断工具
- 默认 LAN `192.168.123.1`，AP `HC5962` / `12345678`，root 首次空密码

详细说明见 [hc5962-port/README.md](hc5962-port/README.md)。

## 目录

```
hc5962-port/apply.sh              # 应用 overlay/patches
hc5962-port/config/               # common + 每个源码的 target config
hc5962-port/files/common/         # rootfs overlay（网络/无线/802.1X）
hc5962-port/patches/              # 当前为空
scripts/build.sh                  # 本地多源码构建
.github/workflows/build-hc5962.yml # 五路 CI matrix
```
