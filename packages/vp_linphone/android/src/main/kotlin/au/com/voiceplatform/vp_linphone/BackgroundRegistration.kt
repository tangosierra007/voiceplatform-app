package au.com.voiceplatform.vp_linphone

/**
 * What the re-registration job ([ReregisterWorker]) does after a phone
 * restart or an app update, free of Android types for JVM tests.
 *
 * Nothing brings the app's process back after either, so without this the
 * edge's binding (with its RFC 8599 push parameters) runs out and the phone
 * can't be reached, push included, until someone opens the app.
 *
 * The job never starts the foreground service: Android 15 refuses a
 * `phoneCall` or `microphone` foreground service started from
 * BOOT_COMPLETED, and Android 12+ refuses one started from a background job.
 * It creates the Core by itself for the few seconds a REGISTER takes, with
 * the stored account ([CredentialStore]), and stops it once the edge has
 * answered. Unregister-at-stop is off, so the binding stays; an incoming
 * call then comes as a high-priority FCM push, which may start the service.
 */
object BackgroundRegistration {

    /** How the job ended, for its WorkManager result. */
    enum class Outcome {
        /** The edge answered 200 OK. */
        REGISTERED,

        /** The engine was already up (the app, or a push wake): it refreshes its own registration. */
        ENGINE_RUNNING,

        /** Signed out (nothing stored): nothing to register. */
        NO_ACCOUNT,

        /** The edge refused the account (401, 403 and the like): trying again won't help. */
        REFUSED,

        /** No answer, a network error or a 5xx: worth another try. */
        FAILED,
    }

    sealed interface Plan {
        data object NoAccount : Plan

        /** The Core is up with an account: refresh it, with the new token if there is one. */
        data class RefreshRunning(val newPrid: String?) : Plan

        /** The service is starting, or up with no account yet: it registers by itself. */
        data object LeaveToEngine : Plan

        /** Nothing is running: a Core of our own, just long enough to register [record]. */
        data class Headless(val record: AccountRecord) : Plan
    }

    data class EngineState(val coreUp: Boolean, val accountUp: Boolean, val stopped: Boolean)

    fun plan(record: AccountRecord?, engine: EngineState, fcmToken: String?): Plan {
        if (record == null) return Plan.NoAccount
        val updated = withToken(record, fcmToken)
        val newPrid = updated.pushPrid.takeIf { it != record.pushPrid }
        return when {
            engine.coreUp && engine.accountUp -> Plan.RefreshRunning(newPrid)
            engine.coreUp || !engine.stopped -> Plan.LeaveToEngine
            else -> Plan.Headless(updated)
        }
    }

    /**
     * The record with today's FCM token as its pn-prid. Only an account that
     * registered with push parameters gets one; with no token (no Play
     * services, or Firebase didn't answer) the stored pn-prid stays.
     */
    fun withToken(record: AccountRecord, fcmToken: String?): AccountRecord {
        val token = fcmToken?.takeIf { it.isNotBlank() } ?: return record
        if (record.pushProvider != FCM || record.pushParam == null || record.pushPrid == null) return record
        if (token == record.pushPrid) return record
        return record.copy(pushPrid = token)
    }

    /** A Failed registration: the edge's own refusal (4xx but 408) is final, the rest is retried. */
    fun failure(sipCode: Int): Outcome = if (sipCode in 400..499 && sipCode != 408) Outcome.REFUSED else Outcome.FAILED

    const val FCM = "fcm"
}
