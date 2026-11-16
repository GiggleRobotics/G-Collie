package dev.giggle.g_collie_flutter

import android.app.DownloadManager
import android.net.Uri
import android.os.Environment
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Network
import android.net.LinkProperties
import android.net.ConnectivityManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.util.concurrent.Executors
import dev.giggle.gcollie.NativeNetwork
import dev.giggle.gcollie.TaskNotifications

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var networkStarted = false
    private var noStateSince = 0L
    private var lastNetworkRecovery = 0L
    private companion object {
        // Match the native node's process lifetime, including Activity recreation.
        val networkRefreshGeneration = java.util.concurrent.atomic.AtomicLong(0L)
    }
    private var lastOpenFailureLog = 0L
    private fun logNetworkOpenFailure() {
        val now = android.os.SystemClock.elapsedRealtime()
        if (lastOpenFailureLog != 0L && now - lastOpenFailureLog < 30000L) return
        lastOpenFailureLog = now
        val safe = JSONObject().put("event", "open_failed")
        try {
            val status = JSONObject(NativeNetwork.status())
            val state = status.optString("state")
            val allowedStates = setOf("NoState", "Stopped", "Starting", "Running", "NeedsLogin", "NeedsMachineAuth", "InUseOtherUser", "error")
            safe.put("state", if (state in allowedStates) state else "unknown")
            // Only allowlisted Go counters/categories; never error/authURL/address/token.
            safe.put("diagnostics", status.optJSONObject("diagnostics") ?: JSONObject())
        } catch (_: Throwable) {
            safe.put("state", "diagnostic_unavailable")
        }
        android.util.Log.w("GCollieNetwork", safe.toString())
    }
    private fun networkStatus(): String {
        var raw = NativeNetwork.status()
        val state = JSONObject(raw).optString("state")
        val now = android.os.SystemClock.elapsedRealtime()
        if (state == "NoState") {
            if (noStateSince == 0L) noStateSince = now
            if (now - noStateSince >= 20000L && (lastNetworkRecovery == 0L || now - lastNetworkRecovery >= 120000L)) {
                lastNetworkRecovery = now
                // Only Go's allowlisted counters/categories are logged, never raw status/authURL.
                val safe = JSONObject().put("state", "NoState")
                    .put("waitingSeconds", (now - noStateSince) / 1000)
                    .put("diagnostics", JSONObject(raw).optJSONObject("diagnostics") ?: JSONObject())
                android.util.Log.w("GCollieNetwork", safe.toString())
                // Only this rate-limited recovery forces one link observation refresh.
                // Node identity, private-network login and device pairing stay intact.
                startNetwork(forceRefresh = true)
                raw = NativeNetwork.status()
            }
        } else { noStateSince = 0L; lastNetworkRecovery = 0L }
        return raw
    }
    private fun refreshNetwork() {
        if (!worker.isShutdown) worker.execute {
            try {
                if (startNetwork()) {
                    runOnUiThread { channel?.invokeMethod("networkChanged", null) }
                }
            } catch (e: Throwable) {
                android.util.Log.w("GCollieNetwork", "Network update failed: ${e.javaClass.simpleName}")
            }
        }
    }
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { refreshNetwork() }
        override fun onLost(network: Network) { refreshNetwork() }
        override fun onLinkPropertiesChanged(network: Network, link: LinkProperties) { refreshNetwork() }
    }
    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    private fun incoming(i: Intent?): String? = if (i?.data?.scheme == "gcollie" && i.data?.host == "connect") i.data?.getQueryParameter("url") else i?.getStringExtra("server")
    private fun startNetwork(forceRefresh: Boolean = false): Boolean {
        // Ordinary Status/Open retain the same value and do not inject netmon events.
        // Keep the incremented value across later ordinary calls, not a one-shot flag.
        if (forceRefresh) networkRefreshGeneration.incrementAndGet()
        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        val link = cm.getLinkProperties(cm.activeNetwork)
        val capabilities = cm.getNetworkCapabilities(cm.activeNetwork)
        val interfaceType = when {
            capabilities?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN) == true -> "vpn"
            capabilities?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) == true -> "mobile"
            capabilities?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true -> "wifi"
            capabilities?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET) == true -> "ethernet"
            cm.activeNetwork == null -> "none"
            else -> "other"
        }
        val description = JSONObject().put("interfaceType", interfaceType)
        val addresses = JSONArray()
        if (link != null) {
            description.put("name", link.interfaceName).put("mtu", link.mtu)
            val dns = JSONArray()
            link.dnsServers.forEach { dns.put(it.hostAddress!!.split("%")[0]) }
            description.put("dns", dns)
            if (Build.VERSION.SDK_INT >= 28 && link.isPrivateDnsActive && !link.privateDnsServerName.isNullOrBlank()) {
                description.put("privateDNSName", link.privateDnsServerName)
            }
            link.linkAddresses.forEach { addresses.put(it.address.hostAddress!!.split("%")[0] + "/" + it.prefixLength) }
            link.routes.firstOrNull { it.isDefaultRoute && it.gateway != null }?.let { description.put("gateway", it.gateway!!.hostAddress) }
        }
        description.put("networkHandle", cm.activeNetwork?.networkHandle ?: 0L)
        description.put("refreshGeneration", networkRefreshGeneration.get())
        val configuration = JSONObject(checked(NativeNetwork.configureNetwork(description.put("addresses", addresses).toString())))
        val changed = configuration.optBoolean("changed", true) || !networkStarted
        checked(NativeNetwork.start(File(filesDir, "tailnet").absolutePath))
        networkStarted = true
        return changed
    }
    private fun checked(raw: String): String {
        val value = JSONObject(raw)
        if (value.has("error")) throw IllegalStateException(value.getString("error"))
        return raw
    }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager).registerDefaultNetworkCallback(networkCallback)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dev.giggle.gcollie/native")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "appVersion" -> {
                    try {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(info.versionName)
                    } catch (e: Throwable) {
                        result.error("version_unavailable", "无法读取应用版本", null)
                    }
                }
                "clipboardImage" -> {
                    try {
                        val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        val clip = clipboard.primaryClip
                        val uri = if (clip != null && clip.itemCount > 0) clip.getItemAt(0).uri else null
                        if (uri == null || uri.scheme != "content" || !(contentResolver.getType(uri) ?: "").startsWith("image/")) {
                            result.error("no_image", "剪贴板中没有可读取的图片", null)
                        } else {
                            worker.execute {
                                try {
                                    val bytes = contentResolver.openInputStream(uri)?.use { val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
                                        while (output.size() <= 10 * 1024 * 1024) { val n = it.read(buffer); if (n < 0) break; output.write(buffer, 0, n) }; output.toByteArray() } ?: throw IllegalArgumentException("无法读取剪贴板图片")
                                    if (bytes.isEmpty() || bytes.size > 10 * 1024 * 1024) throw IllegalArgumentException("请选择不超过 10 MB 的图片")
                                    val mime = contentResolver.getType(uri)
                                    val ext = when (mime) { "image/png" -> "png"; "image/jpeg" -> "jpg"; "image/webp" -> "webp"; "image/gif" -> "gif"; else -> throw IllegalArgumentException("暂不支持该图片格式") }
                                    val file = File(cacheDir, "clipboard-${System.currentTimeMillis()}.$ext")
                                    file.writeBytes(bytes)
                                    runOnUiThread { result.success(file.absolutePath) }
                                } catch (e: Exception) { runOnUiThread { result.error("clipboard_read", "无法读取剪贴板图片，请重新复制后重试", null) } }
                            }
                        }
                    } catch (e: Exception) { result.error("clipboard_read", "无法读取剪贴板图片，请重新复制后重试", null) }
                }
                "offlineDirectory" -> {
                    val directory = java.io.File(filesDir, "offline-images")
                    directory.mkdirs()
                    result.success(directory.absolutePath)
                }
                "downloadFile" -> {
                    try {
                        val uri = Uri.parse(call.argument<String>("url") ?: "")
                        if (uri.scheme != "http" || uri.host != "127.0.0.1" || uri.port <= 0 ||
                            !Regex("^/preview/[a-f0-9]{48}/content$").matches(uri.path ?: "") || uri.getQueryParameter("download") != "1") {
                            throw IllegalArgumentException("无效文件下载地址")
                        }
                        val name = (call.argument<String>("name") ?: "download").replace(Regex("[\\\\/\u0000-\u001f]"), "_").take(150)
                        val filename = "${System.currentTimeMillis()}-$name"
                        val request = DownloadManager.Request(uri).setTitle(name)
                            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        if (Build.VERSION.SDK_INT >= 29) request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, filename)
                        else request.setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, filename)
                        val id = (getSystemService(DOWNLOAD_SERVICE) as DownloadManager).enqueue(request)
                        val prefs = getSharedPreferences("downloads", MODE_PRIVATE)
                        val rows = JSONArray(prefs.getString("rows", "[]"))
                        rows.put(JSONObject().put("id", id).put("name", name).put("time", System.currentTimeMillis()).put("previewRequest",call.argument<String>("previewRequest") ?: "").put("computer",call.argument<String>("computer") ?: ""))
                        prefs.edit().putString("rows", rows.toString()).apply()
                        result.success(id)
                    } catch (e: Exception) { result.error("download", e.message, null) }
                }
                "shareDiagnostic" -> {
                    startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_SUBJECT,"G-Collie 诊断记录").putExtra(Intent.EXTRA_TEXT,call.argument<String>("text") ?: ""), "导出诊断记录"))
                    result.success(null)
                }
                "downloads" -> {
                    val manager = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
                    val rows = JSONArray(getSharedPreferences("downloads", MODE_PRIVATE).getString("rows", "[]"))
                    val output = ArrayList<Map<String, Any>>()
                    for (i in rows.length()-1 downTo 0) {
                        val row = rows.getJSONObject(i)
                        manager.query(DownloadManager.Query().setFilterById(row.getLong("id"))).use { cursor ->
                            if (cursor.moveToFirst()) {
                                output.add(mapOf("id" to row.getLong("id"), "name" to row.getString("name"), "time" to row.getLong("time"), "previewRequest" to row.optString("previewRequest"), "computer" to row.optString("computer"),
                                    "status" to cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)),
                                    "bytes" to cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                                    "total" to cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),
                                    "reason" to cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))))
                            } else output.add(mapOf("id" to row.getLong("id"), "name" to row.getString("name"), "time" to row.getLong("time"), "previewRequest" to row.optString("previewRequest"), "computer" to row.optString("computer"), "status" to -1))
                        }
                    }
                    result.success(output)
                }
                "readDownloadImage" -> worker.execute {
                    try {
                        val id=call.argument<Number>("id")!!.toLong()
                        val manager=getSystemService(DOWNLOAD_SERVICE) as DownloadManager
                        val mime=manager.getMimeTypeForDownloadedFile(id) ?: ""
                        if (!mime.startsWith("image/")) { runOnUiThread { result.success(null) } }
                        else {
                            val uri=manager.getUriForDownloadedFile(id) ?: throw IllegalStateException("文件不存在")
                            val bytes=contentResolver.openInputStream(uri)!!.use { val out=java.io.ByteArrayOutputStream(); val buffer=ByteArray(8192); var count=it.read(buffer); while(count!=-1 && out.size()<=15*1024*1024){out.write(buffer,0,count);count=it.read(buffer)};out.toByteArray() }
                            if(bytes.size>15*1024*1024) throw IllegalStateException("图片超过 15 MB，请使用其他应用打开")
                            runOnUiThread { result.success(bytes) }
                        }
                    }catch(e:Exception){runOnUiThread{result.error("image",e.message,null)}}
                }
                "openDownload" -> {
                    try {
                        val id = call.argument<Number>("id")!!.toLong()
                        val manager = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
                        val uri = manager.getUriForDownloadedFile(id) ?: throw IllegalStateException("本地文件不存在或尚未完成下载")
                        contentResolver.openFileDescriptor(uri, "r")?.close() ?: throw IllegalStateException("本地文件不存在")
                        val mime = manager.getMimeTypeForDownloadedFile(id) ?: "application/octet-stream"
                        startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "打开下载内容"))
                        result.success(null)
                    } catch(e: Exception) { result.error("open", e.message, null) }
                }
                "authorizationComplete" -> {
                    startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                    result.success(null)
                }
                "initialLink" -> result.success(incoming(intent))
                "notificationEnabled" -> result.success(getSharedPreferences("connection", MODE_PRIVATE).getBoolean("notifications", false))
                "notificationStatus" -> result.success(TaskNotifications.running)
                "notificationPermission" -> {
                    if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) result.success(true)
                    else if (permissionResult != null) result.error("busy", "正在请求通知权限", null)
                    else { permissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 701) }
                }
                "notificationsStop" -> { getSharedPreferences("connection", MODE_PRIVATE).edit().putBoolean("notifications", false).apply(); stopService(Intent(this, TaskNotifications::class.java)); result.success(null) }
                "notificationsStart" -> {
                    getSharedPreferences("connection", MODE_PRIVATE).edit().putBoolean("notifications", true).apply()
                    val service = Intent(this, TaskNotifications::class.java)
                        .putExtra("origin", call.argument<String>("origin"))
                        .putExtra("cookie", call.argument<String>("cookie"))
                        .putExtra("remote", call.argument<String>("remote"))
                    try { startForegroundService(service); result.success(null) } catch (e: Exception) { result.error("notifications", e.message, null) }
                }
                "networkStatus", "networkLogin", "networkLogout", "networkOpen" -> worker.execute {
                    try {
                        startNetwork()
                        val raw = when (call.method) {
                            "networkLogin" -> NativeNetwork.login()
                            "networkLogout" -> NativeNetwork.logout()
                            "networkOpen" -> NativeNetwork.open(call.argument<String>("remote") ?: "")
                            else -> networkStatus()
                        }
                        val value = checked(raw)
                        runOnUiThread { result.success(value) }
                    } catch (e: Throwable) {
                        if (call.method == "networkOpen") logNetworkOpenFailure()
                        runOnUiThread { result.error("network", e.message ?: "内置网络不可用", null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); incoming(intent)?.let { channel?.invokeMethod("link", it) } }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 701) { permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED); permissionResult = null }
    }
    override fun onDestroy() { (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(networkCallback); worker.shutdownNow(); super.onDestroy() }
}
