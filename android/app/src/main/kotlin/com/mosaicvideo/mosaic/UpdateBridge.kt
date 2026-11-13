package com.mosaicvideo.mosaic

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** GitHub APK updates only; no background or unattended installation. */
class UpdateBridge(private val activity: MainActivity, engine: FlutterEngine) {
    fun close() { executor.shutdown() }
    private val executor = Executors.newSingleThreadExecutor()
    private val pm get() = activity.packageManager
    private val directory get() = File(activity.cacheDir, "updates").canonicalFile
    private val signingFlags get() = if (Build.VERSION.SDK_INT >= 28)
        PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    @Suppress("DEPRECATION")
    private fun current() = pm.getPackageInfo(activity.packageName, signingFlags)
    @Suppress("DEPRECATION")
    private fun code(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) }
        }?.toSet() ?: emptySet()
    }
    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "mosaic/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> try {
                    val installed = current()
                    result.success(mapOf(
                        "version" to installed.versionName,
                        "code" to code(installed),
                        "packageName" to activity.packageName,
                        "abis" to Build.SUPPORTED_ABIS.toList(),
                        "directory" to directory.path,
                        "release" to ((activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0)
                    ))
                } catch (_: Exception) { result.error("UPDATE_INFO", "Could not read installed version", null) }
                "install" -> {
                    val path = call.argument<String>("path") ?: ""
                    val hash = call.argument<String>("sha256") ?: ""
                    val expectedCode = call.argument<Number>("code")?.toLong() ?: -1
                    executor.execute {
                        try {
                            val apk = File(path).canonicalFile
                            require(apk.parentFile == directory && apk.name == "update.apk" && apk.isFile)
                            val digest = MessageDigest.getInstance("SHA-256")
                            apk.inputStream().use { input ->
                                val buffer = ByteArray(65536)
                                var size = input.read(buffer)
                                while (size >= 0) { if (size > 0) digest.update(buffer, 0, size); size = input.read(buffer) }
                            }
                            require(digest.digest().joinToString("") { "%02x".format(it) }.equals(hash, true))
                            @Suppress("DEPRECATION")
                            val archive = requireNotNull(pm.getPackageArchiveInfo(apk.path, signingFlags))
                            val installed = current()
                            require(archive.packageName == activity.packageName)
                            require(code(archive) == expectedCode && expectedCode > code(installed))
                            val actualSigners = signers(archive)
                            require(actualSigners.isNotEmpty() && actualSigners == signers(installed))
                            activity.runOnUiThread {
                                try {
                                    if (Build.VERSION.SDK_INT >= 26 && !pm.canRequestPackageInstalls()) {
                                        activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                            Uri.parse("package:${activity.packageName}")))
                                        result.success("permission")
                                    } else {
                                        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
                                        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                                            setDataAndType(uri, "application/vnd.android.package-archive")
                                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                            clipData = android.content.ClipData.newRawUri("Mosaic update", uri)
                                        })
                                        result.success("installer")
                                    }
                                } catch (_: Exception) { result.error("UPDATE_INSTALL", "Could not open installer", null) }
                            }
                        } catch (_: Exception) {
                            activity.runOnUiThread { result.error("UPDATE_VERIFY", "APK verification failed", null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
