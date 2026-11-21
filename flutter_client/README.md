# G-Collie for Android

Android 客户端使用 Flutter 实现。它连接用户自托管的 G-Collie 电脑服务，读取原有 Agent 会话并提交获准的操作。应用 ID 为 `dev.giggle.g_collie_flutter`。下载已发布 APK 和配对步骤见 [手机使用手册](../docs/手机端使用说明.md) 与 [发行说明](../RELEASE.md)。

## 运行

开发使用 Flutter stable、JDK 17 和 Android SDK。本项目已使用 Flutter 3.47.7、Dart 3.13.5、Android Build Tools 36、NDK 28.2.13676358 和 CMake 3.22.1 构建。最低 Android 版本为 8.0（API 26）。公开构建提供 arm64 与 x86_64。

从仓库根目录进入客户端，先进行组件测试：

```bash
cd flutter_client
flutter pub get
flutter analyze
flutter test
```

首次构建包含内置私网的 App 时，在仓库根目录准备 Go 与 NDK 并运行 `npm run build:network`，生成 `android/lib/arm64-v8a/` 和 `android/lib/x86_64/` 下的网络库。随后在 `flutter_client/` 运行 `flutter run`，或用 `flutter build apk --debug --target-platform android-arm64` 生成开发 APK。[工具链与服务端开发](../CONTRIBUTING.md)

## 与电脑联调

电脑端先启动服务，手机通过可达的完整地址和独立配对码连接。数据库和真实模型执行保留在电脑上。调试 USB 转发、系统图片选择器、文件下载或进程恢复时，请记录真机与应用版本。[测试指南](../TESTING.md) · [远程连接](../docs/内置远程连接.md)

| 目录 | 内容 |
| --- | --- |
| `lib/` | 工作台、连接管理、会话页面、回执、媒体和文件预览 |
| `android/` | Android 工程、系统文件和网络等原生接口 |
| `assets/` | 随包图像、图标和声明 |
| `test/` | 状态、组件与异常流程回归 |

## 正式签名与打包

从仓库根目录运行打包脚本。通过 `GCOLLIE_ANDROID_SIGNING_PROPERTIES` 提供仓库外的私密签名配置。Release 构建会检查签名配置是否完整。

```properties
storeFile=/absolute/private/path/release.p12
storePassword=YOUR_PRIVATE_PASSWORD
keyAlias=g-collie-release
keyPassword=YOUR_PRIVATE_PASSWORD
```

```bash
export GCOLLIE_ANDROID_SIGNING_PROPERTIES=/absolute/private/path/signing.properties
npm run package:flutter-apk
```

脚本运行静态分析、测试和分 ABI 构建，产物位于仓库根目录的 `releases/`，包括 APK、逐文件 SHA256 和签名元数据。正式版本沿用发布签名并递增 build number。私钥和配置存放在仅维护者可访问的目录，备份请加密。

### 已有内测安装的升级限制

Android 覆盖安装需要相同应用 ID、匹配的签名和兼容的版本号。已安装旧内测版的用户请选择对应的同签覆盖包；新安装使用生产签名包。卸载或清除本机数据会移除手机上的配对、设置、草稿及私网登录。公开证书指纹与升级说明见 [Android 签名与升级](../RELEASE.md#android-签名与升级)。
