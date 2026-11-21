# G-Collie 0.3.35 / Android 0.1.51

2026-11-17 发布。电脑服务与网页为 0.3.35，Android 为 0.1.51（arm64 构建号 2058，x86_64 构建号 4058）。下文对应公开标签 v0.3.35。工作区中的后续改动见 [更新日志](docs/更新日志.md)。

[GitHub Release 与下载](https://github.com/GiggleRobotics/G-Collie/releases/tag/v0.3.35) · [完整验证记录](docs/开发/06-版本发布记录.md) · [能力矩阵](docs/能力矩阵.md)

## 本版变化

- 修复手机会话详情瞬断后的只读重试、历史稳定ID归并和未知发送结果防重放。
- Codex工具“已查看图像”进入原工具记录，默认折叠，点击标题展开／收起，图片靠左；内部子Agent不再误入普通会话列表。
- Markdown授权相对图片默认加载；文件缺失、无权限或加载失败仅显示图片图标和图片名称。
- 配对地址和验证码框支持粘贴完整邀请链接，不自动提交。
- 纯终端Codex使用原生app-server／安全现存daemon；修复旧数据库兼容、派生JPEG条纹、内置网络子进程代理继承和Hermes未知结果误判。
- 真实Hermes旧sidecar支持浮点秒轮次标识；新版gateway按已核验的实例、profile及authority幂等附着已运行会话。缺失runtime拒绝冷接管；审批要求完整回放和当前代际。

## 下载与升级

| 使用环境 | Release 附件 |
| --- | --- |
| Linux amd64 电脑 | `g-collie_0.3.35_amd64.deb` |
| 首次安装的 arm64 Android 手机 | `g-collie-0.1.51-android-arm64-release.apk` |
| x86_64 Android 设备或模拟器 | `g-collie-0.1.51-android-x86_64-release.apk` |
| 已使用旧内测签名的 arm64 手机 | `g-collie-flutter-0.1.51-arm64-beta.apk` |

下载文件及其同名 `.sha256` 到同一目录。以 Linux DEB 为例：

```bash
sha256sum -c g-collie_0.3.35_amd64.deb.sha256
sudo apt install ./g-collie_0.3.35_amd64.deb
g-collie
```

首次连接见 [电脑使用手册](docs/电脑端使用说明.md) 和 [手机使用手册](docs/手机端使用说明.md)。升级前请保留旧包和数据备份。电脑端数据位于 `~/.local/share/g-collie`。运行 `g-collie backup` 会短暂停止 G-Collie 服务，备份含设备授权和网络身份，请择时运行并私密保管。

## Android 签名与升级

生产证书 SHA256 为 `6286e58588a3b92e786f4511bb84cb59e954b527e2bf2c1f3e11c5b2e80cc08b`。旧内测覆盖包与生产包使用不同证书。升级已有安装请选择原签名对应的文件，核对签名后覆盖安装可保留数据。Release 同时提供源码包、生产签名元数据与 SHA256 清单。DEB 的完整性校验使用随包 SHA256。

## 本轮验证

该 Tag 的服务端 178 项测试、Flutter 162 项测试、静态分析、网页构建及 Go 核心 race 回归通过。Codex 0.169 与 Hermes 在隔离会话和回环模型下验证了原生控制。Android 使用旧内测同签包在小米手机上验收升级、图片和 Markdown 展示，以及约 8 分钟后台期间切网后追平和去重。生产双 ABI APK 单独核验签名和 16 KiB 对齐。[发行验收记录](docs/开发/06-版本发布记录.md)

## 能力边界

Codex终端计划模式、Codex／Claude安全删除仍未适配；Claude需本人登录。Hermes停止只针对当前轮，不承诺清空排队消息；不支持安全原子冷恢复的环境明确拒绝接管。实验协议能力取决于原生版本和会话状态，不等同所有助手共享相同能力。

本轮真实传输测试使用合成消息，真实CLI／Hermes控制使用本地模型；没有宣称生产账号额度、全部外部模型、全天候锁屏、所有网络／VPN、主机重启自启或所有Android机型均已验证。历史系统兼容证据及未覆盖环境继续见开发记录。未知请求或结果不自动重放。

项目代码GPL-3.0-only，第三方条款见LICENSE／NOTICE／THIRD_PARTY_NOTICES.md。FFmpeg对应完整源码与构建脚本随DEB位于`/usr/share/doc/g-collie/ffmpeg/`。原始私人截图、账号凭据和签名私钥不随发行提供。
