# 本机验证记录

日期：2026-10-18（Asia/Shanghai）。只在指定测试会话执行真实模型调用。未修改其他工作会话的内容。

## 自动检查

- `npm run typecheck`、`npm run build` 通过。
- `npm test`：15 项，无模型调用。覆盖状态与流式去重、重启后未知结果不重放、增量版本投影与原型污染防护、审批绑定 / 过期处理 / 授权选项约束、问题响应格式、Hermes 过期停止拒绝。
- `scripts/chat-smoke.mjs`：移动抽屉、搜索、详情、项目、信息菜单、桌面布局，无浏览器运行错误。
- `scripts/approval-ui-test.mjs`：手机审批 / 问题卡片提交原请求 ID、正确选项与回答，处理后清除。使用浏览器级响应 fixture，不冒充真实模型调用。
- 实际生产服务检查：`.data/access-token`、操作 ledger、环境文件、`/@fs/.../.data` 和服务端源码路径均不可匿名读取。

## Codex 原桌面会话

测试聊天：开展手机控制测试，ID `01a14e4c-a713-7bf1-9637-3ef870354669`。

| 功能 | 结果 |
| --- | --- |
| 拥有者发现、快照、增量、执行状态、Token | 真实桌面原会话已验证 |
| 发送与回复 | 已核对该会话原始日志中的用户消息和真实回复 |
| 手机发送 / 停止按钮 | 已真实验证，停止携带 expectedTurnId |
| 重复提交 | 相同 requestId 只生成一条原生用户消息 |
| 过期停止 / 无认证控制 / 错误适配器路由 | 拒绝且不影响目标聊天 |
| 断网 / 恢复 | 输入禁用、状态未知；恢复后连接同一原会话 |
| 命令审批 | 真实 printf 测试命令触发原生审批，批准一次后继续并完成 |
| 结构化问题 | 原生 request_user_input 提问、回答、请求清除已验证 |
| 文件审批 | 响应映射与授权选项约束单元测试通过，未实际创建文件变更审批 |

脚本：`desktop-control-test.ts`、`desktop-stop-test.ts`、`desktop-enabled-ui.mjs`、`desktop-regression.mjs`、`codex-question-test.ts`、`codex-approval-test.ts`。相关真实用量测试仅按需运行。

## Hermes 桌面后端会话

测试聊天：G-Collie · Hermes 手机控制测试，持久 ID `20261018_173023_e8c0ea`。

- 发现并连接当前实际 `hermes serve` 回环后端，附着现有运行时，不创建第二个后端进程。
- 测试会话首次创建后在原生 state.db 具有相同持久 ID、标题、用户消息及真实回复。
- 真实发送、停止和原工作运行时仍保留已验证（`hermes-control-test.ts`）。
- 手机网页发送按钮、回复显示、停止按钮、移动布局已真实验证（`hermes-ui-test.ts`）。
- 原生 clarify 提问、回答、请求清除已真实验证（`hermes-question-test.ts`）。
- 审批协议、一次批准 / 拒绝选项与过期请求单元测试通过；尚未触发真实危险命令审批，不列为完整原生实测。
- 生产连接只附着已加载会话；测试脚本曾明确恢复这个测试聊天用于测试，不对任意历史聊天自动冷启动。

## 仍有边界

- Codex 内部 IPC 随桌面版本变化可能需要适配。
- Hermes 普通 interrupt 没有服务端原子 expected-turn 参数；目前客户端在发送前核对当前启动时间，极小的跨客户端轮次切换竞争仍不能完全消除。
- 复杂权限审批、MCP 验证、多选问题等未支持的请求提示到电脑端处理。
- 未重启用户的桌面 App 做破坏性恢复验证，也未验证多 Hermes profile / 远程 Hermes URL。
- 实机通过 ADB 打开与截图；系统禁止 ADB 输入注入，自动点击使用手机尺寸 Chromium。
- 后台推送、费用账单、长期运行稳定性、跨版本兼容性尚未完成。

## Codex 手机新建（2026-10-18）

