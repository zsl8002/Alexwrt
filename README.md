# AlexWrt

面向 JDCloud RE-CS-02 / AX6600 与 PVE x86_64 的双固件自动构建项目。

## 上游参考
- 设备适配与配置参考：https://github.com/ones20250/Openwrt-AX6600
- IPQ 专用源码（设备适配仓库当前采用）：https://github.com/ones20250/immortalwrt_ipq
- ImmortalWrt：https://github.com/immortalwrt/immortalwrt
- OpenWrt：https://github.com/openwrt/openwrt
- PassWall2：https://github.com/Openwrt-Passwall/openwrt-passwall2
- PassWall packages：https://github.com/Openwrt-Passwall/openwrt-passwall-packages

## 两条构建线
1. AX6600：采用 ones20250 的 IPQ60xx 设备适配源码，目标固定为 qualcommax/ipq60xx JDCloud RE-CS-02。设备适配、分区布局和无线驱动不能简单替换成通用 OpenWrt 主线。
2. PVE：每日解析 OpenWrt 最新正式稳定 release tag，以该 tag 为基础编译 x86_64。保留 OpenWrt 官方 feeds；仅将 packages feed 的 Go 工具链目录更新到上游 master（当前 Xray-core 需要 Go 1.27，而 OpenWrt 25.12 稳定 feed 默认 Go 1.26），其余官方 packages feed 仍使用稳定分支。额外启用 ImmortalWrt 官方 packages 与 luci 两个独立 overlay feed，作为 OpenWrt 官方生态之上的补充。

## ImmortalWrt 生态集成\nPVE 与 AX6600 两条构建线均启用 ImmortalWrt 官方 packages、luci feed，分别使用 immortal_packages、immortal_luci 名称，与 OpenWrt 官方 packages/luci feed 并存；OpenWrt 官方 routing、telephony、video 等 feeds 保持不变。构建先安装 OpenWrt 官方 feeds，再以非强制方式安装 ImmortalWrt feeds（不使用 feeds install -f），同名包不覆盖 OpenWrt 核心包或已安装的官方 feed 包，只有不冲突的软件包进入可选构建目录。每次构建记录两条 ImmortalWrt feed 的 Git commit。\n\n注意：这是源码级 feed 生态叠加，不代表 ImmortalWrt 整个发行版的内核补丁、设备树、默认配置或二进制仓库被移植；每个实际选入固件的软件包仍须经过当前目标架构、依赖和编译验证。\n\n## PassWall2、依赖与签名
PassWall2 和 passwall-packages 在构建时从上游克隆并记录 commit，优先从源码编译进固件。预选依赖包括 xray-core、sing-box、v2ray-geoip、v2ray-geosite、tcping、geoview。PVE 的 OpenWrt 25.12 软件包 feed 当前提供 Go 1.26.x，因此 PVE 构建将 Xray-core 固定到上游 26.7.11（其 go.mod 要求 Go 1.26），并使用上游公布的源码 SHA256；待基础 Go 工具链升级到 1.27 后再解除此兼容性固定。AX6600 构建不应用该 PVE 专用版本固定。

不使用 apk add --allow-untrusted，不关闭签名校验，不把本地临时 key 当作官方 key。PassWall 上游 APK feed 的签名公钥必须与实际索引签名匹配；遇到 key 下载失败、证书时间错误或验签失败时必须停止，不得绕过。

PVE 构建会跳过未选入固件的 Prosody feed 包：当前稳定 feed 中该包引用的四个 Lua 5.4 模块不可用，且 Prosody 不属于本固件功能范围。不会修改官方 Prosody 配方或关闭依赖检查。当前首版采用源码编译预装 PassWall2，尚未宣称已配置可在线更新的 AlexWrt 自有签名 APK/IPK 仓库。后续自有 feed 必须使用 GitHub Secrets 中的专用私钥签名，并在镜像内预置对应公钥。

## 更新
- 软件包：使用系统原生包管理器及发行版官方签名仓库。PassWall2 更新随本项目成功构建的固件发布；自有签名 feed 部署完成前，不会伪称可从第三方仓库无缝更新。
- 整机：包含 attendedsysupgrade。通过 LuCI/ASU 检查匹配设备的 sysupgrade 并确认执行。默认不启用无人确认的强制自动刷写，避免断电、分区不匹配或错误镜像导致变砖。
- AX6600 必须区分 factory 与 sysupgrade 镜像；刷机前备份分区、配置并确认恢复方式。

## 产物
Actions 构建成功后上传固件、最终 .config、上游 commit 清单和 SHA256SUMS，并创建日期 Release。构建失败、目标镜像缺失或签名检查失败时不发布。

## 状态说明
这是自动构建骨架。PVE 与 AX6600 均已配置 ImmortalWrt packages/luci 双 feed overlay；首次运行需实际验证上游 feed 与 OpenWrt 当前版本的兼容性、依赖、目标 profile、包名和内核 ABI。当前尚未完成真实设备刷机验证；AX6600 factory 镜像仅在上游确实生成并通过文件检查时发布。