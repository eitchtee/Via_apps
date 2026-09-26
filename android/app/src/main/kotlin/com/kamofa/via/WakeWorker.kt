package com.kamofa.via

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** Runs one inbox sync in a headless Flutter engine (`wakeMain` in Dart). */
class WakeWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val done = CompletableDeferred<Unit>()
        val engine = withContext(Dispatchers.Main) {
            FlutterEngine(applicationContext).also { engine ->
                Fcm.attach(applicationContext, engine)
                MethodChannel(engine.dartExecutor.binaryMessenger, "via/wake").setMethodCallHandler { call, result ->
                    if (call.method == "done") done.complete(Unit)
                    result.success(null)
                }
                val loader = FlutterInjector.instance().flutterLoader()
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "wakeMain"),
                )
            }
        }
        try {
            withTimeoutOrNull(9 * 60 * 1000L) { done.await() }
        } finally {
            Handler(Looper.getMainLooper()).post { engine.destroy() }
        }
        return Result.success()
    }

    // Only used for expedited work before Android 12.
    override suspend fun getForegroundInfo(): ForegroundInfo {
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Syncing", NotificationManager.IMPORTANCE_MIN),
        )
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Checking for new items")
            .setSilent(true)
            .build()
        return if (Build.VERSION.SDK_INT >= 29) {
            ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        private const val CHANNEL = "sync"
        private const val NOTIFICATION_ID = 7001

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
