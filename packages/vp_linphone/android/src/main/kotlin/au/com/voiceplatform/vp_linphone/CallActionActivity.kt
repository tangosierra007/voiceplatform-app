package au.com.voiceplatform.vp_linphone

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Not exported: only our own notification's PendingIntents can start it. It
 * checks the call's token ([CallActionGate]), acts (Answer), hands the UI
 * request to the plugin in memory ([PendingUiRequest]) and brings the app's
 * activity forward with no call extras at all, so nothing another app sends
 * to the exported launcher activity can answer a call or show it over the
 * lock screen.
 */
class CallActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handle(intent)
        finish()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
        finish()
    }

    private fun handle(intent: Intent?) {
        intent ?: return
        val callId = intent.getStringExtra(TelecomBridge.EXTRA_CALL_ID)
        val token = intent.getStringExtra(IncomingCallNotifier.EXTRA_TOKEN)
        val action = when (intent.getStringExtra(IncomingCallNotifier.EXTRA_ACTION)) {
            IncomingCallNotifier.ACTION_SHOW_INCOMING -> CallActionGate.Action.SHOW_INCOMING
            IncomingCallNotifier.ACTION_ANSWER -> CallActionGate.Action.ANSWER
            else -> return
        }
        if (!IncomingCallNotifier.gate.authorise(action, callId, token)) {
            LinphoneEngine.logLine("TELECOM", "notification action refused: bad or used token")
            return
        }
        callId!!
        val request = if (action == CallActionGate.Action.ANSWER) {
            TelecomBridge.answerFromNotification(this, callId)
            UiRequestMsg(UiRequestKindMsg.SHOW_CALL, callId)
        } else {
            UiRequestMsg(UiRequestKindMsg.SHOW_INCOMING, callId)
        }
        // The app's own activity is already under this one: the notification's
        // PendingIntent starts both (IncomingCallNotifier.activityIntent), so
        // nothing here starts an activity from the background, which Android
        // blocks on a locked or backgrounded phone.
        PendingUiRequest.post(request)
    }
}
