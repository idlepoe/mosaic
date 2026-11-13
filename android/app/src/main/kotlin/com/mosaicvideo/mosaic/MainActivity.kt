package com.mosaicvideo.mosaic

import android.app.Activity
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var source: File? = null
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var gallery: GalleryBridge
    private lateinit var updates: UpdateBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        gallery = GalleryBridge(this, flutterEngine)
        updates = UpdateBridge(this, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mosaic/media")
            .setMethodCallHandler { call, result ->
                if (call.method != "rotation") { result.notImplemented(); return@setMethodCallHandler }
                val path = call.argument<String>("path")
                executor.execute {
                    val retriever = MediaMetadataRetriever()
                    val rotation = try {
                        if (path == null) null else {
                            retriever.setDataSource(path)
                            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull()
                        }
                    } catch (_: Exception) { null }
                    finally { try { retriever.release() } catch (_: Exception) { } }
                    runOnUiThread { result.success(rotation) }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mosaic/storage")
            .setMethodCallHandler { call, result ->
                if (call.method != "export") { result.notImplemented(); return@setMethodCallHandler }
                if (pending != null) { result.error("BUSY", "이미 저장 중입니다.", null); return@setMethodCallHandler }
                val file = File(call.argument<String>("path") ?: "")
                val allowed = File(filesDir.parentFile, "app_flutter/results").canonicalFile
                if (!file.isFile || !file.canonicalPath.startsWith(allowed.path + File.separator)) {
                    result.error("INVALID", "결과 파일을 찾을 수 없습니다.", null); return@setMethodCallHandler
                }
                pending = result
                source = file
                val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension) ?: "application/octet-stream"
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mime
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: file.name)
                }
                try { startActivityForResult(intent, 4101) }
                catch (e: Exception) { pending = null; source = null; result.error("EXPORT", e.message, null) }
            }
    }

    @Deprecated("Activity result bridge for FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (::gallery.isInitialized && gallery.onActivityResult(requestCode, resultCode, data)) return
        if (requestCode != 4101) return
        val reply = pending ?: return
        val file = source
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || file == null) {
            pending = null; source = null; reply.success(false); return
        }
        executor.execute {
            try {
                contentResolver.openOutputStream(uri, "wt").use { output ->
                    requireNotNull(output) { "저장 위치를 열 수 없습니다." }
                    file.inputStream().use { input -> input.copyTo(output) }
                }
                runOnUiThread { pending = null; source = null; reply.success(true) }
            } catch (e: Exception) {
                runOnUiThread { pending = null; source = null; reply.error("EXPORT", e.message, null) }
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::gallery.isInitialized) gallery.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onDestroy() {
        if (::updates.isInitialized) updates.close()
        super.onDestroy()
    }
}
