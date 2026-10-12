package com.kamofa.via.tasker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle

/**
 * Tasker asks, once per "Via Command" profile, whether the command it was handed (the
 * pass-through data from `ViaNative.requestTaskerQuery`) matches that profile's names.
 */
class CommandQueryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Tasker.ACTION_QUERY_CONDITION) return
        // Without pass-through data Tasker is polling on its own: no command arrived.
        val data = intent.getBundleExtra(Tasker.EXTRA_PASS_THROUGH_DATA)
        val command = data?.getString("command")
        if (command == null) {
            resultCode = Tasker.RESULT_CONDITION_UNSATISFIED
            return
        }
        val names = intent.getBundleExtra(Tasker.EXTRA_BUNDLE)?.getString("commands").orEmpty()
            .split(',').map { it.trim() }.filter { it.isNotEmpty() }
        if (names.isNotEmpty() && names.none { it.equals(command, ignoreCase = true) }) {
            resultCode = Tasker.RESULT_CONDITION_UNSATISFIED
            return
        }
        val variables = Bundle().apply {
            putString("%via_command", command)
            putString("%via_from", data.getString("from").orEmpty())
            putString("%via_raw", data.getString("raw").orEmpty())
            // Numbered variables are what Tasker reads as the %via_params() array.
            data.getStringArrayList("params").orEmpty().forEachIndexed { i, p ->
                putString("%via_params${i + 1}", p)
            }
        }
        resultCode = Tasker.RESULT_CONDITION_SATISFIED
        getResultExtras(true).putBundle(Tasker.EXTRA_VARIABLES, variables)
    }
}
