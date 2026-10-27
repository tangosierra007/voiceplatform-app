package au.com.voiceplatform.vp_linphone

import org.linphone.core.AudioDevice
import org.linphone.core.Call
import org.linphone.core.Reason

/**
 * Pure mappings from liblinphone's types to the CallEngine contract, kept free
 * of any native call so they run in JVM unit tests.
 */
object Mapping {

    /** Null means "no change to the snapshot's state" (early updates). */
    fun callState(state: Call.State): CallStateMsg? = when (state) {
        Call.State.IncomingReceived,
        Call.State.PushIncomingReceived,
        Call.State.IncomingEarlyMedia -> CallStateMsg.INCOMING
        Call.State.OutgoingInit,
        Call.State.OutgoingProgress -> CallStateMsg.DIALLING
        Call.State.OutgoingRinging,
        Call.State.OutgoingEarlyMedia -> CallStateMsg.RINGING
        Call.State.Connected,
        Call.State.StreamsRunning,
        Call.State.Updating,
        Call.State.UpdatedByRemote,
        Call.State.Resuming -> CallStateMsg.CONNECTED
        Call.State.Pausing,
        Call.State.Paused -> CallStateMsg.HELD_BY_ME
        Call.State.PausedByRemote -> CallStateMsg.HELD_BY_REMOTE
        Call.State.Referred -> CallStateMsg.TRANSFERRING
        Call.State.Error,
        Call.State.End,
        Call.State.Released -> CallStateMsg.ENDED
        Call.State.Idle,
        Call.State.EarlyUpdating,
        Call.State.EarlyUpdatedByRemote -> null
    }

    /** What this device asked for, so the end reason says so. */
    enum class LocalIntent { HANGUP, DECLINE, TO_VOICEMAIL }

    data class EndFacts(
        val incoming: Boolean,
        val wasConnected: Boolean,
        val localIntent: LocalIntent?,
        val finalState: Call.State,
        val logStatus: Call.Status?,
        val reason: Reason?,
        /** SIP status of the failure or the Reason header's cause. */
        val protocol: String?,
        val protocolCode: Int,
    )

    fun endReason(f: EndFacts): EndReasonMsg {
        when (f.localIntent) {
            LocalIntent.DECLINE -> return EndReasonMsg.DECLINED
            LocalIntent.TO_VOICEMAIL -> return EndReasonMsg.TO_VOICEMAIL
            LocalIntent.HANGUP -> return EndReasonMsg.LOCAL
            null -> {}
        }
        // CANCEL with Reason: SIP;cause=200;text="Call completed elsewhere".
        if (f.incoming && !f.wasConnected &&
            (f.logStatus == Call.Status.AcceptedElsewhere ||
                (f.protocol.equals("SIP", ignoreCase = true) && f.protocolCode == 200))
        ) {
            return EndReasonMsg.ANSWERED_ELSEWHERE
        }
        if (f.logStatus == Call.Status.DeclinedElsewhere) return EndReasonMsg.DECLINED
        val code = f.protocolCode
        if (f.reason == Reason.Busy || code == 486 || code == 600) return EndReasonMsg.BUSY
        if (f.reason == Reason.Declined || code == 603) return EndReasonMsg.DECLINED
        if (!f.incoming && !f.wasConnected &&
            (f.reason == Reason.NotAnswered || code == 480 || code == 408)
        ) {
            return EndReasonMsg.NO_ANSWER
        }
        if (f.reason == Reason.IOError || f.reason == Reason.NoResponse || code == 503) {
            return if (f.wasConnected) EndReasonMsg.NETWORK_LOST else EndReasonMsg.FAILED
        }
        if (f.finalState == Call.State.Error) return EndReasonMsg.FAILED
        return EndReasonMsg.REMOTE
    }

    fun registrationFailure(code: Int, reason: Reason?, phrase: String?): RegFailureMsg {
        val p = phrase?.lowercase().orEmpty()
        return when {
            code == 401 || code == 407 || reason == Reason.Unauthorized -> RegFailureMsg.BAD_CREDENTIALS
            code == 403 || reason == Reason.Forbidden -> RegFailureMsg.FORBIDDEN
            "tls" in p || "certificate" in p || "handshake" in p -> RegFailureMsg.TLS
            code == 408 || code == 504 || reason == Reason.NoResponse || reason == Reason.ServerTimeout -> RegFailureMsg.TIMEOUT
            code == 503 || reason == Reason.IOError -> RegFailureMsg.NETWORK
            else -> RegFailureMsg.UNKNOWN
        }
    }

    /** Opus first, then G.722, PCMA, PCMU (decision 135); telephone-event for RFC 4733. */
    val PREFERRED_CODECS = listOf("opus", "G722", "PCMA", "PCMU")

