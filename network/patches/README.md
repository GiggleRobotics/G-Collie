# Android 控制连接 TLS 握手时限补丁

固定上游：`tailscale.com v1.104.1`。正式手机经 VPN 到控制站的只读 curl 分段测得 TLS 完成时间约 5.775 秒；上游 `net/dnscache.TLSDialer` 的 5 秒握手时限会提前取消。该证据说明需要容纳较慢握手，尚不代表冷启动问题已在补丁后真机验收。

`prepare-network-tailscale.py` 校验版本、原文件 SHA256 和唯一替换位置，把模块复制到 `.packaging/network`，只修改副本。Android 构建通过临时 modfile 使用副本，将握手时限设为 15 秒。Linux 服务仍构建原模块；其他平台 helper 返回原有 5 秒。父 context 更早的 deadline、取消传播、TLS 认证和证书检查均不变。不修改共享 Go module 缓存、路由、DNS、代理或身份。

重现：运行 `python3 scripts/prepare-network-tailscale.py`；再于 `network` 中运行 `../.tools/go/bin/go test -modfile=../.packaging/network/android-network.mod tailscale.com/net/dnscache -run TestGCollieTLSHandshakeTimeout`。正式双架构构建由 `scripts/build-network.sh` 自动准备。上游升级或校验变化会明确失败，须人工复核后更新补丁，不能静默套用。

构建目录 `ANDROID-SOURCE-MODIFICATIONS.txt` 和 App 的 `NETWORK-NOTICES.txt` 记录修改；上游许可证保留。这里只增加容错时限，不承诺外网/VPN可靠性。
