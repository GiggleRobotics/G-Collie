# 测试指南

服务端、网页和 Flutter 客户端分别有自动回归。模拟接口适合精确检查提交次数、请求编号和异常回执，实体设备用于检查安装升级、系统选择器、网络和交互。安装包的历史验证范围见 [发行说明](RELEASE.md) 和 [验证记录](docs/开发/06-版本发布记录.md)。

## 基础检查

从仓库根目录执行，使用 Node.js 22、npm、Python 3 和 FFmpeg。Linux x86_64 可先运行 `python3 scripts/setup-ffmpeg.py` 安装开发测试用的 FFmpeg。它会校验下载文件的散列，并将可执行文件放到 `.tools/ffmpeg/ffmpeg`。

```bash
npm ci
npm run typecheck
npm test
npm run build
```

测试输出会列出通过、失败和跳过的项目。涉及发行版解码能力的部分用例会查找 `.tools/ffmpeg-release/ffmpeg`。准备对应二进制后再核对这些用例。

手机端的最低 Flutter 版本见 [pubspec.yaml](flutter_client/pubspec.yaml)。以下命令从仓库根目录开始。

```bash
cd flutter_client
flutter pub get
flutter analyze
flutter test
```

## 按改动运行专项

| 改动 | 专项命令 |
| --- | --- |
| 请求身份、首发重试与回执 | `node --import tsx --test server/session-create.test.ts server/desktop-create.test.ts` |
| 会话图片、上传附件与预览 | `node --import tsx --test server/resources.test.ts server/attachments.test.ts` |
| Codex 历史和 Hermes 消息投影 | `python3 scripts/test-codex-context-projection.py` 和 `python3 scripts/test-hermes-projection.py` |
| 手机切换会话、等待确认、重复提交 | 在 `flutter_client/` 执行 `flutter test test/pending_messages_test.dart test/chat_submission_regression_test.dart` |
| 手机工具图片与聊天画廊 | 在 `flutter_client/` 执行 `flutter test test/remote_gallery_test.dart test/session_media_test.dart` |

## 接口与浏览器

`node scripts/test-codex-headless-http.mjs` 启动临时目录中的服务和模拟 Codex 后端，覆盖首发、无效图片、按原编号查询与重试等 HTTP 行为。无效图片用例需要本机提供 FFmpeg。另可用 `node scripts/test-isolated-http.mjs` 检查设备配对、撤销、同一会话资源读取及跨会话拒绝。两个脚本自行启动测试服务，分别使用回环端口 18543 和 18542。

浏览器用例可对生产构建运行。在一个终端启动静态文件预览。

```bash
npm run build
python3 -m http.server 4397 --bind 127.0.0.1 --directory dist
```

在另一个终端安装 Playwright 对应的 Chromium，再运行专项。下列用例拦截 API，使用合成会话数据。

```bash
npx playwright install chromium
export GCOLLIE_UI_TEST_URL=http://127.0.0.1:4397
node scripts/test-web-create-receipts.mjs
node scripts/test-web-aux-navigation.mjs
node scripts/test-web-session-management.mjs
node scripts/test-web-media.mjs
```

## 真机回归

1. 记录设备 Android 版本、APK 版本号和电脑端版本。覆盖安装前核对包名、签名和版本号，保留原配对。
2. 使用测试电脑连接和专用会话。首发时分别模拟延迟、明确拒绝和成功。等待期间检查正文和附件，再核对成功后的目标会话及实际提交次数。
3. 对明确不可读取的图片，移除或更换附件后手动重试。遇到普通失败，检查草稿是否可编辑。切换会话后到达的回执应归属原会话。
4. 在真实浏览器的窄屏视口，从侧栏进入辅助页，再回首页或另一条会话。同步记录截图、复现步骤和未测场景，移除临时测试连接。

USB 联调使用运行 API 的测试服务。例如服务监听在 4321 时，用 `adb reverse tcp:4321 tcp:4321` 转发到电脑，在 App 填入 `http://127.0.0.1:4321`。完成后用 `adb reverse --remove tcp:4321` 清理该转发。跨网和长后台请按真实网络另行验证。原始设备日志与含私人数据的截图只留在本地。
