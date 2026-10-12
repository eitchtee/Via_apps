package com.kamofa.via.tasker

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import com.kamofa.via.Fcm
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * What Tasker opens to configure the plugin: a dialog drawn by Flutter (`taskerEditMain`).
 * Over `via/tasker_edit`, Dart reads the mode and the saved values with `config`, and ends
 * with `save` (values and blurb) or `cancel`. All values are strings.
 */
abstract class TaskerEditActivity : FlutterActivity() {
    protected abstract val mode: String

    /** Adds what this plugin type needs to the result and the bundle Tasker stores. */
    protected abstract fun complete(result: Intent, bundle: Bundle)

    override fun getDartEntrypointFunctionName(): String = "taskerEditMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Fcm.attach(this, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "via/tasker_edit").setMethodCallHandler { call, result ->
            when (call.method) {
                "config" -> {
                    val saved = intent.getBundleExtra(Tasker.EXTRA_BUNDLE)
                    val values = saved?.keySet()
                        ?.filter { !it.startsWith("net.dinglisch") }
                        ?.mapNotNull { key -> saved.getString(key)?.let { key to it } }
                        ?.toMap()
                        .orEmpty()
                    result.success(mapOf("mode" to mode, "values" to values))
                }
                "save" -> {
                    val bundle = Bundle()
                    call.argument<Map<String, String>>("values")!!.forEach { (k, v) -> bundle.putString(k, v) }
                    val data = Intent().putExtra(Tasker.EXTRA_BLURB, call.argument<String>("blurb"))
                    complete(data, bundle)
                    data.putExtra(Tasker.EXTRA_BUNDLE, bundle)
                    setResult(Activity.RESULT_OK, data)
                    result.success(null)
                    finish()
                }
                "cancel" -> {
                    setResult(Activity.RESULT_CANCELED)
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }
}

/** Configures the "Via Command" event: which command names fire it. */
class CommandEventEditActivity : TaskerEditActivity() {
    override val mode = "event"

    override fun complete(result: Intent, bundle: Bundle) {
        result.putExtra(
            Tasker.EXTRA_RELEVANT_VARIABLES,
            arrayOf(
                "%via_command\nCommand\nThe command's name",
                "%via_params()\nParams\nThe command's params",
                "%via_from\nFrom\nThe device that sent the command",
                "%via_raw\nRaw text\nThe command as received",
            ),
        )
    }
}

/** Configures the "Send Via Command" action: the devices, the command and its params. */
class SendCommandEditActivity : TaskerEditActivity() {
    override val mode = "command"

    override fun complete(result: Intent, bundle: Bundle) {
        val params = (0 until (bundle.getString("param_count")?.toIntOrNull() ?: 0)).map { "param$it" }
        // Tasker replaces variables in these before firing.
        bundle.putString(Tasker.BUNDLE_VARIABLE_REPLACE_KEYS, (listOf("command") + params).joinToString(" "))
        // Run synchronously, so the task waits for the send and sees a failure.
        result.putExtra(Tasker.EXTRA_REQUESTED_TIMEOUT, TaskerSendWorker.timeoutMs(bundle).toInt() + 10_000)
    }
}

/** Configures the "Send with Via" action: the devices, and text, a link or files. */
class SendItemEditActivity : TaskerEditActivity() {
    override val mode = "item"

    override fun complete(result: Intent, bundle: Bundle) {
        bundle.putString(Tasker.BUNDLE_VARIABLE_REPLACE_KEYS, "content title")
        result.putExtra(Tasker.EXTRA_REQUESTED_TIMEOUT, TaskerSendWorker.timeoutMs(bundle).toInt() + 10_000)
    }
}
