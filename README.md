# G-Collie · Agent 会话控制台

**帮你照看每一个Agent**

离开电脑后，你仍然可以用手机或另一台电脑的浏览器，查看 Codex、Hermes 或 Claude Code 的工作进度。通过 G-Collie，你可以打开原来的对话，在支持续聊的会话里补充要求，也可以选一个项目开始新任务。无论从哪台设备操作，助手都在原来的 Linux 电脑上运行，使用那里的项目和文件。

[看功能演示](https://gigglerobotics.github.io/G-Collie/#demo) · [下载 Linux 电脑端](https://github.com/GiggleRobotics/G-Collie/releases/download/v0.3.36/g-collie_0.3.36_amd64.deb) · [下载 Android 手机端](https://github.com/GiggleRobotics/G-Collie/releases/download/v0.3.36/g-collie-0.1.52-android-arm64-release.apk)

<picture>
  <source media="(prefers-reduced-motion: reduce)" srcset="docs/使用示例/g-collie-cover.jpg">
  <img src="docs/使用示例/g-collie-demo.gif" alt="G-Collie 演示：左侧电脑执行，右侧手机同步进度并追加要求；在手机工作台选择助手和项目，新建会话。">
</picture>

## 你可以怎么用

- **出门后，接着电脑上的工作。** 比如 Codex 正在跑测试，你可以在手机上看到哪一项失败了，打开它发来的截图，再在支持续聊的对话里说「帮我查一下原因」。之前的消息都在。
- **手边只有手机，也能开工。** 在手机上选一个助手和电脑上的项目，发一句「看看这个项目今天改了什么」。电脑上的助手开始处理，回复出现在手机里。
- **换一台电脑，继续同一件事。** 在笔记本浏览器里连接运行助手的电脑，打开原对话，看结果或继续交代任务。笔记本上无需重新安装助手、复制项目。

三个助手都能查看历史。Codex 和 Hermes 能否继续已有对话，取决于电脑上的助手接口；Claude Code 从外部终端创建的对话可回看，从 G-Collie 创建的对话可继续操作。[查看各助手支持的操作](docs/能力矩阵.md)

## 安装与首次连接

先在**运行助手的 Linux 电脑**上安装电脑端，用平时登录助手的账号运行 `g-collie`，并保持电脑开机联网。接下来按手边的设备选择教程：

| 手边的设备 | 怎么连 |
| --- | --- |
| Android 手机 | 安装 G-Collie App，让手机和电脑加入同一私网。在 App 里输入电脑给出的地址和六位配对码。[看手机配对演示（30 秒）](https://gigglerobotics.github.io/G-Collie/start/#phone-demo) |
| 另一台电脑 | 连到能访问执行电脑的网络，用浏览器打开它的完整地址，填写设备名称和六位配对码。[看浏览器配对演示（20 秒）](https://gigglerobotics.github.io/G-Collie/start/#browser-demo) |

当前下载为 Linux amd64 **0.3.36** 和 Android arm64 **0.1.52**。Android x86_64 安装包、旧内测签名升级包及校验文件见[发行页](https://github.com/GiggleRobotics/G-Collie/releases/tag/v0.3.36)。

## 使用与开发

- **安装、使用或排查连接问题**：[电脑端手册](docs/电脑端使用说明.md) · [手机端手册](docs/手机端使用说明.md) · [网络排错](docs/内置远程连接.md)
- **从源码运行或贡献代码**：[贡献指南](CONTRIBUTING.md) · [测试说明](TESTING.md) · [Android 构建](flutter_client/README.md)
- **查看版本变化或反馈问题**：[更新日志](docs/更新日志.md) · [提交 Issue](https://github.com/GiggleRobotics/G-Collie/issues)

项目自有代码按 GPL-3.0-only 分发。[许可证](LICENSE) · [项目声明](NOTICE) · [第三方许可](THIRD_PARTY_NOTICES.md)