    /**
     * Given the payload types' mime types in liblinphone's order, returns the
     * new order as indices into [mimeTypes], each with whether it is enabled.
     * Preferred codecs come first in [PREFERRED_CODECS] order, then
     * telephone-event (enabled), then everything else (disabled).
     */
    fun codecPlan(mimeTypes: List<String>): List<Pair<Int, Boolean>> {
        val plan = mutableListOf<Pair<Int, Boolean>>()
        val used = mutableSetOf<Int>()
        for (want in PREFERRED_CODECS) {
            mimeTypes.forEachIndexed { i, m ->
                if (i !in used && m.equals(want, ignoreCase = true)) {
                    plan += i to true
                    used += i
                }
            }
        }
        mimeTypes.forEachIndexed { i, m ->
            if (i !in used && m.equals("telephone-event", ignoreCase = true)) {
                plan += i to true
                used += i
            }
        }
        mimeTypes.indices.filter { it !in used }.forEach { plan += it to false }
        return plan
    }

    fun isHdCodec(mimeType: String?): Boolean =
        mimeType != null && (mimeType.equals("opus", true) || mimeType.equals("G722", true))

    fun route(type: AudioDevice.Type): AudioRouteMsg? = when (type) {
        AudioDevice.Type.Earpiece -> AudioRouteMsg.EARPIECE
        AudioDevice.Type.Speaker -> AudioRouteMsg.SPEAKER
        AudioDevice.Type.Bluetooth,
        AudioDevice.Type.BluetoothA2DP,
        AudioDevice.Type.HearingAid -> AudioRouteMsg.BLUETOOTH
        AudioDevice.Type.Headset,
        AudioDevice.Type.Headphones,
        AudioDevice.Type.GenericUsb -> AudioRouteMsg.WIRED_HEADSET
        else -> null
    }

    /** Device types to try for a route, best first. */
    fun deviceTypes(route: AudioRouteMsg): List<AudioDevice.Type> = when (route) {
        AudioRouteMsg.EARPIECE -> listOf(AudioDevice.Type.Earpiece)
        AudioRouteMsg.SPEAKER -> listOf(AudioDevice.Type.Speaker)
        AudioRouteMsg.BLUETOOTH -> listOf(
            AudioDevice.Type.Bluetooth, AudioDevice.Type.HearingAid, AudioDevice.Type.BluetoothA2DP,
        )
        AudioRouteMsg.WIRED_HEADSET -> listOf(
            AudioDevice.Type.Headset, AudioDevice.Type.Headphones, AudioDevice.Type.GenericUsb,
        )
        // Android Auto arrives with Telecom (3.2); liblinphone alone can't route to it.
        AudioRouteMsg.CAR -> emptyList()
    }
}

/** Dial-string rules. */
object Rules {
    /**
     * Spec 22, Emergency calls: after removing spaces and punctuation, 000, 112
     * or 106, alone or with a leading 0. call() never refuses these (rule 8):
     * it skips the registration and microphone checks and places the call.
     */
    fun isEmergency(number: String): Boolean {
        // Letters, `*` and `#` make it something else (a SIP name, a feature code).
        if (number.any { it.isLetter() || it == '*' || it == '#' }) return false
        return number.filter { it.isDigit() } in EMERGENCY
    }

    private val EMERGENCY = setOf("000", "112", "106", "0000", "0112", "0106")

    /** Keeps digits, `+` (leading only), `*` and `#`; drops spaces and punctuation. */
    fun dialString(number: String): String {
        val trimmed = number.trim()
        val sb = StringBuilder()
        trimmed.forEachIndexed { i, c ->
            when {
                c.isDigit() || c == '*' || c == '#' -> sb.append(c)
                c == '+' && sb.isEmpty() && i == trimmed.indexOfFirst { !it.isWhitespace() } -> sb.append(c)
            }
        }
        return sb.toString()
    }

    /** A user part we can put in a SIP URI: an extension, a number, or a feature code. */
    fun isDialable(dial: String): Boolean = dial.isNotEmpty() && dial.length <= 32 &&
        dial.trimStart('+').isNotEmpty() && dial.trimStart('+').all { it.isDigit() || it == '*' || it == '#' }

    private val UUID_RE = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

    /**
     * `urn:uuid:<uuid>` (the contract's instanceId) to the bare lower-case UUID
     * liblinphone keeps in `[misc] uuid`; null if it isn't one.
     */
    fun instanceUuid(instanceId: String): String? {
        val v = instanceId.trim().lowercase()
        if (!v.startsWith("urn:uuid:")) return null
        val bare = v.removePrefix("urn:uuid:")
        return if (UUID_RE.matches(bare)) bare else null
    }

    fun isValidDtmf(digits: String): Boolean =
        digits.isNotEmpty() && digits.length <= 64 && digits.all { it in "0123456789*#ABCDabcd" }
}
