package com.kamofa.via

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * FCM wake-ups from the Via relay are `{"t": "wake"}` and carry no content: they only
 * mean "sync now". A new token is registered with the server by the same sync.
 */
class WakeService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        WakeWorker.enqueue(this)
    }

    override fun onNewToken(token: String) {
        WakeWorker.enqueue(this)
    }
}
