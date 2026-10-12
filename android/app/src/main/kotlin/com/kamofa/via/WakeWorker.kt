package com.kamofa.via

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters

/** Runs one inbox sync in a headless Flutter engine (`wakeMain` in Dart). */
class WakeWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        Headless.run(applicationContext, "wakeMain")
        return Result.success()
    }

    // Only used for expedited work before Android 12.
    override suspend fun getForegroundInfo(): ForegroundInfo =
        Headless.foregroundInfo(applicationContext, "Checking for new items")

    companion object {
        fun enqueue(context: Context) {
            val request = OneTimeWorkRequestBuilder<WakeWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            // APPEND_OR_REPLACE: a wake during a running sync queues exactly one more.
            WorkManager.getInstance(context)
                .enqueueUniqueWork("via-wake", ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        }
    }
}
