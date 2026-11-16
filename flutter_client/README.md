# G-Collie Flutter Android 客户端

沿用现有 G-Collie 页面布局、文案、配色、边牧素材及 Lucide 图标，仅将界面实现切换为 Flutter；未修改原版 React 页面或旧 APK。界面使用 Flutter 组件，复用现有 G-Collie 电脑服务，应用 ID 为 `dev.giggle.g_collie_flutter`。公开发行只提供这一个 Android 应用，不再分发旧客户端。

## 运行

需要 Flutter stable（本次验证 3.47.7 / Dart 3.13.5）、JDK 17、Android SDK 34/35/36、Build Tools 36、NDK 28.2.13676358 和 CMake 3.22.1（平台版本由插件使用）。公开手机包面向 Android 8+ 的 arm64 设备；x86_64 包用于模拟器验证，暂不提供 32 位 ARM 包。

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

生成的开发 APK：`build/app/outputs/flutter-apk/app-debug.apk`，只用于本地开发，禁止作为公开发行包。

## 正式签名与打包

APK 复用 `android/lib/` 下的 arm64-v8a / x86_64 网络模块，首次构建先运行 `npm run build:network`。正式版本保持应用 ID `dev.giggle.g_collie_flutter`，不能随意更换签名密钥。

签名配置通过环境变量指定项目外的私密文件；未提供完整配置时，Release 构建直接失败，绝不回退到 debug 签名。配置格式如下（示例全部是占位符）：

```properties
storeFile=/absolute/private/path/release.p12
storePassword=YOUR_PRIVATE_PASSWORD
keyAlias=g-collie-release
keyPassword=YOUR_PRIVATE_PASSWORD
```

密钥与配置所在目录权限设为 `0700`，文件权限设为 `0600`；不要将其放进仓库、CI 日志、问题附件或发行包。备份至加密离线介质，密码分开保管；同一磁盘上的副本不能代替离线备份。维护者可用 JDK `keytool` 创建自己的 PKCS12 RSA 签名密钥，Fork 不使用本项目发布密钥。

```bash
export GCOLLIE_ANDROID_SIGNING_PROPERTIES=/absolute/private/path/signing.properties
npm run package:flutter-apk
```

脚本先执行 `flutter analyze`、`flutter test`，然后输出当前 pubspec 版本的：

- `releases/g-collie-<版本>-android-arm64-release.apk`：arm64 手机公开安装包。
- `releases/g-collie-<版本>-android-x86_64-release.apk`：x86_64 模拟器兼容验证包，不代表所有 x86 实机已验证。
- 每个 APK 对应的 `.sha256` 校验文件。
- `releases/g-collie-<版本>-android-signatures.json`：包名、版本号、ABI、SHA256 和生产证书指纹。脚本会验证 APK 签名并拒绝 debug 证书。

发布前使用 SDK Build Tools 的 `apksigner verify --verbose --print-certs <APK>` 核验证书指纹，用 `sha256sum -c <APK>.sha256` 核对文件。后续版本必须使用同一生产密钥，并提高 `pubspec.yaml` 的 build number。debug 构建仍使用本地开发密钥，与生产包隔离。

### 已有内测安装的升级限制

截至 0.1.40 的内测包使用 debug 证书。生产证书不同，Android 会拒绝同包覆盖安装（`INSTALL_FAILED_UPDATE_INCOMPATIBLE`），这不是安装包损坏。不能承诺内测包无损升级到生产签名，不能通过签名配置规避系统校验。

不要自动卸载、清除内测应用或改变现有配对。已有内测用户可先保留现状，待自行决定迁移后再手动卸载内测包、安装公开版并重新配对；这会丢失本机配对、设置、草稿和内置网络登录状态。电脑上的 Agent 会话不因手机卸载删除。首次生产签名安装完成后，后续同签名 APK 可正常覆盖升级。

## 连接

电脑照常运行 G-Collie 服务，在“手机与配对”生成配对码。在 Flutter 客户端填写完整电脑地址、六位码和设备名称；也可以粘贴含 `#pair=` 的配对链接。客户端只保存此电脑发放的设备 Cookie，使用系统安全存储，不需要模型 API Key 或电脑管理密钥。

