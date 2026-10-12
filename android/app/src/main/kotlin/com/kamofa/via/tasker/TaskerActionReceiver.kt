package com.kamofa.via.tasker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.kamofa.via.Headless
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * Tasker runs one of the actions ("Send Via Command" or "Send with Via"); the bundle's
 * `type` says which, and its variables are already replaced. Tasker finds a plugin's fire
 * receiver by package, so both actions share this one.
 */
class TaskerActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Tasker.ACTION_FIRE_SETTING) return
        val bundle = intent.getBundleExtra(Tasker.EXTRA_BUNDLE) ?: return
        // The values can be long (text, many params), more than WorkManager's 10 KB of
        // input, so they wait in a file.
        val values = JSONObject()
        for (key in bundle.keySet()) {
            if (!key.startsWith("net.dinglisch")) bundle.getString(key)?.let { values.put(key, it) }
        }
        val dir = File(context.cacheDir, "tasker-jobs").apply { mkdirs() }
        val job = File(dir, "${UUID.randomUUID()}.json").apply { writeText(values.toString()) }
        val request = OneTimeWorkRequestBuilder<TaskerSendWorker>()
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .setInputData(
                workDataOf(
                    "job" to job.absolutePath,
                    "timeout" to TaskerSendWorker.timeoutMs(bundle),
                    "completion" to Tasker.completionUri(intent),
                ),
            )
            .build()
        // Appended, so items arrive in the order Tasker sent them.
        WorkManager.getInstance(context)
            .enqueueUniqueWork("via-tasker-send", ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }
}

/** Sends one item from a headless Flutter engine (`taskerSendMain` in Dart). */
class TaskerSendWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val file = File(inputData.getString("job") ?: return Result.success())
        val error = try {
            val json = JSONObject(file.readText())
            val job = json.keys().asSequence().associateWith { json.getString(it) }
            val result = Headless.run(applicationContext, "taskerSendMain", job, inputData.getLong("timeout", 50_000))
            if (result == null) "Timed out" else (result.value as? Map<*, *>)?.get("error") as String?
        } catch (e: Exception) {
            "Could not send: ${e.message}"
        } finally {
            file.delete()
        }
        inputData.getString("completion")?.let { Tasker.signalFinish(applicationContext, it, error) }
        return Result.success()
    }

    // Only used for expedited work before Android 12.
    override suspend fun getForegroundInfo(): ForegroundInfo =
        Headless.foregroundInfo(applicationContext, "Sending from Tasker")

    companion object {
        /** Files can take a while; workers get 10 minutes at most. */
        fun timeoutMs(bundle: Bundle): Long =
            if (bundle.getString("type") == "item" && bundle.getString("kind") == "file") 9 * 60_000L else 50_000L
    }
}