- `node scripts/desktop-create-ui.mjs`：真实手机尺寸页面选择 Codex 和 Giggle 项目，填写名称、首条消息；桌面原生接口创建并返回同一会话 ID，首条回复同步，桌面 owner 已连接。
- `node scripts/desktop-created-control.mjs`：对上述测试会话发送第二轮，实际点击停止；验证同一新建 requestId 不重复创建、未配对请求返回 401。
- `node scripts/desktop-create-projectless.mjs`：真实无项目创建、首条回复、projectPath 为 null，进入最近会话。设置 `ORBIT_TEST_REQUEST_ID` 可复用已提交的测试操作。
- 单元测试覆盖本地项目白名单、无项目 target、成功幂等和结果未知不重放。当前 18 项通过。
- 原生桌面列表已确认项目测试会话存在，ID `01a14f05-59a0-7802-861d-aae38064ee01`。无项目测试 ID `01a14f06-0fde-7cb3-80b7-2f939fafc5a8`。

## 会话分享

`node scripts/share-ui-test.mjs`：对独立 Codex/Hermes 测试会话执行手机下拉菜单分享、生成只读链接、匿名读取、重新打开面板恢复链接、撤销后 404，以及管理接口未配对 401。`server/shares.test.ts` 覆盖 HTML 转义、投影字段、过期、持久化和撤销。全部 19 项单元测试通过。

Codex 原生分享由桌面工具单独实测成功；G-Collie pipe 调用失败，当前 UI 统一使用明确标注的 G-Collie 局域网快照。

## 历史会话自动加载

- `node scripts/history-activation-ui.mjs`：真实 Codex、Hermes 测试会话初始均未连接；手机打开后自动触发一次恢复，输入启用，实时控制标记成立，后续轮询没有重复恢复。
- `node scripts/history-activation-states.mjs`：界面协议夹具验证归档不触发恢复、失败原因不会被轮询覆盖、手动重试后可输入。
- `node scripts/history-hermes-send.mjs` / `node scripts/history-codex-send.mjs`：对已恢复的原测试会话发送最小指令并验证实际回复，不调用工具、不修改文件。
- `server/activation.test.ts`：并发合并、失败后可重试、归档拦截、复用 Hermes runtime 和处理续接 ID。当前 21 项单元测试通过。

## 0.2.0 产品化基础

- `npm test`：26 项通过，新增短期配对/一次性消费/五次猜错/超时、设备凭证哈希/持久化/撤销、管理权限边界、同源和回环引导约束、推送服务地址限制、通知状态转换。
- `node scripts/product-auth-test.mjs`：真实服务端执行管理密钥迁移、六位码及二维码秘密码配对、独立 Cookie、控制/只读/管理权限、配对码重用拒绝、撤销立即 401、跨站拒绝、推送 SSRF 地址拒绝和健康检查。
- 已安装并启动 Linux systemd 用户后台服务，服务重启后健康检查正常。清除 `CODEX_THREAD_ID` / `CODEX_APP_TOOLS_PIPE_PATH` 的独立进程使用本机持久化初始化信息成功读取 7 个桌面项目（无模型推理）。
- 浏览器验证设置中独立凭证迁移、管理端设备列表、只读二维码实际生成。PWA manifest、192/512 图标与 service worker 构建正常，不缓存 API 数据。
- 源码发布包使用显式文件列表，检查不包含 `.data`、设备/推送密钥、桌面运行信息和 node_modules，包含实际需要的 Python 读取器。
- Tailscale 本机客户端在线，但当前 tailnet 尚未启用 Serve；`tailscale serve` 返回账号授权链接，等待用户开启。尚未完成真实手机 HTTPS 安装和后台推送到达测试，不将其标为通过。

## 0.2.0 Linux DEB / Android APK

