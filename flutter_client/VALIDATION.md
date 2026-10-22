# Flutter 移植验证 · 2026-10-20

本次只迁移技术实现；原 React 页面及旧 APK 未修改。Flutter 页面沿用现有品牌素材、Lucide SVG、首页、侧栏、聊天气泡、输入区、筛选及工作台设置的结构。

## 已通过

- Flutter 3.47.7 / Dart 3.13.5 静态分析，无问题。
- 8 项 HTTP 接口及 widget 测试：地址校验、原会话控制路由、只读/断线限制、Cookie 保存、401、会话收发、日历未知值与零值、问题回答刷新时的输入保持。
- Android ARM64 Release 内测包构建成功，APK v2 签名验证通过。
- 包内包含 Flutter AOT、Flutter 引擎、Dart JNI 及原有 `libgcollie_network.so`。
- Android 模拟器：配对、首页、打开会话、键盘避让、发送消息及收到模拟回复。测试仅访问本机模拟服务，没有向真实 Agent 发送消息。
- 模拟器原生平台通道可启动内置网络并读取 `NeedsLogin` 状态，JNI 库加载正常。

截图位于项目 `screenshots/flutter/`，内容均为模拟服务验收。

## 真机安装状态

已识别 Xiaomi 14（Android 16 / API 36），旧 G-Collie 未卸载或覆盖。

最初常规安装被系统取消，且 USB 传输反复掉线。改用 16 KiB 分块、每块间隔 5 ms 的降速传输后，55.7 MB APK 完整传入手机；手机与电脑 SHA-256 一致，`pm install -r` 返回 `Success`。

已通过无线 ADB（`10.42.0.144:43523`）继续验证：

- 正式电脑服务 `0.3.3` 配对、真实会话列表读取；强制停止再启动，配对保持。
- 打开正式 Codex 会话，显示真实历史、当前工具调用及“桌面正在执行”状态；没有向已有工作会话发送测试消息。
- 真机键盘输入 `Flutter-wireless-test`、点击发送、服务端收到消息，手机显示模拟回复。截图 `screenshots/flutter/phone-wireless-replied.png` 明确标注模拟服务。
- 最后已切回正式电脑服务，并打开真实会话。截图 `screenshots/flutter/phone-formal-session.png`。
- 本轮日志检查未见 Flutter 错误或进程崩溃。

当前正式连接通过无线 ADB 的 `reverse tcp:4310 tcp:4310`，依赖调试连接，并非独立私网连接。新建专用 Hermes 调试会话被电脑服务拒绝：`未唯一发现 Hermes 本机后端`；没有创建成功，也没有发送真实 Agent 测试消息。

真实 Agent 完整收发、私网登录、原生后台通知、真实附件与长会话性能仍需验收。原有 G-Collie 仍保留。

## 产物

- `releases/g-collie-flutter-0.1.0-arm64-beta.apk`
- `releases/g-collie-flutter-0.1.0-arm64-beta.apk.sha256`
- 复现：`npm run package:flutter-apk`

## 2026-10-23 USB 真机补充

USB 设备 `d7e798c8` 连接正常；已恢复 `reverse tcp:4310 tcp:4310`。手机当前安装版本为 `0.1.0`（2001）。电脑 Hermes 后端已恢复可用。

创建专用会话 `G-Collie Flutter USB 真机调试 1023`（`hermes:20261023_001454_a27084`），在手机输入并发送 `Reply only FLUTTER_USB_OK. Do not use tools or change files.`。正式服务记录与手机显示均确认收到真实助手回复 `FLUTTER_USB_OK`，会话返回空闲。截图 `screenshots/flutter/phone-usb-real-reply.png` 已人工查看。未向已有工作会话发送测试消息，未修改 UI 或应用代码。

已通过系统通知权限授权，原生前台通知服务启动成功。App 退到桌面后，在专用会话执行无工具的 30 行固定文本回复；服务端生成任务完成事件，Android 收到“本轮执行已结束”，点击通知正确打开对应 Hermes 会话（截图 `screenshots/flutter/phone-usb-notification-open.png`）。临时移除 ADB 转发后约 18 秒收到“电脑连接中断，任务状态未知；正在重试”，随后恢复转发。提醒保持开启。本轮日志检查未见 Flutter 错误或进程崩溃。此前临时 Flutter SDK 已不存在，本轮未重新运行 Flutter 单测或构建；安装包沿用此前验证版本。

## 2026-10-23 图片与文档预览修复（0.1.1 / 2003）

最终实现为 App 内预览，已撤掉文件点击后启动系统浏览器的行为。聊天 UI 与工具执行记录展示未改。

