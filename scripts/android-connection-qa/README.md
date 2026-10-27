# Android 连接提醒专项

在已授权、解锁的内测手机上执行：

```bash
GCOLLIE_ADB_SERIAL=设备序列号 bash scripts/android-connection-qa/run.sh
```

需要本仓库内测签名安装的 Flutter APK、Android SDK 36 和同一 debug.keystore。测试临时安装独立 instrumentation APK，停止并重新启动手机应用；不会中断电脑 Agent 任务，不修改网络账号或配对凭据。

测试端点仅在手机回环地址监听，返回固定的任务状态夹具：正常→三次 503→恢复→继续正常。检查常驻状态、断线通知、恢复通知及后续不重复提醒；保留原“任务提醒”开关。退出时删除临时 APK、重新打开正式应用恢复实际连接。

此项证明真实 Android 通知服务状态转换，不等同于公网断线、锁屏后台保活或真实 OAuth 授权验证。请勿在用户正输入账号信息时运行。
