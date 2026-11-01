package au.com.voiceplatform.vp_linphone

import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test
import org.linphone.core.Call
import org.linphone.core.MediaEncryption
import org.linphone.core.Reason

/** APP13: SRTP is mandatory on every app call. */
class MediaSecurityTest {

    /** liblinphone's defaults for a fresh Core: no encryption, not mandatory. */
    private class FakeCore(
        private val supported: Set<MediaEncryption> = setOf(MediaEncryption.None, MediaEncryption.SRTP),
    ) : MediaSecurity.CoreSettings {
        override var encryption = MediaEncryption.None
        override var mandatory = false
        override var capabilityNegotiation = true
        override fun supports(encryption: MediaEncryption) = encryption in supported
    }

    private class FakeParams : MediaSecurity.Settings {
        override var encryption = MediaEncryption.None
        override var capabilityNegotiation = true
    }

    @Test
    fun coreIsSrtpMandatoryWithoutCapabilityNegotiation() {
        val core = FakeCore()
        MediaSecurity.applyToCore(core)
        assertEquals(MediaEncryption.SRTP, core.encryption)
        assertTrue(core.mandatory)
        // With capability negotiation on, RTP/AVP could sit on the m-line.
        assertFalse(core.capabilityNegotiation)
        assertTrue(MediaSecurity.coreCompliant(core.encryption, core.mandatory))
    }

    @Test
    fun noSrtpInTheBuildMeansNoEngine() {
        val core = FakeCore(supported = setOf(MediaEncryption.None))
        assertFailsWith<MediaSecurity.Unavailable> { MediaSecurity.applyToCore(core) }
        assertEquals(MediaEncryption.None, core.encryption)
        assertFalse(MediaSecurity.coreCompliant(core.encryption, core.mandatory))
    }

    @Test
    fun everyCallsParamsAreSrtp() {
        val p = FakeParams()
        MediaSecurity.applyToCall(p)
        assertEquals(MediaEncryption.SRTP, p.encryption)
        assertFalse(p.capabilityNegotiation)
    }

    @Test
    fun aCoreThatIsNotMandatorySrtpRefusesCalls() {
        assertFalse(MediaSecurity.coreCompliant(MediaEncryption.SRTP, mandatory = false))
        assertFalse(MediaSecurity.coreCompliant(MediaEncryption.None, mandatory = true))
        assertFalse(MediaSecurity.coreCompliant(MediaEncryption.DTLS, mandatory = true))
        assertFalse(MediaSecurity.coreCompliant(null, mandatory = true))
        assertTrue(MediaSecurity.coreCompliant(MediaEncryption.SRTP, mandatory = true))
    }

    private val checked = listOf(Call.State.StreamsRunning, Call.State.OutgoingEarlyMedia, Call.State.PausedByRemote)

    @Test
    fun mediaWithoutSrtpEndsTheCallInEveryStateWhereAudioFlows() {
        // StreamsRunning: an answer without crypto, a late-offer call, or a
        // re-INVITE that dropped crypto. OutgoingEarlyMedia: a 183 with SDP.
        // PausedByRemote: a remote hold (music on hold).
        for (s in checked) {
            assertEquals(MediaSecurity.Verdict.END, MediaSecurity.verdict(s, MediaEncryption.None), s.name)
            assertEquals(MediaSecurity.Verdict.END, MediaSecurity.verdict(s, null), s.name)
            assertEquals(MediaSecurity.Verdict.END, MediaSecurity.verdict(s, MediaEncryption.DTLS), s.name)
            assertEquals(MediaSecurity.Verdict.END, MediaSecurity.verdict(s, MediaEncryption.ZRTP), s.name)
            assertEquals(MediaSecurity.Verdict.ALLOW, MediaSecurity.verdict(s, MediaEncryption.SRTP), s.name)
        }
    }

    @Test
    fun exactlyTheThreeAudioStatesAreChecked() {
        assertEquals(checked.toSet(), MediaSecurity.CHECKED_STATES)
    }

