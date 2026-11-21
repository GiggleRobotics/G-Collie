# 参与 G-Collie 开发

G-Collie 把电脑上已有的 Agent 会话带到手机和浏览器。修复控制操作时，请先明确目标电脑、会话和请求。用户在慢连接上切换会话后，迟到的回执仍应归到原来的操作。

## 本地开发

从仓库根目录运行。电脑端使用 Node.js 22、npm 和 Python 3。前端和服务端共用一个开发入口，Vite 由服务进程加载。

```bash
npm ci
PORT=4321 npm run dev
```

在同一台电脑打开 `http://127.0.0.1:4321`。源码模式默认把配对和工作台状态写入仓库内被忽略的 `.data/`，也可以通过 `GCOLLIE_DATA_DIR` 指向专用测试目录。这个变量只改变 G-Collie 自身的数据目录。需要测试创建、停止或审批时，使用隔离接口或专用 Agent 会话。[测试指南](TESTING.md)

## 从用户操作定位代码

| 要修改的行为 | 先读这些入口 |
| --- | --- |
| 浏览器配对、设备角色或撤销访问 | 登录表单在 [web/main.tsx](web/main.tsx)，管理端界面在 [web/DeviceSettings.tsx](web/DeviceSettings.tsx)。设备身份和一次性邀请码由 [server/auth.ts](server/auth.ts) 管理，HTTP 权限检查在 [server/index.ts](server/index.ts)。 |
| 读取会话、打开历史、连接原助手 | Codex 和 Hermes 的本地历史从 [server/local.ts](server/local.ts) 调用 [scripts/read-local.py](scripts/read-local.py)。Codex 桌面与终端分别接入 [desktop.ts](server/desktop.ts) 和 [codex-app-server.ts](server/codex-app-server.ts)。Hermes 的实时控制在 [hermes.ts](server/hermes.ts)，Claude Code 的历史投影与控制在 [claude.ts](server/claude.ts)。 |
| 新建会话、首条消息、迟到的发送回执 | 从 [server/session-create.ts](server/session-create.ts) 的请求账本追踪到路由和适配器。网页输入与导航在 [web/ChatConsole.tsx](web/ChatConsole.tsx)。手机端由 [main.dart](flutter_client/lib/main.dart) 调用 [api.dart](flutter_client/lib/api.dart)，待确认消息保存在 [pending_messages.dart](flutter_client/lib/pending_messages.dart)。 |
| 文件、图片、工具记录 | 上传归属在 [server/attachments.ts](server/attachments.ts)，从历史引用解析可读资源在 [server/resources.ts](server/resources.ts)。网页组件见 [SessionMedia.tsx](web/SessionMedia.tsx) 和 [ProcessRecord.tsx](web/ProcessRecord.tsx)。手机资源读取见 [resources.dart](flutter_client/lib/resources.dart)，消息展示见 [ui.dart](flutter_client/lib/ui.dart)。 |
| 私网、Android 系统交互 | 电脑网络服务由 [embedded-network.ts](server/embedded-network.ts) 调用网络程序。Go 实现在 [network/](network/)，手机通过 [native.dart](flutter_client/lib/native.dart) 和 [Android 平台代码](flutter_client/android/app/src/main/) 接入。 |

通过[能力矩阵](docs/能力矩阵.md)核对助手支持的操作。界面改动可对照[页面流程](docs/开发/03-当前界面与流程.md)和[交互原型](docs/开发/交互原型/README.md)。已公开的官网首页、下载区与首次连接教程位于 [`gh-pages` 分支](https://github.com/GiggleRobotics/G-Collie/tree/gh-pages)。

普通网页开发只需运行 Node 服务。涉及内置网络的手机构建还需要 Go 和 Android NDK。依赖版本分别见 `network/go.mod`、`flutter_client/pubspec.yaml` 和 Gradle 配置。

## 提交问题和改动

- 问题报告请给出系统、电脑端与手机版本、Agent 来源、最短复现步骤和预期结果。连接问题请注明使用局域网还是内置私网。[提交 Issue](https://github.com/GiggleRobotics/G-Collie/issues)
- 一个 Pull Request 聚焦一个用户问题。说明改了哪条路径、如何复现、跑过哪些检查，以及仍需哪些设备或账号才能验证。涉及页面改动时附上使用演示数据的前后对比。
- 回执、授权和资源读取应覆盖失败路径。可复用仓库中同类测试的临时目录和模拟接口。真实聊天记录、设备凭据、配对链接与签名材料请保留在本地。
- 项目代码采用 GPL-3.0-only。引入第三方代码、字体、图标或随包二进制时，保留来源和授权说明。[许可证](LICENSE) · [第三方声明](THIRD_PARTY_NOTICES.md)

## 构建发行产物

从根目录执行 `npm run build` 生成网页静态文件。DEB 和 Android APK 使用独立脚本组装发行产物。

- 内置网络使用 Go 1.27.2 和 Android NDK r27d 构建。准备工具链后运行 `npm run build:network`，工具路径可通过 `GCOLLIE_GO` 和 `GCOLLIE_ANDROID_NDK` 指定。
- Linux DEB 需要 amd64 Node.js 22.22.1 发行目录及其 LICENSE、FFmpeg 7.0.2、FFmpeg 对应源码与构建记录。Node 放入 `.tools/node-v22.22.1-linux-x64/`。在 `.tools/ffmpeg-release/` 准备官方源包，从该目录运行仓库的 `scripts/build-release-ffmpeg.sh`，脚本校验源码 SHA256。使用与目标系统兼容的构建环境。对应已发行 DEB 的源码和构建材料随包安装在 `/usr/share/doc/g-collie/ffmpeg/`。
- 准备完上述依赖、许可证与构建材料后运行 `npm run package:deb`。Android 的签名配置、ABI 和验签步骤见 [Android 开发指南](flutter_client/README.md#正式签名与打包)。
- 发布说明按 Tag 记录下载文件、版本、兼容性、SHA256 和升级方式。发布前请核对产物中的配置与许可证，并用隔离环境运行安装包。[公开发行说明](RELEASE.md)