局域网可填写已开放监听的电脑局域网地址。远程可使用系统 Tailscale VPN，或从顶部“内置网络”在 App 内官方授权窗口完成本应用的独立入网。内置网络会列出在线 G-Collie 电脑；选择电脑的 G-Collie 私网服务地址（不是只监听回环的系统 Tailscale IP）。电脑服务从源码运行时也会查找已安装的网络程序。

冷启动会等待登录状态恢复，并对只读健康检测失败自动重试；发送消息不会自动重发。通过 USB 本机地址进入时，若能访问同一电脑的私网入口，会核对设备身份后保存远程地址与现有配对。顶部明确区分 USB 调试和私有网络连接。Android 模拟器访问电脑可使用 `http://10.0.2.2:4310`。

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

入网与 G-Collie 设备配对是独立操作，debug 内测包与生产签名之间的迁移限制见上文。已验证无 ADB 端口转发的私网访问、冷启动恢复、真实 Codex / Hermes 收发及执行中追加消息。超长后台存活尚未完成专项验收。详细历次验证记录见 [VALIDATION.md](VALIDATION.md)。

0.1.4：点击新建直接选择助手/项目，进入空白聊天，首次发送才创建会话；名称根据首条消息生成。输入或附件非空时显示发送箭头，执行中也能发送；执行中输入为空时显示停止。Codex 使用桌面 steer，Hermes 沿用后端忙碌输入配置。历史问题回答只显示人类回答，不显示内部回复标签与 JSON。
## 会话图片与文件预览（0.1.1）

会话中的结构化图片会保留并显示；本机 Markdown 图片链接通过已配对服务读取。点击图片进入 Flutter 缩放查看页；PDF、Word（DOCX）、Markdown、TXT 在 App 内打开文档阅读页，不跳转系统浏览器。PDF 支持翻页，Word 支持正文与表格阅读，复杂排版以原文件为准。原文件可通过右上角下载至系统下载目录；旧 DOC 等其他格式可下载后用对应应用打开。

电脑服务只提供会话明确引用的允许类型文件，拒绝敏感配置路径；文档使用 20 分钟有效且绑定设备授权的只读票据，撤销设备授权后失效。文件移动、删除、超过限制或预览链接过期时需要返回会话重新点击。HTML 文档预览通过 App 内 WebView 呈现，聊天主界面仍为 Flutter。

开发部署：当前用户服务通过 `~/.config/systemd/user/g-collie.service.d/90-flutter-preview.conf` 使用项目 `.packaging/preview-server.mjs` 和项目脚本；原系统安装文件保留。重新打包服务端需包含 PDF.js legacy assets（Deb 打包脚本已适配）。

0.1.3：Codex / Hermes 的工具调用与结果合并为紧凑摘要，可展开查看命令和实际输出；呈现可靠的状态、耗时及可用的公开思考摘要。缺少结果或摘要时不补造内容。

0.1.5：新会话的助手和项目均使用紧凑卡片，三个助手同行排列。两项选择后统一确认进入聊天；同尺寸“＋ 新建项目”卡片内提供电脑文件夹选择和新建。项目列表及新会话项目关联持久保存。

照片、视频、文件的附件菜单在三个助手中保持一致。视频上限 100 MB，以流上传；模型接收最多 6 张均匀抽样画面，当前不分析音频。模型需要具备图片理解能力。服务端需安装 FFmpeg，可设置 `GCOLLIE_FFMPEG` 为可执行文件绝对路径；本地 Linux x86_64 开发环境也可运行 `python3 scripts/setup-ffmpeg.py` 获取校验后的固定版本依赖。此本地依赖不会自动包含在 Debian 安装包中。

0.1.7–0.1.9：用量页新增 Codex 重置卡入口，消费前确认账号，超时重试保留操作编号，成功后刷新额度；新增 Claude Code 本机主会话与子代理用量汇总。三个助手以一行三个等宽卡片排列，图标在上、名称在下，选中时显示边框和底色。

配对成功后安全保存设备凭证，当前有效期为 90 天；有效期内重启或覆盖升级无需重新输入配对码。凭证过期、被撤销或 App 数据被清除后需要重新配对；内置网络登录与设备配对彼此独立。
