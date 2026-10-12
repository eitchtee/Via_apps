package com.kamofa.via

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.work.ForegroundInfo
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Runs a Dart entrypoint in a headless Flutter engine. Over the `via/headless` channel, Dart
 * reads its arguments with `args` and ends with `done`, whose argument is the result.
 */
object Headless {
    private const val CHANNEL = "sync"
    private const val NOTIFICATION_ID = 7001

    /** The result Dart passed to `done`, or null on timeout. */
    suspend fun run(
        context: Context,
        entrypoint: String,
        args: Map<String, Any?> = emptyMap(),
        timeoutMs: Long = 9 * 60 * 1000L,
    ): Result? {
        val done = CompletableDeferred<Result>()
        val engine = withContext(Dispatchers.Main) {
            FlutterEngine(context).also { engine ->
                Fcm.attach(context, engine)
                MethodChannel(engine.dartExecutor.binaryMessenger, "via/headless").setMethodCallHandler { call, result ->
                    when (call.method) {
                        "args" -> result.success(args)
                        "done" -> {
                            done.complete(Result(call.arguments))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
                val loader = FlutterInjector.instance().flutterLoader()
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), entrypoint),
                )
            }
        }
        try {
            return withTimeoutOrNull(timeoutMs) { done.await() }
        } finally {
            Handler(Looper.getMainLooper()).post { engine.destroy() }
        }
    }

    class Result(val value: Any?)

    /** For workers that run expedited, which before Android 12 means a foreground service. */
    fun foregroundInfo(context: Context, title: String): ForegroundInfo {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Syncing", NotificationManager.IMPORTANCE_MIN),
        )
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setSilent(true)
            .build()
        return ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    }
}
