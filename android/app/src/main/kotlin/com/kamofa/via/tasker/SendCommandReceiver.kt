package com.kamofa.via.tasker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.kamofa.via.Headless

/** Tasker runs the "Send Via Command" action. Variables are already replaced in the bundle. */
class SendCommandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Tasker.ACTION_FIRE_SETTING) return
        val bundle = intent.getBundleExtra(Tasker.EXTRA_BUNDLE) ?: return
        val count = bundle.getString("param_count")?.toIntOrNull() ?: 0
        val completion = Tasker.completionUri(intent)
        val request = try {
            OneTimeWorkRequestBuilder<TaskerSendWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .setInputData(
                    workDataOf(
                        "to" to bundle.getString("to").orEmpty().split(',').filter { it.isNotEmpty() }.toTypedArray(),
                        "command" to bundle.getString("command").orEmpty().trim(),
                        "params" to Array(count) { bundle.getString("param$it").orEmpty() },
                        "completion" to completion,
                    ),
                )
                .build()
        } catch (e: IllegalStateException) {
            // WorkManager input is limited to 10 KB.
            completion?.let { Tasker.signalFinish(context, it, "The command is too long") }
            return
        }
        // Appended, so commands arrive in the order Tasker sent them.
        WorkManager.getInstance(context)
            .enqueueUniqueWork("via-tasker-send", ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }
}

/** Sends one command from a headless Flutter engine (`taskerSendMain` in Dart). */
class TaskerSendWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val args = mapOf(
            "to" to inputData.getStringArray("to").orEmpty().toList(),
            "command" to inputData.getString("command").orEmpty(),
            "params" to inputData.getStringArray("params").orEmpty().toList(),
        )
        val result = Headless.run(applicationContext, "taskerSendMain", args, timeoutMs = 50_000)
        val error = if (result == null) "Timed out" else (result.value as? Map<*, *>)?.get("error") as String?
        inputData.getString("completion")?.let { Tasker.signalFinish(applicationContext, it, error) }
        return Result.success()
    }

    // Only used for expedited work before Android 12.
    override suspend fun getForegroundInfo(): ForegroundInfo =
        Headless.foregroundInfo(applicationContext, "Sending a command")
}
