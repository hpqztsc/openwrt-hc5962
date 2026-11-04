# HiWiFi HC5962（极路由4 / B70）— multi-source OpenWrt build

在多个主流 OpenWrt 源码树上构建 HC5962 固件，并预置：

- **AP + STA**：一块射频连接已有 Wi-Fi，另一块给其他设备当 AP；
- **有线 802.1X**：WAN 口做标准 EAPOL 认证（PEAP / TTLS / TLS / PWD）；
- **双上行主备**：有线 metric 10，Wi-Fi STA metric 20，有线优先、自动回退；
- 常用 LuCI、证书、USB 存储/文件系统等软件包。

官方源码里已经有 HC5962 的 DTS、镜像配方和 mt76 驱动，因此**不需要移植驱动或改 DTS**。本目录只负责构建配方、首启网络/无线配置和 802.1X 服务。

## 支持的源码

| id | 源码 | 分支 | 内核 | 包管理器 |
|---|---|---|---|---|
| `main` | `openwrt/openwrt` | `main` | 6.18 | apk |
| `2512` | `openwrt/openwrt` | `openwrt-25.12` | 6.12 | apk |
| `2410` | `openwrt/openwrt` | `openwrt-24.10` | 6.6 | opkg |
| `immortalwrt` | `immortalwrt/immortalwrt` | `master` | 6.18 | apk |
| `lede` | `coolsnowwolf/lede` | `master` | 6.18 | opkg |

五个树都自带：

- `target/linux/ramips/dts/mt7621_hiwifi_hc5962.dts`
- `Device/hiwifi_hc5962`（NAND，`IMAGE_SIZE 32768k`）
- mt7603 / mt76x2 驱动与固件
- `wpad-openssl` 的 full 构建（含 `CONFIG_DRIVER_WIRED=y` 和完整 EAP/TLS）

所以 `patches/` 目前是空的。LEDE 还额外有 `hiwifi_hc5962-spi-breed`（16M SPI + Breed）变体，本配方选择的是**原厂 128M NAND 布局** `hiwifi_hc5962`。

## 目录

```
hc5962/
├── hc5962-port/
│   ├── apply.sh                    # 把 overlay/patches 应用到源码树
│   ├── config/common.config        # 公共软件包
│   ├── config/<source>.config      # 各源码的目标/设备/包管理器
│   ├── files/common/               # 所有源码共用的 rootfs overlay
│   └── patches/<source>/           # 预留，当前为空
├── scripts/build.sh                # 本地 Linux 构建（按 source 选择）
└── .github/workflows/build-hc5962.yml  # 五路 matrix 构建
```

`apply.sh` 的行为和 c526a-port 一致：

1. 检查源码树；
2. 对 `patches/<source>/*.patch` 依次 `git apply`；
3. 把 `files/common/` 作为 rootfs overlay 复制到源码树的 `files/`；
4. 如果存在 `files/<source>/`，再覆盖一层（用于源码差异）。

## 软件包

`config/common.config` + 各源码配置选择：

- `luci-ssl`（LuCI + HTTPS + `luci-app-package-manager` + IPv6/PPP 协议；LEDE 用 `luci-ssl-openssl` 以匹配其默认的 libustream-openssl）
- 中文翻译：base / firewall / package-manager
- `wpad-openssl`（full：AP + STA + wired 802.1X）、`wpa-cli`、`hostapd-utils`
- `iw`、`iwinfo`、`ip-tiny`
- `kmod-mt7603`、`kmod-mt76x2`
- `ca-bundle`、`openssl-util`、`curl`
- USB 存储：`kmod-usb-storage(-uas)`、ext4/vfat/exfat/ntfs3、`block-mount`、`usbutils`、`e2fsprogs`、`dosfstools`

mt7621 目标默认会选 `wpad-basic-mbedtls`，`common.config` 里显式关闭它，避免和 `wpad-openssl` 冲突。

## 运行 profile

`apply.sh` 和 `build.sh` 支持三种 overlay profile：

| profile | 网络模式 | LAN |
|---|---|---|
| `default` | NAT 路由，WAN 有线/802.1X + WiFi STA | `192.168.123.1/24`，DHCP 开 |
| `ap` | AP/桥接，DHCP/NAT 关闭，relayd 桥接 WiFi STA | `192.168.1.30/24`，网关 `192.168.1.1` |
| `mwan` | 多 WAN NAT，mwan3 failover `wan -> wwan -> usbwan` | `192.168.123.1/24` + 管理 alias `192.168.1.30/32` |

`mwan` 的三路上行：

- `wan`：有线，DHCP，可在同一接口上跑 802.1X
- `wwan`：WiFi STA，`hc5962-wifi uplink` 或 travelmate 管理
- `usbwan`：USB 网卡/手机共享，默认 `usb0` + DHCP；4G/5G 模块可改成 `qmi`/`mbim`