- `npm run typecheck` 与 26 项单元测试通过。
- DEB 包含独立 Node 22.22.1 amd64 运行时、服务端 bundle、网页和桌面菜单入口；提取后以独立数据目录在 4320 启动，健康检查、首页、配对状态接口均返回 200，真实本机会话索引读取成功（612 个会话）。
- Node 下载与官方 SHA256 校验匹配；Android Build Tools 35.0.0、Android 35 平台包与 Google SDK 仓库声明的 SHA1 校验匹配。
- APK 使用内测专用持久化签名，apksigner 验证 v2/v3 签名通过；Android 8+，不含原生后台推送。
- 检查 DEB 文件清单，不含 `.data`、设备凭据、会话副本或签名私钥。
- ADB `172.16.17.22:38891` 连接成功，4310 端口反向转发成功。安装返回 `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`，设备系统禁止 ADB 安装；APK 另已复制到手机 Download/G-Collie-0.2.0.apk。实机安装及界面测试尚需设备允许安装后继续。
- DEB 系统安装已通过 pkexec 请求，等待系统身份验证。不能将包提取运行测试等同于已完成系统安装。

### 2026-10-19 安装进度

- DEB 系统安装成功（dpkg 状态 install ok installed）。
- 使用 `g-collie migrate` 将本机旧数据迁移到 `~/.local/share/g-collie`；重新安装用户服务后实际 ExecStart 为 `/usr/lib/g-collie/runtime/node /usr/lib/g-collie/server.mjs`，服务 active。
- 安装后的服务健康检查返回 200；实际服务的 product-auth-test 全部通过。诊断显示 Codex available=true、controlEnabled=true，运行时 Node 22.22.1。
- 手机重试 `adb install --no-incremental -r` 仍被 INSTALL_FAILED_USER_RESTRICTED 拒绝。系统还因缺少 INJECT_EVENTS 权限拒绝了滑动操作，已打开开发者选项，需手动开启“USB 安装”和“USB 调试（安全设置）”后继续实机安装及 UI 测试。

### 2026-10-19 内置网络模拟手机联通验证
- Android 模拟器内置 tsnet 状态 Running；电脑内置节点 Running。
- 发现手机误填 `http://100.84.91.5:4310`，实际隔离测试服务监听 `4321`；改为 `http://100.84.91.5:4321` 后成功加载配对页。
- `adb reverse --list` 为空，连接通过内置 tailnet 完成。
- 使用 owner 创建短期 control 配对码，在模拟器实际 UI 完成配对，成功显示 Codex/Hermes 会话列表与项目。
- 本次未发送或停止任何工作会话；不代表实体手机或所有会话控制已验证。

### 2026-10-19 内置网络控制回归
- 强制停止并重启 Android 应用后，无需重新登录或配对，成功恢复会话列表。
- 隔离 4321 服务的 Codex 控制设置原先关闭；通过 owner 接口启用后测试会话显示桌面实时连接。
- 实际模拟手机 UI：Hermes 专用测试会话发送短消息，收到 `G-Collie embedded network test OK.`。
- 实际模拟手机 UI：Codex 无项目新建验证会话发送短消息，收到 `G-Collie Codex tailnet OK.`；该测试消息只出现一次。
- 实际模拟手机 UI：Codex 专用测试会话发送长回复请求后点击停止当前轮，实时状态恢复 idle。未操作当前工作会话。
- 实体手机、后台通知与跨外网不同运营商连接仍未验证。

### 2026-10-19 0.3.2 产品能力验收

