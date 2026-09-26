package com.kamofa.via

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * `via/fcm` channel. FCM is only available when the app was built with a
 * google-services.json; otherwise [getToken] answers null and Dart falls back to polling.
 */
object Fcm {
    fun available(context: Context): Boolean = FirebaseApp.getApps(context).isNotEmpty()

    fun attach(context: Context, engine: FlutterEngine) {
        val appContext = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, "via/fcm").setMethodCallHandler { call, result ->
            when (call.method) {
                "getToken" -> {
                    if (!available(appContext)) {
                        result.success(null)
                    } else {
                        FirebaseMessaging.getInstance().token
                            .addOnSuccessListener { result.success(it) }
                            .addOnFailureListener { result.success(null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
