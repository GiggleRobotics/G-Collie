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
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onLinkPropertiesChanged(network: Network, link: LinkProperties) {
            if (networkStarted && !worker.isShutdown) worker.execute { try { startNetwork() } catch (_: Throwable) {} }
        }
    }
    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    private fun incoming(i: Intent?): String? = if (i?.data?.scheme == "gcollie" && i.data?.host == "connect") i.data?.getQueryParameter("url") else i?.getStringExtra("server")
    private fun startNetwork() {
        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
        val link = cm.getLinkProperties(cm.activeNetwork)
        val description = JSONObject()
        val addresses = JSONArray()
        if (link != null) {
            description.put("name", link.interfaceName).put("mtu", link.mtu)
            link.linkAddresses.forEach { addresses.put(it.address.hostAddress!!.split("%")[0] + "/" + it.prefixLength) }
            link.routes.firstOrNull { it.isDefaultRoute && it.gateway != null }?.let { description.put("gateway", it.gateway!!.hostAddress) }
        }
        checked(NativeNetwork.configureNetwork(description.put("addresses", addresses).toString()))
        checked(NativeNetwork.start(File(filesDir, "tailnet").absolutePath))
        networkStarted = true
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
                        (getSystemService(DOWNLOAD_SERVICE) as DownloadManager).enqueue(request)
                        result.success(null)
                    } catch (e: Exception) { result.error("download", e.message, null) }
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
                            else -> NativeNetwork.status()
                        }
                        val value = checked(raw)
                        runOnUiThread { result.success(value) }
                    } catch (e: Throwable) { runOnUiThread { result.error("network", e.message ?: "内置网络不可用", null) } }
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
