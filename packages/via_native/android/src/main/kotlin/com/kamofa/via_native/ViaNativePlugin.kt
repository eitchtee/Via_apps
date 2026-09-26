package com.kamofa.via_native

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.Executors

/**
 * Native helpers that must also work from background isolates (FCM, WorkManager), where
 * there is no Activity: clipboard, saving to Downloads, opening files. Reading a share
 * intent needs the Activity, so it only works in the foreground.
 */
class ViaNativePlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "via_native")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "copyText" -> {
                val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("Via", call.argument<String>("text")))
                result.success(null)
            }
            "saveToDownloads" -> background(result) {
                saveToDownloads(
                    call.argument<String>("path")!!,
                    call.argument<String>("name")!!,
                    call.argument<String>("mime") ?: "application/octet-stream",
                )
            }
            "openFile" -> {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(Uri.parse(call.argument<String>("uri")), call.argument<String>("mime"))
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                try {
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "deviceName" -> {
                val name = Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
                result.success(name?.takeIf { it.isNotBlank() } ?: Build.MODEL)
            }
            "getSharedData" -> {
                val intent = activity?.intent
                if (intent == null) {
                    result.success(null)
                } else {
                    background(result) { readShareIntent(intent) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun background(result: Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message, null) }
            }
        }
    }

    /** Copies [path] into Download/Via through MediaStore and returns the content URI. */
    private fun saveToDownloads(path: String, name: String, mime: String): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.RELATIVE_PATH, "Download/Via")
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("MediaStore insert failed")
        try {
            resolver.openOutputStream(uri)!!.use { out -> File(path).inputStream().use { it.copyTo(out) } }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return uri.toString()
    }

    /** Text and files of an ACTION_SEND(_MULTIPLE) intent. Files are copied to the cache. */
    private fun readShareIntent(intent: Intent): Map<String, Any?>? {
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }
        val uris = mutableListOf<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtraCompat(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
        } else {
            intent.getParcelableExtraCompat(Intent.EXTRA_STREAM)?.let { uris.add(it) }
        }
        val dir = File(context.cacheDir, "share").apply { deleteRecursively(); mkdirs() }
        val files = uris.mapIndexedNotNull { i, uri -> copyToCache(uri, File(dir, i.toString())) }
        return mapOf(
            "text" to intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
            "subject" to intent.getStringExtra(Intent.EXTRA_SUBJECT),
            "files" to files,
        )
    }

    private fun copyToCache(uri: Uri, dir: File): Map<String, Any>? {
        val resolver = context.contentResolver
        var name: String? = null
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) name = it.getString(0)
        }
        val fileName = (name ?: uri.lastPathSegment ?: "file").substringAfterLast('/')
        dir.mkdirs()
        val target = File(dir, fileName)
        val input = resolver.openInputStream(uri) ?: return null
        input.use { inp -> target.outputStream().use { inp.copyTo(it) } }
        return mapOf(
            "path" to target.absolutePath,
            "name" to fileName,
            "mime" to (resolver.getType(uri) ?: "application/octet-stream"),
            "size" to target.length(),
        )
    }

    @Suppress("DEPRECATION")
    private fun Intent.getParcelableExtraCompat(key: String): Uri? =
        if (Build.VERSION.SDK_INT >= 33) getParcelableExtra(key, Uri::class.java) else getParcelableExtra(key)

    @Suppress("DEPRECATION")
    private fun Intent.getParcelableArrayListExtraCompat(key: String): ArrayList<Uri>? =
        if (Build.VERSION.SDK_INT >= 33) getParcelableArrayListExtra(key, Uri::class.java)
        else getParcelableArrayListExtra(key)

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
