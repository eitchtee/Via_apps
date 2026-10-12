package com.kamofa.via.tasker

import android.content.Context
import android.content.Intent
import android.os.Bundle

/**
 * The Locale/Tasker plugin protocol, as far as Via uses it (see TaskerPlugin.java from
 * tasker.joaoapps.com). The "Via Command" event is fired by `ViaNative.requestTaskerQuery`
 * in Dart; the "Send Via Command" action runs [SendCommandReceiver].
 */
object Tasker {
    const val ACTION_EDIT_EVENT = "net.dinglisch.android.tasker.ACTION_EDIT_EVENT"
    const val ACTION_QUERY_CONDITION = "com.twofortyfouram.locale.intent.action.QUERY_CONDITION"
    const val ACTION_FIRE_SETTING = "com.twofortyfouram.locale.intent.action.FIRE_SETTING"

    const val EXTRA_BUNDLE = "com.twofortyfouram.locale.intent.extra.BUNDLE"
    const val EXTRA_BLURB = "com.twofortyfouram.locale.intent.extra.BLURB"

    const val RESULT_CONDITION_SATISFIED = 16
    const val RESULT_CONDITION_UNSATISFIED = 17

    private const val EXTRAS = "net.dinglisch.android.tasker.extras."
    const val EXTRA_PASS_THROUGH_DATA = EXTRAS + "PASS_THROUGH_DATA"
    const val EXTRA_VARIABLES = EXTRAS + "VARIABLES"
    const val EXTRA_REQUESTED_TIMEOUT = EXTRAS + "REQUESTED_TIMEOUT"
    private const val EXTRA_COMPLETION_INTENT = EXTRAS + "COMPLETION_INTENT"
    private const val EXTRA_RESULT_CODE = EXTRAS + "RESULT_CODE"
    const val EXTRA_RELEVANT_VARIABLES = "net.dinglisch.android.tasker.RELEVANT_VARIABLES"
    const val BUNDLE_VARIABLE_REPLACE_KEYS = "net.dinglisch.android.tasker.VARIABLE_REPLACE_KEYS"

    private const val RESULT_CODE_OK = -1
    private const val RESULT_CODE_FAILED = 2

    /** Where to report the end of a synchronous action, as an intent URI; null if Tasker isn't waiting. */
    fun completionUri(fireIntent: Intent): String? =
        when (val raw = fireIntent.extras?.get(EXTRA_COMPLETION_INTENT)) {
            is String -> raw
            is Intent -> raw.toUri(Intent.URI_INTENT_SCHEME)
            else -> null
        }

    /** Ends a synchronous action; a non-null [error] fails it with `%errmsg` set. */
    fun signalFinish(context: Context, completionUri: String, error: String?) {
        val intent = Intent.parseUri(completionUri, Intent.URI_INTENT_SCHEME)
            .putExtra(EXTRA_RESULT_CODE, if (error == null) RESULT_CODE_OK else RESULT_CODE_FAILED)
        if (error != null) intent.putExtra(EXTRA_VARIABLES, Bundle().apply { putString("%errmsg", error) })
        context.sendBroadcast(intent)
    }
}