- Python 会话投影保留 Codex/Hermes 结构化图片；真实会话中用户新附的两张截图可被资源接口识别。
- 会话图片缩略图、Flutter 图片查看页已真机验证；查看页支持缩放。截图 `phone-resource-links.png`、`phone-inapp-image.png`。
- 真机从聊天链接进入 PDF、DOCX、Markdown 预览页，焦点始终为 `dev.giggle.g_collie_flutter/.MainActivity`。截图 `phone-inapp-pdf.png`、`phone-inapp-word.png`、`phone-inapp-markdown.png`。
- PDF 使用 PDF.js legacy 兼容资源；此前手机默认浏览器上的加载失败已修复，最终 App 内显示成功。
- DOCX 正文和表格预览成功；点击右上角下载后文件落到 `/sdcard/Download/1792688251462-preview.docx`，手机与电脑 SHA-256 一致。移动网络下载时可能出现系统流量确认，未更改全局流量限制。
- 新增服务端资源引用约束、敏感路径/符号链接拒绝、Markdown 清理、设备撤销验证；后台 37 项测试通过。最终 legacy 资源版本另通过资源测试和四类页面浏览器渲染检查。
- Flutter 静态分析无问题，10 项测试通过；ARM64 Release 构建、覆盖安装成功。版本 `0.1.1`，versionCode `2003`。
- 下载与预览通过 20 分钟、绑定已配对设备的只读票据；本地中转不会向页面发送设备 Cookie。只允许已发放的预览路径，拒绝跨站请求。

范围：Word DOCX 为阅读转换，复杂分页与排版以原文件为准；旧 DOC 等其他格式提供原文件下载。电脑文件需仍存在，当前正式连接仍依赖 USB ADB 转发。独立私网和超长后台存活未新增验收。

当前产物：`releases/g-collie-flutter-0.1.1-arm64-beta.apk` 及对应 SHA-256。服务端由当前用户 systemd drop-in 指向项目构建产物，系统原安装保留。

## Codex 会话补充验收

使用已有专用会话“开展手机控制测试”（`codex:01a14e4c-a713-7bf1-9637-3ef870354669`），未向其他工作会话发送验证消息。

- Codex 返回带图片、PDF、DOCX、Markdown 链接的回复；资源接口正确识别四项资源。
- 小米 14 点击 Codex 回复中的 PDF、Word、Markdown 链接，以及图片，均在 G-Collie 内打开。截图 `codex-inapp-pdf.png`、`codex-inapp-word.png`、`codex-inapp-markdown.png`、`codex-inapp-image.png`，均已查看。
- 从 Codex Word 预览页下载原文件，落盘 `1792688510005-preview.docx`，SHA-256 与电脑一致。
- 单独上传并发送真实原生图片附件（非 Markdown 图片链接），Codex 返回 `CODEX_IMAGE_OK`；手机显示真实附件，截图 `codex-native-image.png`。
- 发现原生图片附带的 `<image ...>` 标记重复显示，已在有结构化图片的消息中移除该重复标记；接口验证图片仍保留且正文干净。只更新读取投影脚本，无需重装手机包，执行记录展示不变。

## 0.1.2 预览与历史消息整理

用户已确认效果正常。新版 0.1.2（2004）已安装：预览页缩小标题字号、移除重复文件名和网页下载栏，统一纸张背景与底部翻页/缩放控件。Flutter 静态分析与 10 项测试通过，资源接口测试和四类预览页面检查通过。历史消息只在完整匹配已知附件包装格式时提取人类正文，图片保留，非图片文件保留可点击附件；4 项针对包装清理的 Python 测试通过。截图所对应历史会话的接口已确认包装文字为零，图片消息仍有两条。执行记录展示方式没有调整。

## 0.1.3 Codex / Hermes 过程记录对齐

已安装版本 0.1.3（2005）。工具调用与返回按调用 ID 关联，默认紧凑一行显示命令、状态和可用耗时；展开查看输入与输出。Codex 桌面原生命令事件补充命令、退出码和输出；异步执行与后续等待结果关联，避免重复状态行。进度说明采用紧凑正文；整轮处理时间放在用户消息之后。

只投影明确的公开思考摘要，不读取或导出 raw_content、encrypted_content 等内部字段；没有公开摘要时不生成思考内容。Hermes 使用 tool_calls/tool_call_id 关联，过滤隐藏/内部通知记录，工具输出的正文和退出码单独整理，不把原始 JSON 当正文显示。

验证：Flutter 静态分析无问题，原有 10 项测试及新增 2 项过程控件测试通过；Python 5 项过程配对/异步合并/公开摘要/缺失结果测试及原有 4 项消息清理测试通过。Hermes 实时执行 `printf GCOLLIE_PROCESS_OK`，紧凑摘要与展开输出已真机验证（hermes-process-compact.png / hermes-process-expanded.png）。Codex 当前真实会话的过程投影及手机紧凑记录已验证（codex-process-compact.png）。Codex 专用验收轮在开始工具前长时间未返回，已按对应 turnId 停止，未重复提交；当前正在执行的真实 Codex 会话用于过程展示对照。

产物 releases/g-collie-flutter-0.1.3-arm64-beta.apk，v2 签名及 SHA-256 已核对。当前仍使用 USB ADB 转发；此次没有改动文档预览和聊天主结构。