- Linux DEB 0.3.2 已系统安装，正式用户服务从 `/usr/lib/g-collie` 运行；临时验收 drop-in 已移除，正式端口 4310。
- 迁移前保留本机数据备份，仅迁移原内置网络身份；正式网络 Running，地址 `http://100.84.91.5:4310`。
- Android APK 0.3.2 已安装到 Android 15 x86_64 模拟器，同一签名升级保留网络身份。
- 自动发现电脑、默认 4310、APK 配对链接、错误端口明确提示均通过实际 UI 验证。
- 冷启动等待网络就绪；电脑网络进程意外退出后自动恢复，正式服务重启后关注列表恢复。
- TypeScript 类型检查通过；Node 30 项测试通过，包含网络进程重启、持久关注列表、提醒游标、首次载入/断线恢复不误报。Go core 测试通过，包含健康探测禁止重定向和错误服务识别。
- 模拟手机退到桌面后，真实 Codex 专用测试会话结束，原生通知栏收到“本轮执行已结束”；点击通知跳回对应会话。
- Android POST_NOTIFICATIONS 实际授权，dataSync 前台服务运行正常；常驻通知显示连接状态和关注数量。设备撤销后停止同步。
- 撤销此次模拟器专用控制设备后，手机显示“设备授权已失效”，后台提醒服务停止；已重新配对并恢复提醒。
- 新提醒 feed 集成权限检查：只读设备 GET 200，发送操作 403；撤销后 GET 401。临时权限测试设备已撤销。
- `g-collie doctor` 通过；本机备份实际创建并可读取，目录 0700、归档 0600，含网络身份和配对数据。不会把私有备份放进发布安装包。
- 实体手机原 ADB 地址 `172.16.17.22:38891` 返回 Connection refused，尚未进行本轮实体手机安装、移动数据跨网或 Android 后台时限长期验收。
- 最终断线测试：正式控制台服务停止约 43 秒后，模拟手机原生通知实际显示“电脑连接中断，任务状态未知；正在重试”；finally 已恢复正式服务，`g-collie doctor` 确认网络 Running。
- 最终发布 DEB 的 server.mjs、launcher.mjs、网络二进制及 dist/index.html 与系统安装文件 SHA-256 一致；安装包校验值记录在 releases/SHA256SUMS-0.3.2。
- 模拟器随后以 emulator-5560 重启（同一 GCollie AVD）。移除模拟器旧 HTTP 代理后恢复私有网络发现；最终 APK 增加“网络同步完成后继续待连接地址”的逻辑，实际冷启动恢复到会话首页，原生提醒前台服务也恢复运行，无需重新登录或配对。

### 2026-10-19 实体手机 USB 调试接入
- USB 识别 Xiaomi 14（houji / 23127PN0CC），Android 16。旧 ADB 服务未刷新设备，重启 ADB 后 USB 授权状态为 device。
- 0.3.2 APK 通过 USB 覆盖安装成功，应用启动与 ADB 点击均正常。
- 手机内置网络初始 NeedsLogin，登录按钮已打开手机系统浏览器。等待用户完成 Tailscale 账号入网授权后继续配对、收发和通知验收。
- 用户已完成实体手机 Tailscale 授权，手机内置网络成功访问正式 4310 配对页；一次性邀请被消费，服务已登记实体手机为 control 设备。未使用 ADB reverse 转发网络。
- 收发/停止/原生通知测试尚未完成：手机在 G-Collie 与其他应用之间持续切换，已请求用户提供连续约两分钟的前台测试窗口，避免自动点击误落到其他应用。

### 2026-10-19 小米 14（Android 16）真实交互验收完成
- 用户提供连续前台测试窗口后，通过 USB ADB 操作实体手机 G-Collie UI。
- 手机实际发送 Codex 专用测试消息，桌面同一测试会话回复 `G-Collie physical phone Codex OK.`。
- 手机 UI 发起长回复测试后点击停止，正式服务读取该 Codex 测试会话状态为 idle。
- 手机启用任务提醒，原生 TaskNotifications dataSync 前台服务实际运行。
- 手机返回系统桌面后，通知栏显示“已连接电脑 · 关注 1 个会话”和“本轮执行已结束”；点击该通知实际返回对应会话。
- 手机实际发送 Hermes 专用测试消息，收到 `G-Collie physical phone Hermes OK.`，并在实体手机 UI 验证回复可见。
- 全程只对专用测试会话发送/停止，未操作当前开发工作会话；无 ADB reverse 网络转发。
- 测试结束手机留在 G-Collie，原生任务提醒保持开启。移动数据跨网、锁屏长期驻留及系统后台时限尚未单独验收。

