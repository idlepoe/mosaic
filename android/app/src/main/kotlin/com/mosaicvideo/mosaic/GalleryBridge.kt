package com.mosaicvideo.mosaic

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Picker grants access only to chosen videos; exports insert new app-owned media. */
class GalleryBridge(private val activity: Activity, engine: FlutterEngine) {
    private val worker = Executors.newSingleThreadExecutor()
    private var pickerReply: MethodChannel.Result? = null
    private var saveReply: MethodChannel.Result? = null
    private var saveSource: File? = null

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "mosaic/gallery").setMethodCallHandler { call, reply ->
            when (call.method) {
                "pickVideos" -> pickVideos(reply)
                "save" -> save(call.argument<String>("path"), reply)
                else -> reply.notImplemented()
            }
        }
    }

    private fun pickVideos(reply: MethodChannel.Result) {
        if (pickerReply != null) { reply.error("BUSY", "이미 영상을 선택 중입니다.", null); return }
        pickerReply = reply
        val intent = if (Build.VERSION.SDK_INT >= 33) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "video/*"
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, MediaStore.getPickImagesMaxLimit())
            }
        } else {
            Intent(Intent.ACTION_PICK, MediaStore.Video.Media.EXTERNAL_CONTENT_URI).apply {
                type = "video/*"; putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        try { activity.startActivityForResult(intent, PICK_REQUEST) }
        catch (_: Exception) {
            try {
                activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    type = "video/*"; addCategory(Intent.CATEGORY_OPENABLE)
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }, PICK_REQUEST)
            } catch (e: Exception) { pickerReply = null; reply.error("PICK", e.message, null) }
        }
    }

    fun onActivityResult(request: Int, result: Int, data: Intent?): Boolean {
        if (request != PICK_REQUEST) return false
        val reply = pickerReply ?: return true
        pickerReply = null
        if (result != Activity.RESULT_OK) { reply.success(emptyList<Any>()); return true }
        val uris = LinkedHashSet<Uri>()
        data?.data?.let { uris.add(it) }
        data?.clipData?.let { clips -> for (i in 0 until clips.itemCount) uris.add(clips.getItemAt(i).uri) }
        worker.execute {
            val created = mutableListOf<File>()
            try {
                val folder = File(activity.cacheDir, "mosaic_imports").apply { mkdirs() }
                val picked = uris.map { uri ->
                    var name = "video.mp4"
                    activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) name = cursor.getString(0) ?: name
                    }
                    val safeName = name.replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1F]"), "_").takeLast(180)
                    val file = File(folder, "${UUID.randomUUID()}_$safeName")
                    created.add(file)
                    activity.contentResolver.openInputStream(uri).use { input ->
                        requireNotNull(input) { "선택한 영상을 열 수 없습니다." }
                        file.outputStream().use { output -> input.copyTo(output) }
                    }
                    mapOf("path" to file.absolutePath, "name" to name, "id" to uri.toString())
                }
                activity.runOnUiThread { reply.success(picked) }
            } catch (e: Exception) {
                created.forEach { it.delete() }
                activity.runOnUiThread { reply.error("IMPORT", "영상을 불러오지 못했습니다. 저장 공간을 확인하세요. ${e.message}", null) }
            }
        }
        return true
    }

    private fun save(path: String?, reply: MethodChannel.Result) {
        if (saveReply != null) { reply.error("BUSY", "갤러리에 저장 중입니다.", null); return }
        val file = File(path ?: "")
        val allowed = File(activity.filesDir.parentFile, "app_flutter/results").canonicalFile
        if (!file.isFile || !file.canonicalPath.startsWith(allowed.path + File.separator)) {
            reply.error("INVALID", "결과 파일을 찾을 수 없습니다.", null); return
        }
        saveSource = file; saveReply = reply
        if (Build.VERSION.SDK_INT <= 28 && activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), SAVE_PERMISSION)
        } else { writeMedia() }
    }

    fun onRequestPermissionsResult(request: Int, results: IntArray): Boolean {
        if (request != SAVE_PERMISSION) return false
        if (results.isNotEmpty() && results[0] == PackageManager.PERMISSION_GRANTED) writeMedia()
        else {
            saveReply?.error("PERMISSION", "갤러리에 저장하려면 저장 공간 권한이 필요합니다.", null)
            saveReply = null; saveSource = null
        }
        return true
    }

    private fun writeMedia() {
        val reply = saveReply ?: return
        val file = saveSource ?: return
        worker.execute {
            var uri: Uri? = null
            try {
                val mime = when (file.extension.lowercase()) {
                    "jpg", "jpeg" -> "image/jpeg"
                    "png" -> "image/png"
                    "gif" -> "image/gif"
                    "webp" -> "image/webp"
                    "webm" -> "video/webm"
                    else -> throw IllegalArgumentException("갤러리에 저장할 수 없는 형식입니다. 파일로 저장해 주세요.")
                }
                val video = mime.startsWith("video/")
                val base = if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
                val collection = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(MediaStore.MediaColumns.DATE_ADDED, System.currentTimeMillis() / 1000)
                    put(MediaStore.Images.ImageColumns.DATE_TAKEN, System.currentTimeMillis())
                }
                var legacyFile: File? = null
                if (Build.VERSION.SDK_INT >= 29) {
                    values.put(MediaStore.MediaColumns.RELATIVE_PATH, "$base/Mosaic")
                    values.put(MediaStore.MediaColumns.IS_PENDING, 1)
                } else {
                    @Suppress("DEPRECATION")
                    val directory = File(Environment.getExternalStoragePublicDirectory(base), "Mosaic").apply { mkdirs() }
                    var destination = File(directory, file.name)
                    var index = 1
                    while (destination.exists()) { destination = File(directory, "${file.nameWithoutExtension} (${index++}).${file.extension}") }
                    legacyFile = destination
                    @Suppress("DEPRECATION")
                    values.put(MediaStore.MediaColumns.DATA, destination.absolutePath)
                }
                val target = requireNotNull(activity.contentResolver.insert(collection, values)) { "갤러리 항목을 만들지 못했습니다." }
                uri = target
                activity.contentResolver.openOutputStream(target, "w").use { output ->
                    requireNotNull(output) { "갤러리 파일을 열지 못했습니다." }
                    file.inputStream().use { input -> input.copyTo(output) }
                }
                if (Build.VERSION.SDK_INT >= 29) {
                    activity.contentResolver.update(target, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
                } else if (legacyFile != null) {
                    MediaScannerConnection.scanFile(activity, arrayOf(legacyFile.absolutePath), arrayOf(mime), null)
                }
                activity.runOnUiThread {
                    saveReply = null; saveSource = null
                    reply.success(mapOf("uri" to target.toString(), "album" to "Mosaic", "name" to file.name))
                }
            } catch (e: Exception) {
                uri?.let { try { activity.contentResolver.delete(it, null, null) } catch (_: Exception) { } }
                activity.runOnUiThread { saveReply = null; saveSource = null; reply.error("GALLERY", e.message, null) }
            }
        }
    }

    companion object { private const val PICK_REQUEST = 4201; private const val SAVE_PERMISSION = 4202 }
}
