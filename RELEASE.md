# G-Collie 0.3.36 / Android 0.1.52

2026-11-21 发布。Linux 电脑端和网页工作台为 0.3.36，Android 为 0.1.52（arm64 构建号 2063，x86_64 构建号 4063）。

[GitHub Release 与下载](https://github.com/GiggleRobotics/G-Collie/releases/tag/v0.3.36) · [手机首次连接演示](https://gigglerobotics.github.io/G-Collie/start/#phone-demo) · [浏览器配对演示](https://gigglerobotics.github.io/G-Collie/start/#browser-demo)

## 本版变化

- 修复 Codex、Hermes 和 Claude Code 部分旧会话能看到消息却打不开图片的问题。网页可从工具记录查看图片，网页与 Android 的多图会话可浏览远端图片附件。
- 新建会话等待电脑确认时保留草稿和附件，并可查询原请求。已有会话的迟到回执按原会话处理。
- 窄屏网页可以从辅助页面直接返回会话列表。网页标题和 Android 关于页统一使用「G-Collie · Agent 会话控制台」。
- Codex 桌面接入兼容会话流协议 v13，保留 v11 支持。

## 下载与升级

| 使用环境 | Release 附件 |
| --- | --- |
| Linux amd64 电脑 | `g-collie_0.3.36_amd64.deb` |
| 首次安装的 arm64 Android 手机 | `g-collie-0.1.52-android-arm64-release.apk` |
| x86_64 Android 设备或模拟器 | `g-collie-0.1.52-android-x86_64-release.apk` |
| 已使用旧内测签名的 arm64 手机 | `g-collie-flutter-0.1.52-arm64-beta.apk` |

下载文件及其同名 `.sha256` 到同一目录。以 Linux DEB 为例：

```bash
sha256sum -c g-collie_0.3.36_amd64.deb.sha256
sudo apt install ./g-collie_0.3.36_amd64.deb
g-collie
```

首次连接见 [电脑使用手册](docs/电脑端使用说明.md) 和 [手机使用手册](docs/手机端使用说明.md)。升级前请保留旧包和数据备份。电脑端数据位于 `~/.local/share/g-collie`。运行 `g-collie backup` 会短暂停止 G-Collie 服务，备份含设备授权和网络身份，请择时运行并私密保管。

## Android 签名与升级

生产证书 SHA256 为 `6286e58588a3b92e786f4511bb84cb59e954b527e2bf2c1f3e11c5b2e80cc08b`。旧内测覆盖包与生产包使用不同证书。升级已有安装请选择原签名对应的文件，核对签名后覆盖安装可保留数据。Release 同时提供源码包、生产签名元数据与 SHA256 清单。DEB 的完整性校验使用随包 SHA256。

## 源码与许可

Release 附有对应源码、签名元数据及校验文件。FFmpeg 的源码和构建材料随 DEB 安装在 `/usr/share/doc/g-collie/ffmpeg/`。[更新日志](docs/更新日志.md) · [能力矩阵](docs/能力矩阵.md) · [第三方许可](THIRD_PARTY_NOTICES.md)