注意：`192.168.1.30` 作为 LAN alias 的前提是**没有任何 WAN 使用 192.168.1.0/24**。如果有线 802.1X 上连也是 192.168.1.0/24，请把 `.30` 放到独立管理 VLAN/端口，或改用 `default` 的独立 LAN 网段。mwan3 只做 IPv4 failover，策略名 `failover`，成员按 `wan -> wwan -> usbwan` 排序。

## 构建

### 本地 Linux

要求 Linux + **GNU tar >= 1.35**（Ubuntu 22.04 自带 1.34，会让 git 源的 tarball 哈希和 OpenWrt 期望值不一致；可自行编译 tar 1.35）。脚本会自动设置 `FORCE_UNSAFE_CONFIGURE=1`，因为以 root 构建时 OpenWrt 的 host tools 需要它。

```sh
./scripts/build.sh 2512            # openwrt-25.12
./scripts/build.sh main            # openwrt main
./scripts/build.sh 2410            # openwrt-24.10
./scripts/build.sh immortalwrt
./scripts/build.sh lede

# 多 WAN / AP 桥接 profile
PROFILE=mwan ./scripts/build.sh 2410
PROFILE=ap   ./scripts/build.sh 2410
```

可选环境变量：

```sh
SRC=/workdir/openwrt ./scripts/build.sh 2512
DL_DIR=/workdir/dl JOBS=16 ./scripts/build.sh 2512
```

默认源码目录是 `build/<source>/openwrt`，下载缓存在 `dl/`。镜像输出在：

```
build/<source>/openwrt/bin/targets/ramips/mt7621/
```

### GitHub Actions

推送到 GitHub 后运行 **Build OpenWrt for HC5962**。workflow 用 matrix 并行构建五个源码，每个源码一个 artifact：

```
openwrt-hc5962-openwrt-main-<run>
openwrt-hc5962-openwrt-25.12-<run>
openwrt-hc5962-openwrt-24.10-<run>
openwrt-hc5962-immortalwrt-<run>
openwrt-hc5962-lede-<run>
```

## 刷机

- 首次从原厂固件：用 `...factory.bin`，按 HC5962 设备页 / 不死 U-Boot 的恢复方式上传。
- 已经在跑 OpenWrt / LEDE：

  ```sh
  sysupgrade -n openwrt-ramips-mt7621-hiwifi_hc5962-squashfs-sysupgrade.bin
  ```

  从 LEDE / immortalwrt / 旧布局切换时建议 `-n`，刷完重新配置。
- 刷机前备份：`sysupgrade -b /tmp/backup.tar.gz`，保存到电脑。

## 默认配置

首启脚本 `/etc/uci-defaults/90-hc5962` 只执行一次（标记 `/etc/hc5962-initialized`，`sysupgrade` 保留配置时不会覆盖用户设置）：

- LAN：`192.168.123.1/24`，DHCP `.100-.249`
- WAN：DHCP，metric 10
- WWAN（Wi-Fi STA）：DHCP，metric 20；自动加入 firewall `wan` zone
- 2.4G AP：SSID `HC5962`，密码 `12345678`
- 5G STA：默认关闭，等待 `hc5962-wifi uplink` 配置
- 主机名 `HC5962`，时区 `Asia/Shanghai`，NTP 阿里/中国 NTP
- LuCI 默认中文（如果安装了中文语言包）
- root 首次为空密码，请立即在 LuCI 设置

## 连接已有 Wi-Fi（STA 上行）

默认 5G 去连上游，2.4G 继续做 AP：

```sh
hc5962-wifi uplink "Upstream-SSID" "Upstream-Password"
```

上游是 2.4G（或想用 2.4G 连、5G 发）：

```sh
hc5962-wifi uplink "Upstream-SSID" "Upstream-Password" 2g
```

开放网络：

```sh
hc5962-wifi uplink "Free-WiFi" ""
```

查看状态：

```sh
hc5962-wifi status
```

WPA3-only 上游：

```sh
uci set wireless.sta_5g.encryption='sae'
uci commit wireless && wifi reload
```

恢复无线默认布局（会清掉自定义 Wi-Fi 配置）：

```sh
hc5962-wifi reset
```

说明：`uplink` 把选中频段设为 STA，另一频段设为 AP；同一频段不会同时跑 STA 和 AP。若用有线做上行、想额外开 5G AP，在确认 `sta_5g` 关闭后执行：

```sh
uci set wireless.ap_5g.disabled=0
uci commit wireless && wifi reload
```

## 有线 802.1X

服务默认关闭（`/etc/config/dot1x` 的 `enabled 0`），设置账号后自动启用。

PEAP/MSCHAPv2（校园网最常见）：

```sh
8021x set 'user@campus' 'password'
```

TTLS/PAP：

```sh
8021x set 'user' 'password' ttls 'auth=PAP'
```

EAP-TLS：

```sh
8021x set-tls 'user@campus' /etc/8021x/ca.pem \
    /etc/8021x/client.pem /etc/8021x/client.key
```

在 VLAN 子接口上认证：

```sh
8021x device wan.100
# 同时把 network.wan.device 改成 wan.100，或使用 VLAN 设备
```

