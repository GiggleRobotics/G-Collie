# G-Collie 0.3.2 开发者内测

优先使用 Linux amd64 DEB 和 Android APK，二者均内置 Tailscale，无需手机另外安装 Tailscale 或配置 Serve。电脑端启动后地址为 `http://100.x.x.x:4310`。

安装 DEB 后运行 `g-collie`，启用内置远程连接并在浏览器授权；手机 APK 也需授权入网。手机可发现同网络的 G-Collie 电脑，或通过“在 G-Collie APK 中打开”自动带入配对链接。网络入网和 G-Collie 控制/只读配对分别授权。

此版本增加连接前的 G-Collie 服务检查、明确错误提示和网络进程自动恢复。Android 模拟器已验证收发和停止；实体手机及移动数据跨网仍待验收。完整步骤见 [内置远程连接](docs/内置远程连接.md)。

升级：`sudo dpkg -i g-collie_0.3.2_amd64.deb`，再运行 `g-collie restart`；手机安装同一签名新版 APK 可保留登录和配对。电脑数据在 `~/.local/share/g-collie`，升级前建议备份。用户服务在用户登录后自动启动，注销后持续运行依赖系统 lingering 设置。APK 现支持用户开启的原生任务提醒、断线提示和常驻同步状态，受 Android 后台时限及省电影响。维护命令新增 `g-collie doctor`、`g-collie backup`。

以下是源码安装及旧版系统 Tailscale 兼容方式：

## G-Collie 0.2.0 开发者内测

此版本面向单人自托管，尚非面向普通消费者的正式商用版本。

完整用户操作步骤见 [电脑端说明](docs/电脑端使用说明.md) 与 [手机端说明](docs/手机端使用说明.md)。

## 源码安装

需要 Linux、Node.js 22+、npm、Python 3，以及已正常登录的 Codex / Hermes 桌面 App。

解压源码包，在目录运行 `npm run setup`。首次在 Codex 提供的终端环境执行 `npm run service:install`，保存桌面本地接口初始化信息（不读取模型账户凭据）。停止旧前台服务后，执行 `npm run service:start`。用户登录后自动启动，崩溃自动恢复。`npm run service:status` 查看状态，`journalctl --user -u g-collie -n 50` 查看日志。注销后继续运行依赖系统的用户 lingering 设置，此安装器不修改系统级设置。

电脑浏览器打开 http://127.0.0.1:4310 ，选择“电脑首次设置”，输入 `.data/access-token` 中的本地管理密钥。不要把此密钥发送给手机。新安装若需 Codex 写操作，在“电脑与连接”显式启用实验性 Codex 控制；首次使用先以专用测试会话验证当前桌面版本。旧版浏览器会在电脑本地自动换取独立设备凭证。

## 手机

电脑和手机安装、登录自己的 Tailscale。在电脑执行：

```
tailscale serve --bg --https=8443 http://127.0.0.1:4310
```

若提示权限、HTTPS 授权或端口冲突，先按 Tailscale 正常流程处理，不要覆盖已有服务。G-Collie → 设置 → 电脑与连接 → 重新检测连接，可看到 HTTPS 入口。此向导只检测并给出命令，不自动修改 Tailscale、不使用 Funnel。

设置 → 手机与配对 → 选择 HTTPS 地址和控制/只读权限 → 生成短期二维码。手机扫码即可登记，也可手动打开地址输入六位码。十分钟有效，一次使用，连续五次错误后失效。凭证使用 HttpOnly / SameSite Cookie；HTTPS 入口使用 Secure Cookie。有效期 90 天。电脑管理端可撤销单台设备，后续 API 立即返回 401，事件连接在下一心跳关闭。

服务默认只监听本机回环。局域网试用可显式设置 `HOST=0.0.0.0`，务必使用配对；HTTP 不保护线路上的内容，不建议跨不可信网络。

## 手机安装与通知

支持 HTTPS 下的 PWA 安装。Android 浏览器菜单选择安装；iPhone Safari 添加到主屏幕。通知设置中手动开启并发送测试。推送通过浏览器厂商推送服务；有效订阅需要用户授权。推送不包含聊天正文或任务标题，只包含通用状态和跳转标识。

当前仅监控本次服务运行中打开过的会话（最多 30 个，Codex 仅监控仍保持实时订阅的最近会话），重启后需重新打开要关注的会话。尚未实现持久化关注列表与所有历史会话后台扫描。断网、系统省电、浏览器推送服务不可达会影响到达，不能承诺即时到达。

## 升级与数据

先停止服务，备份 `.data`，再更新代码、执行 `npm ci`、`npm run build`、重启。回滚需一起恢复旧代码和对应备份数据。不提供自动在线升级。`npm run service:uninstall` 只停用后台服务，保留数据。

`npm run release:pack` 生成不含 `.data`、密钥、日志和会话数据的源码包及 SHA-256。运行依赖从 npm 按锁文件安装。DEB 暂无发布者签名；Android APK 使用本机持久化内测签名。目前系统安装包提供 Linux amd64 DEB 和 Android APK，Windows/macOS 暂无安装包。

## 兼容边界

Codex 桌面控制、新建与加载仍依赖当前桌面版本的内部 IPC，更新后可能需要适配。第一次初始化仍需要 Codex 环境提供的本地接口信息；后台服务后续可独立运行，不需要这条聊天保持执行。自动发现仅探测当前用户拥有、权限私有的本地 app-tools socket，不提取登录密钥。

Hermes 仅支持本机唯一可识别的桌面后端；不支持多 profile 自动选择。Hermes 停止接口缺少原子 expected-turn 参数，仍有已记录的轮次竞态限制。

不含自建公网中继、微信身份登录、多租户、计费、文件附件、完整跨平台安装器。第三方 Agent 标志保留原来源说明；商用品牌与分发权限需要另行确认。发布前仍需独立安全审查、更多桌面版本与真实手机/移动网络回归。

## 安装包（Linux / Android 内测）

- Linux amd64：`g-collie_0.2.0_amd64.deb`，内含 Node 22 运行时、网页和服务端，不需要安装 npm。依赖系统 Python 3、systemd 和 xdg-utils。安装后从应用菜单打开 G-Collie，或执行 `g-collie`。后台服务属于当前登录用户。
- Android 8+：`g-collie-0.2.0-android.apk`，开发者内测签名。安装后填入电脑访问地址，再用电脑生成的六位码配对。客户端复用网页界面，支持切换电脑、刷新、返回和持久化登录；此版不含原生后台推送、原生扫码或 Tailscale VPN。网页推送仍需兼容浏览器/PWA，不能视为 APK 后台通知已完成。
- APK 不内置私人电脑地址、配对密钥或账号。Android 系统 WebView 负责网页渲染；不忽略证书错误，不开放 JavaScript 原生桥接。
- 私人数据存放在 `~/.local/share/g-collie`，不会写入安装包。旧开发目录迁移命令：`g-collie migrate /原项目/.data`（目标必须为空）。迁移后原有配对继续有效。
- 卸载前执行 `g-collie uninstall-service`，再卸载 deb。私人数据保留，需删除时由用户自行处理。
- APK 签名密钥仅存放在本机 `~/.local/share/g-collie-signing`，不随安装包分发；后续升级须沿用此密钥。
- 构建：`npm run package:deb` 和 `npm run package:apk`。Android 构建脚本可通过 `GCOLLIE_JAVA`、`GCOLLIE_ANDROID_BUILD_TOOLS`、`GCOLLIE_ANDROID_PLATFORM` 指定工具位置。
