package au.com.voiceplatform.vp_linphone

import android.content.Context

/**
 * "This FCM token is not yet sent to the API." The background registration
 * ([ReregisterWorker]) can put a rotated token in the SIP contact, but only
 * the app can `PUT /devices/me/push-token` (it holds the session). Until it
 * does, the pushes the API sends (signed_out, voicemail, message) go to the
 * old token; the app sends it on its next start and clears the flag
 * (VpPushTokens).
 */
object PushTokenFlag {
    private const val PREFS = "vp_linphone_push"
    private const val KEY = "token_unsent"

    fun setUnsent(context: Context) {
        prefs(context).edit().putBoolean(KEY, true).apply()
    }

    fun isUnsent(context: Context): Boolean = prefs(context).getBoolean(KEY, false)

    fun markSent(context: Context) {
        prefs(context).edit().remove(KEY).apply()
    }

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