查看状态 / 日志 / 配置：

```sh
8021x status
8021x log 100
8021x show
```

工作机制：

- `/etc/init.d/8021x` 的 `START=19`，早于 `network`（20）；先 `ip link set wan up`，再启动 `wpa_supplicant -D wired`；
- netifd 的 DHCP 客户端使用 `-t 0` 持续重试；
- 认证状态由 `8021x-watch` 监视，进入 `COMPLETED` 时执行 `ubus call network.interface.wan renew`，兼容“认证前先发 guest VLAN 地址”的交换机；
- 有线 `wan` metric 10、Wi-Fi `wwan` metric 20，两条上行可同时存在。

排查：

```sh
logread -e wpa_supplicant
8021x log 100
wpa_cli -p /var/run/wpa_supplicant-wired -i wan status
ip route
ifstatus wan
ifstatus wwan
```

常见问题：

- **认证一直失败**：确认交换机是标准 802.1X/EAPOL。锐捷私有协议、MentoHUST 之类不是标准 EAP，`wpa_supplicant` 无法代替。
- **EAP-TLS 证书时间错误**：设备没有 RTC，刚启动时可能是 1970；等 NTP 同步或先手动 `date`。PEAP/TTLS 不校验证书时不受影响。
- **交换机要求 EAPOL v2**：`uci set dot1x.wan.eapol_version=2 && /etc/init.d/8021x restart`。
- **认证过了但没有 IP**：确认 `network.wan.proto` 还是 `dhcp`；校园网通常是 802.1X 后 DHCP。
- **8021X 配置没有生效**：`/etc/init.d/8021x` 需要启用；首启脚本会自动 `enable`，手动装文件时执行一次 `/etc/init.d/8021x enable`。

## 上行优先级

```sh
uci get network.wan.metric     # 10
uci get network.wwan.metric    # 20
# 让 Wi-Fi 优先：
uci set network.wan.metric=20
uci set network.wwan.metric=10
uci commit network && ifup wan && ifup wwan
```

## 各源码注意事项

- **25.12 / main / immortalwrt**：默认 apk，LuCI 使用 `luci-app-package-manager`；固件内 `apk` 命令管理软件包。
- **24.10 / lede**：默认 opkg；`luci-app-package-manager` 会自动检测 `/usr/bin/apk`，不存在时使用 opkg。
- **LEDE**：还提供 `hiwifi_hc5962-spi-breed`（16M SPI + Breed）。本配方选择 NAND 版；硬改 SPI 的机器需把 `config/lede.config` 里的设备改成 `DEVICE_hiwifi_hc5962-spi-breed`。
- **LEDE 不生成 initramfs**：其 `uimage-lzma-loader` 与 sysupgrade 共用 kernel 文件会冲突，只产出 factory/sysupgrade。其余四个源码默认同时产出 initramfs。
- **24.10**：ramips DTS 路径与 main/25.12 相同（`target/linux/ramips/dts/`），不需要额外补丁。

## 构建验证

2026-11-04 在 Ubuntu 22.04（32 核 / 32 GB，GNU tar 1.35）上完成：

- `main` / `2512` / `2410` / `immortalwrt` / `lede` 五个源码的 `make defconfig` 全部通过；
- 五个源码的完整构建全部通过，产物约 11–16 MB（factory / sysupgrade，部分含 initramfs）；
- 设备、`wpad-openssl`、`luci-ssl` 等关键包在 `.config` 中均正确选中。

踩坑记录：

- Ubuntu 22.04 的 GNU tar 1.34 会让 git 源 tarball 的哈希与 OpenWrt 期望值不一致，需要 tar >= 1.35；
- OpenWrt 以 root 构建需要 `FORCE_UNSAFE_CONFIGURE=1`（脚本已设置）；
- 不能 `git clone --depth 1`：base-files 用 `git describe` 生成版本，浅克隆会得到 apk 不接受的 `~unknown`；
- LEDE 的 6.18 内核默认带 BTF/FTRACE/perf/debug info，会超过 HC5962 的 4 MB kernel 分区；`config/lede.config` 已关闭这些选项；
- LEDE 的 `uimage-lzma-loader` 与 sysupgrade 共用 kernel 目标，因此 LEDE 配置不生成 initramfs；
- LEDE 默认 LuCI 应用集依赖 `libustream-openssl`，所以 LEDE 使用 `luci-ssl-openssl` 而不是 `luci-ssl`。

## 已知限制

- 只支持标准 802.1X/EAPOL；锐捷等私有认证需要专用客户端。
- 802.1X 通过 `/etc/config/dot1x` + `8021x` 命令行配置，没有专用 LuCI 页面。
- HC5962 是 Wi-Fi 5：2.4G 最高 300 Mbps、5G 最高 867 Mbps，不支持 802.11ax/6 GHz。
- 默认用两块射频分别做 STA/AP，不做同频段 STA+AP 并发。
- 25.12 / 24.10 的 HC5962 仍是 swconfig；未来上游切 DSA 时网络配置需要相应调整。