### 2026-10-19 移动数据与附件功能
- 实体手机 Wi-Fi 关闭、移动数据开启后，系统默认 transport 为 CELLULAR；重新连接出现超时，因此移动数据跨网测试未通过，仍待定位。原 Wi-Fi 开启、移动数据关闭的设置已恢复。
- 0.3.3 新增输入框“＋”菜单：照片、文件、附件预览及移除，单条最多 5 个、单文件 10 MB，附件保存在电脑 7 天。
- 附件绑定上传设备和目标会话，客户端只能提交附件 ID，不能传入本机任意路径；预览请求要求相同设备授权，文件读取无公开静态目录。
- Node 31 项测试通过，TypeScript 类型检查通过。新增测试覆盖附件绑定、路径注入、错误图片、重复 ID 及原生图片输入结构。
- 使用隔离验收服务 4333 发送真实 PNG 和文本附件到 Codex 专用测试会话，桌面 Agent 正确回复“红色；G_COLLIE_ATTACHMENT_FILE_OK”。
- Android 模拟器实际通过系统照片选择器选择测试图片、上传、显示缩略图及大小、从草稿移除。修复系统照片多选返回 ClipData 时默认 parseResult 返回空的问题，改为优先读取 ClipData / Data URI。
- 本次附件选择器 UI 测试使用 emulator ADB reverse 4333，仅为隔离界面验收，不作为 Tailscale 跨网验证证据。
- Hermes 附件暂使用本机文件引用；图片输入未验证，界面明确禁用该选项。
- 0.3.3 最终 DEB 与 APK 已分别覆盖安装到电脑、小米 14；正式服务版本 0.3.3。实体手机版本升级安装成功；附件选择、预览与移除的交互验收以 Android 模拟器为准。
- 上传期间和发送过程中禁用附件移除，防止并发上传把已移除的草稿重新加回；最终类型检查通过。
- 隔离附件验收服务与 emulator 的 ADB reverse 4333 已清理。手机网络确认恢复为 Wi-Fi 开启、移动数据关闭。

### 卡片式会话筛选（2026-10-19）

- 下拉筛选替换为助手、项目卡片，显示图标和会话数量，支持组合筛选和一键清除。
- TypeScript 检查与 DEB 构建通过，已安装到电脑服务。
- 在 390×844 浏览器视口验证 Codex + Giggle 组合筛选（5 个会话）、选中高亮、清除后恢复全部。
- 效果截图：`screenshots/session-filter-cards.png`。本次未重新验证真机网络连接。

### 筛选交互优化（2026-10-19）

- 根据用户录屏，将挤占历史列表的内嵌卡片改为独立筛选面板；手机底部弹出，桌面居中。项目完整换行，只有一个内容滚动区，底部确认按钮固定。
- 选择先保留为草稿，确认后应用并收起；关闭丢弃草稿；侧栏展示可再次打开的条件摘要与清除按钮。打开面板时移开搜索输入焦点。
- TypeScript 和 DEB 构建通过，已安装。浏览器 390×844 验证 Codex + Giggle（5 条）、确认后摘要、重置后取消仍保留原条件、清除恢复全部；390×560 验证确认按钮可见。未将缩短视口验证视为真机软键盘验证。
- 截图：`screenshots/session-filter-sheet.png`。

### 侧栏键盘焦点修复（2026-10-19）

- 打开侧栏时焦点移到关闭按钮，取消自动聚焦搜索框，避免触发软键盘。主动点击搜索仍可输入。
- TypeScript、DEB 构建通过，已安装。390×844 浏览器验证打开后 activeElement 为关闭按钮，点击搜索后为搜索输入框；本次未占用实体手机。截图：`screenshots/sidebar-no-search-focus.png`。

### 用量统计面板（2026-10-19）

