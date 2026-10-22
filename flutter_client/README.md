# G-Collie Flutter Android 客户端

沿用现有 G-Collie 页面布局、文案、配色、边牧素材及 Lucide 图标，仅将界面实现切换为 Flutter；未修改原版 React 页面或旧 APK。界面使用 Flutter 组件，复用现有 G-Collie 电脑服务，应用 ID 为 `dev.giggle.g_collie_flutter`，可与旧 APK 同时安装。

## 运行

需要 Flutter stable（本次验证 3.47.7 / Dart 3.13.5）、JDK 17、Android SDK 34/35/36、Build Tools 36、NDK 28.2.13676358 和 CMake 3.22.1（平台版本由插件使用）。支持 Android 8+。

```bash
cd flutter_client
flutter pub get
flutter run
```

```bash
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

生成的内测 APK：`build/app/outputs/flutter-apk/app-debug.apk`。当前使用 Android 内测签名，不作为正式分发签名。

正式体验请使用 Release 内测包：在项目根目录执行 `npm run package:flutter-apk`，输出 `releases/g-collie-flutter-0.1.0-arm64-beta.apk`。APK 使用原有 `android/lib/` 下的网络模块，首次构建需先运行 `npm run build:network`。

## 连接

电脑照常运行 G-Collie 服务，在“手机与配对”生成配对码。在 Flutter 客户端填写完整电脑地址、六位码和设备名称；也可以粘贴含 `#pair=` 的配对链接。客户端只保存此电脑发放的设备 Cookie，使用系统安全存储，不需要模型 API Key 或电脑管理密钥。

局域网可填写电脑局域网地址。远程连接沿用原 APK 的内置 Tailscale JNI 模块与本机网关，先从顶部菜单“内置网络”完成本应用的独立入网授权，再连接电脑的私网地址。电脑只监听 127.0.0.1 时，需先使用现有服务的局域网/远程访问配置。Android 模拟器访问电脑本机可使用 `http://10.0.2.2:4310`。

局域网 HTTP 与现有服务兼容；跨不可信网络应使用有效证书 HTTPS 或受保护的私有网络。客户端不绕过证书校验，也不自动跟随重定向。

## 已实现

- 六位码/配对链接登录、安全保存凭证、重启恢复、授权失效返回配对页、撤销本设备配对。
- Codex/Hermes 会话列表、搜索、Agent/项目筛选、归档历史查看。
- 加载原会话、最近历史、Markdown 与代码块、选择/复制文本、工具记录折叠、实时回复。
- 新建会话、发送、绑定原执行轮次停止、审批和问题回答；服从服务端只读权限与可用审批选项。
- 附件选择与上传、只读快照分享、Hermes 重命名/归档、日/月用量日历与额度页面。
- 复用原有 JNI 网络库和 Android 前台通知服务，通过平台通道接入；支持配对深链接和通知会话跳转。
- 前台每 2 秒同步当前会话，约 16 秒刷新索引；后台暂停，恢复前台重新同步。
- 断线标为状态未知并禁用操作；请求 ID 去重，写操作不自动重发；切换会话忽略旧响应。

## 当前边界

目前为待真机完整验收的移植版本。部分高级诊断展示仍需补齐；内置网络、原生通知、外部链接跳转、真实附件及长会话需要继续做设备端验收。网络入网与 G-Collie 设备配对仍是两步独立操作，旧 APK 的配对数据不会自动转移到独立包名。

已通过 8 项测试、静态分析、Release 构建与签名验证，已在 Xiaomi 14 安装。无线真机已验证正式服务配对、真实会话及执行状态读取、重启保持配对，以及模拟服务下的输入/发送/回复。最终已切回正式服务；当前使用无线 ADB 端口转发，独立私网和后台通知尚未验收。没有向已有真实 Agent 会话发送测试消息。详细记录见 [VALIDATION.md](VALIDATION.md)。

2026-10-23 USB 真机补充：正式 Hermes 会话输入/发送/真实回复、后台任务完成通知、通知跳转及断线提醒已通过，通知保持开启。当前连接仍依赖 USB ADB 转发；独立私网和长时间后台存活尚未验收。

## 会话图片与文件预览（0.1.1）

会话中的结构化图片会保留并显示；本机 Markdown 图片链接通过已配对服务读取。点击图片进入 Flutter 缩放查看页；PDF、Word（DOCX）、Markdown、TXT 在 App 内打开文档阅读页，不跳转系统浏览器。PDF 支持翻页，Word 支持正文与表格阅读，复杂排版以原文件为准。原文件可通过右上角下载至系统下载目录；旧 DOC 等其他格式可下载后用对应应用打开。

电脑服务只提供会话明确引用的允许类型文件，拒绝敏感配置路径；文档使用 20 分钟有效且绑定设备授权的只读票据，撤销设备授权后失效。文件移动、删除、超过限制或预览链接过期时需要返回会话重新点击。HTML 文档预览通过 App 内 WebView 呈现，聊天主界面仍为 Flutter。

开发部署：当前用户服务通过 `~/.config/systemd/user/g-collie.service.d/90-flutter-preview.conf` 使用项目 `.packaging/preview-server.mjs` 和项目脚本；原系统安装文件保留。重新打包服务端需包含 PDF.js legacy assets（Deb 打包脚本已适配）。

0.1.3：Codex / Hermes 的工具调用与结果合并为紧凑摘要，可展开查看命令和实际输出；呈现可靠的状态、耗时及可用的公开思考摘要。缺少结果或摘要时不补造内容。
