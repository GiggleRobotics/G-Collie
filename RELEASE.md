# G-Collie 0.3.35 / Android 0.1.51

发布日期：2026-11-17。电脑服务／网页版本0.3.35；Android版本0.1.51，arm64构建号2058、x86_64构建号4058。

[GitHub Release 与下载](https://github.com/GiggleRobotics/G-Collie/releases/tag/v0.3.35) · [完整验证记录](docs/开发/06-版本发布记录.md) · [能力矩阵](docs/能力矩阵.md)

## 本版变化

- 修复手机会话详情瞬断后的只读重试、历史稳定ID归并和未知发送结果防重放。
- Codex工具“已查看图像”进入原工具记录，默认折叠，点击标题展开／收起，图片靠左；内部子Agent不再误入普通会话列表。
- Markdown授权相对图片默认加载；文件缺失、无权限或加载失败仅显示图片图标和图片名称。
- 配对地址和验证码框支持粘贴完整邀请链接，不自动提交。
- 纯终端Codex使用原生app-server／安全现存daemon；修复旧数据库兼容、派生JPEG条纹、内置网络子进程代理继承和Hermes未知结果误判。
- 真实Hermes旧sidecar支持浮点秒轮次标识；新版gateway按已核验的实例、profile及authority幂等附着已运行会话。缺失runtime拒绝冷接管；审批要求完整回放和当前代际。

## 本轮验证

- 服务端178项、Flutter162项、类型检查、Flutter静态分析、Web构建和Go核心race回归通过。
- SG实际Codex CLI0.169：13项原生／独立daemon桥控制测试通过，仅使用临时CODEX_HOME及回环模型。旧409已确认为发送前状态同步保护，没有重放用户正文。
- 真实Hermes旧sidecar及JDCLOUD原生gateway分别使用专用profile与回环模型验证发送、幂等、当前轮停止；原生authority附着、完整事件回放及冷恢复拒绝已实测。
- Xiaomi真机原App同签升级0.1.51/2058，原数据保留。工具图片收展及Markdown正常／缺图通过；后台520秒期间Wi-Fi→蜂窝后自动追平两条稳定ID测试消息，重复刷新与反向切网无重复。测试电脑已解除，原三台配对保留，网络设置恢复。
- DEB独立HOME包内烟测及源码／许可／SHA校验，双ABI APK生产签名、非debug、16KiB对齐均单列核验。具体最终SHA见随包SHA256SUMS-first-release和逐文件.sha256。

## 下载与升级

- Linux amd64：`g-collie_0.3.35_amd64.deb`。
- Android新用户：`g-collie-0.1.51-android-arm64-release.apk`；x86_64包用于对应设备及模拟器。
- 旧内测手机：`g-collie-flutter-0.1.51-arm64-beta.apk`，仅供相同旧证书覆盖升级。它与生产arm64包82个非签名ZIP条目逐项一致；真机运行验证使用此包，不冒称生产证书已在该手机全新安装。
- Android生产证书SHA256：`6286e58588a3b92e786f4511bb84cb59e954b527e2bf2c1f3e11c5b2e80cc08b`。不同证书不能直接覆盖，不自动卸载、清数据或承诺跨签无损迁移。
- 同次提供源码包、每个产物.sha256、生产签名元数据及校验清单。DEB提供SHA256，现有流程未配置独立DEB密码学签名。

```bash
sha256sum -c g-collie_0.3.35_amd64.deb.sha256
sudo apt install ./g-collie_0.3.35_amd64.deb
g-collie
```

升级前保留旧包及本人数据备份；安装后核对版本、配对和原会话。个人数据位于`~/.local/share/g-collie`，卸载程序默认保留。备份含配对凭据和网络身份，应私密保管；`g-collie backup`会短暂停G-Collie服务，须避开依赖它的任务。

## 能力边界

Codex终端计划模式、Codex／Claude安全删除仍未适配；Claude需本人登录。Hermes停止只针对当前轮，不承诺清空排队消息；不支持安全原子冷恢复的环境明确拒绝接管。实验协议能力取决于原生版本和会话状态，不等同所有助手共享相同能力。

本轮真实传输测试使用合成消息，真实CLI／Hermes控制使用本地模型；没有宣称生产账号额度、全部外部模型、全天候锁屏、所有网络／VPN、主机重启自启或所有Android机型均已验证。历史系统兼容证据及未覆盖环境继续见开发记录。未知请求或结果不自动重放。

项目代码GPL-3.0-only，第三方条款见LICENSE／NOTICE／THIRD_PARTY_NOTICES.md。FFmpeg对应完整源码与构建脚本随DEB位于`/usr/share/doc/g-collie/ffmpeg/`。原始私人截图、账号凭据和签名私钥不随发行提供。