- 改为账号总览/本机明细，支持日、月、项目、会话、模型；读取所有本地数据库会话，不再依赖最近 500 条列表或手动打开详情。
- Codex 官方 `account/usage/read` 及桌面 `get_usage_limits` 真读验证成功。每日数据截至 10/18，10/19 正确显示未返回；5 小时/周窗口显示真实百分比和重置时间，不由 Token 推算。
- Hermes 核对本地 CanonicalUsage：输入=普通输入+缓存读取+缓存写入，推理包含在输出。历史无逐次时间，基线另列，后台每分钟持久采样增量。
- 缺少日志的 Codex 数据库快照单独展示，不混入可解析 Token 总计或日/月，以免重复历史被算成新消耗。
- 正式 systemd 服务最初无法直连账号 API；仅为 Codex 子进程复用电脑现有代理配置后，正式 `/api/usage` 返回 200，账号累计/每日/额度均成功读取。配置私有且不向前端返回。
- 33 项原有及新增测试通过；后续加入代理白名单测试后，3 项统计测试再次通过（Python 内含 6 个语义/采样测试）。TypeScript 通过。
- 390×844 浏览器验证账号累计、日/月数据、额度、本机项目表和 Hermes 真实统计。未向任何会话发送测试消息。
- 说明书：`docs/用量统计.md`；截图：`screenshots/usage-codex-account.png`、`screenshots/usage-hermes.png`。

### 日历与人民币（2026-10-19）
- 日/周/月采用日历；未知日显示破折号，点选显示明细，月视图为月份卡片，周视图注明月内周小计。Android 模拟器实际显示验证，截图 screenshots/usage-calendar-emulator.png。
- 正式 API 校验会话/项目/日期合计一致，34 项测试通过；变更后统计专项与类型检查通过。
- Hermes 参考价采用 2026-10-19 官方人民币单价，空闲/高峰范围，未知模型单列，不作美元汇率转换或实扣账单。
- 运行文件更新到 ~/.local/lib/g-collie/0.3.3-calendar，用户服务沿用原私有数据，无管理员授权。模拟器本次使用 ADB reverse，仅验证界面。

### 合并日/周视图（2026-10-19）
- 删除周选项，日视图采用原周视图，保留按周分行和月内每行小计。月视图保留。TypeScript 与生产构建通过，用户目录运行资源已更新。

### 深色模式文字修复（2026-10-19）
- 修复侧栏黑色文字未随深色背景变化；明确图标、输入文字、提示文字及统计说明的前景色，增强额度进度对比。
- TypeScript、生产构建通过。Android 模拟器通过外观设置切为深色并关闭设置，检查侧栏文字和图标可读，截图 screenshots/dark-theme-fixed.png。用户级静态资源已更新，无管理员操作。

### 边牧品牌落地（2026-10-19）
- 首页透明边牧插画、顶部品牌头像、侧栏与工作台头像、关于页、淡绿筛选与发送按钮；Codex/Hermes 图标及会话功能保留。
- 内置 imagegen 生成两张透明 PNG，已保存 public/brand，来源与提示词摘要记录于该目录 README。
- TypeScript 与生产构建通过；Android 模拟器深色首页、侧栏检查通过，浅色主题已切换检查。APK 签名 v2/v3 通过，模拟器安装成功。
- 真机 d7e798c8 当前不在 ADB 列表，无法更新原生图标；手机网页刷新即可使用新版界面。APK 已生成，未声称真机安装成功。

### 边牧新版真机升级（2026-10-19 12:43）
- USB d7e798c8 在线，新版 APK 覆盖安装 Success；系统 lastUpdateTime 12:42:42，versionCode 303。
- 已打开真机 G-Collie，原有私有连接与设备配对保留，实际首页品牌头像、边牧插画和会话列表正常加载；未使用 ADB reverse。
- 真机截图 screenshots/collie-physical-installed.png。APK 内应用图标为新版边牧素材。

### 写实开心边牧 v2 真机更新（2026-10-19）
- approved 眼神优化设计稿通过内置 imagegen 生成透明头像/趴姿素材，分别以 v2 文件名保留，替换网页、PWA/通知和 Android 图标引用。
- TypeScript、生产构建、APK v2/v3 签名通过。用户级运行资源及 DEB/APK 更新，校验文件已重算。
- 真机重新插入出现 ADB no permissions，USB ACL 已有权限，重启 ADB daemon 后设备恢复；覆盖安装 Success（1516 ms），MainActivity 启动 Status ok。
- 安装后截图时 USB 再次断开，未获取新版真机截图，不宣称完成视觉验收；已确认服务 v2 图片 URL 返回成功。