    @Test
    fun statesWithoutRunningMediaAreNotChecked() {
        // Connected above all: SDES reads None there until the streams start,
        // and StreamsRunning always follows before any audio.
        assertFalse(MediaSecurity.checksMedia(Call.State.Connected))
        assertEquals(MediaSecurity.Verdict.ALLOW, MediaSecurity.verdict(Call.State.Connected, MediaEncryption.None))
        for (s in Call.State.values().filter { it !in checked }) {
            assertEquals(MediaSecurity.Verdict.ALLOW, MediaSecurity.verdict(s, MediaEncryption.None), s.name)
            assertEquals(MediaSecurity.Verdict.ALLOW, MediaSecurity.verdict(s, null), s.name)
        }
    }

    @Test
    fun aRefusedTerminateEndsEveryCall() {
        var all = 0
        assertEquals(MediaSecurity.Ending.TERMINATED, MediaSecurity.endInsecure({ 0 }, { all++; 0 }))
        assertEquals(0, all, "every call is ended only if the one call cannot be")
        assertEquals(MediaSecurity.Ending.ALL_TERMINATED, MediaSecurity.endInsecure({ -1 }, { all++; 0 }))
        assertEquals(1, all)
        assertEquals(MediaSecurity.Ending.FAILED, MediaSecurity.endInsecure({ -1 }, { -1 }))
    }

    private fun facts(
        incoming: Boolean,
        connected: Boolean = false,
        intent: Mapping.LocalIntent? = null,
        state: Call.State = Call.State.Error,
        reason: Reason? = null,
        code: Int = 0,
    ) = Mapping.EndFacts(incoming, connected, intent, state, null, reason, "SIP", code)

    @Test
    fun anRtpOnlyOfferRefusedWith488IsFailed() {
        // Incoming INVITE without crypto: liblinphone (mandatory) answers 488.
        assertEquals(EndReasonMsg.FAILED, Mapping.endReason(facts(incoming = true, reason = Reason.NotAcceptable)))
        assertEquals(EndReasonMsg.FAILED, Mapping.endReason(facts(incoming = true, state = Call.State.End, code = 488)))
        // Our SRTP-only offer refused by the far end.
        assertEquals(EndReasonMsg.FAILED, Mapping.endReason(facts(incoming = false, code = 488)))
    }

    @Test
    fun aCallEndedForPlainMediaIsFailedNotLocal() {
        val f = facts(incoming = false, connected = true, intent = Mapping.LocalIntent.INSECURE_MEDIA, state = Call.State.End)
        assertEquals(EndReasonMsg.FAILED, Mapping.endReason(f))
    }

    private val engine = File("src/main/kotlin/au/com/voiceplatform/vp_linphone/LinphoneEngine.kt").readText()

    @Test
    fun theEngineAppliesThePolicyToTheCoreAndEveryCall() {
        assertTrue("MediaSecurity.applyToCore(CoreEncryption(c))" in engine)
        // call() and answer() both set the call's params and check the Core.
        assertEquals(2, Regex("""MediaSecurity\.applyToCall\(CallEncryption\(params\)\)""").findAll(engine).count())
        assertEquals(2, Regex("""requireSrtpOnly\(c\)""").findAll(engine).count())
        assertTrue("MediaSecurity.verdict(state, encryption)" in engine)
    }

    @Test
    fun theEngineKeepsCheckingAndEscalatesUntilTheCallHasEnded() {
        // Every state is checked, also after the engine asked for the end:
        // no guard on INSECURE_MEDIA turns the check off.
        assertTrue("if (endIfInsecure(t, state)) return" in engine)
        assertFalse(Regex("""intent\s*!=\s*Mapping\.LocalIntent\.INSECURE_MEDIA""").containsMatchIn(engine))
        // A refused terminate() ends every call, then retries.
        assertTrue("terminateAll = { core?.terminateAllCalls() ?: -1 }" in engine)
        assertTrue("MediaSecurity.Ending.FAILED ->" in engine)
        assertTrue(Regex("""main\.postDelayed\(\{[^}]*endIfInsecure\(t, now\)""").containsMatchIn(engine))
    }

    @Test
    fun nothingInThePluginTurnsEncryptionOffOrOptional() {
        val sources = File("src/main/kotlin").walk().filter { it.isFile && it.extension == "kt" }
        for (f in sources) {
            val text = f.readText()
            assertFalse("setMediaEncryptionMandatory(false)" in text, f.name)
            assertFalse("MediaEncryption.None" in text, f.name)
            assertFalse(Regex("""(isCapabilityNegociationEnabled|isCapabilityNegotiationsEnabled)\s*=\s*true""").containsMatchIn(text), f.name)
        }
    }
}
