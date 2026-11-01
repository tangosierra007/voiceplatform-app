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
    fun exactlyTheThreeAudioStatesAreCheckedEarlyMediaAfterItsStreamsStart() {
        assertEquals(checked.toSet(), MediaSecurity.CHECKED_STATES)
        assertEquals(MediaSecurity.Check.NOW, MediaSecurity.checkAt(Call.State.StreamsRunning))
        assertEquals(MediaSecurity.Check.NOW, MediaSecurity.checkAt(Call.State.PausedByRemote))
        // liblinphone sets OutgoingEarlyMedia before updateStreams(): SRTP is
        // only in currentParams once the callback has returned.
        assertEquals(MediaSecurity.Check.AFTER_STREAMS_START, MediaSecurity.checkAt(Call.State.OutgoingEarlyMedia))
        for (s in Call.State.values().filter { it !in checked }) {
            assertEquals(MediaSecurity.Check.NONE, MediaSecurity.checkAt(s), s.name)
        }
    }

    /** A main-thread queue: tasks run only when [drain] is called, as after the callback returns. */
    private class Posted {
        val tasks = ArrayDeque<Runnable>()
        val post: (Runnable) -> Unit = { tasks.addLast(it) }
        fun drain() {
            while (tasks.isNotEmpty()) tasks.removeFirst().run()
        }
    }

    @Test
    fun anEarlyMediaCheckRunsOnlyAfterThePost() {
        val q = Posted()
        val judged = mutableListOf<Call.State>()
        var encryption: MediaEncryption? = MediaEncryption.None // the callback's view: streams not started
        var now: Call.State? = Call.State.OutgoingEarlyMedia
        val judge = { s: Call.State ->
            judged += s
            MediaSecurity.verdict(s, encryption) == MediaSecurity.Verdict.END
        }
        // In the callback: nothing judged, the state is shown.
        assertFalse(MediaSecurity.runCheck(Call.State.OutgoingEarlyMedia, q.post, { now }, judge))
        assertTrue(judged.isEmpty())
        assertEquals(1, q.tasks.size)
        // updateStreams() has run: a good SDES call reads SRTP and is kept.
        encryption = MediaEncryption.SRTP
        q.drain()
        assertEquals(listOf(Call.State.OutgoingEarlyMedia), judged)

        // Early media without crypto: still None after the post, so it ends.
        judged.clear()
        encryption = MediaEncryption.None
        var ended = false
        MediaSecurity.runCheck(Call.State.OutgoingEarlyMedia, q.post, { now }) { s ->
            judged += s
            (MediaSecurity.verdict(s, encryption) == MediaSecurity.Verdict.END).also { ended = it }
        }
        assertFalse(ended)
        q.drain()
        assertTrue(ended)

        // The call moved on before the post ran: the later checked state is judged.
        judged.clear()
        MediaSecurity.runCheck(Call.State.OutgoingEarlyMedia, q.post, { now }, judge)
        now = Call.State.StreamsRunning
        q.drain()
        assertEquals(listOf(Call.State.StreamsRunning), judged)

        // Ended or no longer tracked (null), or in an unchecked state: nothing is judged.
        judged.clear()
        for (later in listOf(null, Call.State.OutgoingRinging, Call.State.Connected)) {
            now = Call.State.OutgoingEarlyMedia
            MediaSecurity.runCheck(Call.State.OutgoingEarlyMedia, q.post, { now }, judge)
            now = later
            q.drain()
        }
        assertTrue(judged.isEmpty())
    }

    @Test
    fun runningMediaAndRemoteHoldAreJudgedInTheCallback() {
        val q = Posted()
        for (s in listOf(Call.State.StreamsRunning, Call.State.PausedByRemote)) {
            val judged = mutableListOf<Call.State>()
            assertTrue(MediaSecurity.runCheck(s, q.post, { s }) { judged += it; true }, s.name)
            assertEquals(listOf(s), judged)
            assertTrue(q.tasks.isEmpty(), s.name)
        }
        for (s in listOf(Call.State.Connected, Call.State.OutgoingRinging, Call.State.End)) {
            assertFalse(MediaSecurity.runCheck(s, q.post, { s }) { error("judged $s") }, s.name)
            assertTrue(q.tasks.isEmpty(), s.name)
        }
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
    fun aRefusedTerminateEndsEveryCallUnlessTheCallHasEnded() {
        var all = 0
        var marked = 0
        fun end(term: Int, state: Call.State?, allRc: Int) =
            MediaSecurity.endInsecure({ term }, { state }, { marked++ }, { all++; allRc })

        assertEquals(MediaSecurity.Ending.TERMINATED, end(0, Call.State.StreamsRunning, 0))
        assertEquals(0, all, "every call is ended only if the one call cannot be")
        // Refused, but the call has ended meanwhile (or is gone): no escalation.
        for (s in listOf(Call.State.End, Call.State.Error, Call.State.Released, null)) {
            assertEquals(MediaSecurity.Ending.ALREADY_ENDED, end(-1, s, 0), s.toString())
        }
        assertEquals(0, all)
        assertEquals(0, marked)
        // Refused and still up: the other calls are marked first, then all end.
        assertEquals(MediaSecurity.Ending.ALL_TERMINATED, end(-1, Call.State.StreamsRunning, 0))
        assertEquals(1, marked)
        assertEquals(1, all)
        assertEquals(MediaSecurity.Ending.FAILED, end(-1, Call.State.PausedByRemote, -1))
    }

    @Test
    fun onlyOneRetryIsPendingPerCall() {
        val q = Posted()
        val r = MediaSecurity.Retry()
        var runs = 0
        assertTrue(r.schedule(q.post) { runs++ })
        assertFalse(r.schedule(q.post) { runs++ })
        assertFalse(r.schedule(q.post) { runs++ })
        assertEquals(1, q.tasks.size)
        assertTrue(r.pending)
        q.drain()
        assertEquals(1, runs)
        assertFalse(r.pending)
        // Once it has run, the next one can be scheduled.
        assertTrue(r.schedule(q.post) { runs++ })
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
        // Every state goes through runCheck, also after the engine asked for
        // the end: no guard on INSECURE_MEDIA turns the check off. Posted
        // checks go to the main thread.
        assertTrue("val endingNow = MediaSecurity.runCheck(" in engine)
        assertTrue("post = { r -> main.post(r) }," in engine)
        assertTrue("if (endingNow) return" in engine)
        assertFalse(Regex("""intent\s*!=\s*Mapping\.LocalIntent\.INSECURE_MEDIA""").containsMatchIn(engine))
        // A refused terminate() re-reads the state, marks the other calls
        // failed, ends every call, then retries once per call.
        assertTrue("stateNow = { call.state }," in engine)
        assertTrue(".forEach { it.intent = Mapping.LocalIntent.INSECURE_MEDIA }" in engine)
        assertTrue("terminateAll = { core?.terminateAllCalls() ?: -1 }" in engine)
        assertTrue("val retry = MediaSecurity.Retry()" in engine)
        assertTrue("t.retry.schedule({ r -> main.postDelayed(r, INSECURE_RETRY_MS) })" in engine)
        val endCall = engine.substringAfter("private fun endInsecureCall").substringBefore("private val coreListener")
        assertFalse(Regex("""main\.postDelayed\(\{""").containsMatchIn(endCall), "retries only through Retry")
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
