package au.com.voiceplatform.vp_linphone

import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/**
 * A locked or backgrounded phone answers from the incoming-call notification,
 * and the engine service shows one notification per call state.
 */
class IncomingCallUiTest {

    // ---- the incoming-call notification

    @Test
    fun theIncomingNotificationHasAnswerAndDeclineAndIsACallInEveryState() {
        for (app in IncomingSpec.AppState.values()) {
            for (fullScreen in listOf(true, false)) {
                for (silent in listOf(false, true)) {
                    val s = IncomingSpec.spec(app, fullScreen, silent)
                    val at = "$app fullScreen=$fullScreen silent=$silent"
                    assertEquals(listOf(IncomingSpec.Button.DECLINE, IncomingSpec.Button.ANSWER), s.buttons, at)
                    assertEquals("call", s.category, at)
                    // The full-screen intent is always set: if Android refuses it,
                    // it shows the same notification as a sticky heads-up.
                    assertTrue(s.fullScreenIntent, at)
                    assertTrue(s.publicOnLockScreen, at)
                    assertTrue(s.ongoing, at)
                    assertEquals(if (silent) IncomingSpec.CHANNEL_SILENT else IncomingSpec.CHANNEL_RING, s.channel, at)
                    assertEquals(!silent, s.insistent, at)
                }
            }
        }
    }

    private fun src(name: String) = File("src/main/kotlin/au/com/voiceplatform/vp_linphone/$name").readText()
    private val notifier = src("IncomingCallNotifier.kt")
    private val build = notifier.substringAfter("internal fun build(").substringBefore("interface RingHost")

    @Test
    fun theNotificationIsBuiltFromTheSpecAlwaysAsCallStyle() {
        assertTrue("NotificationCompat.CallStyle.forIncomingCall(person, decline, answer)" in build)
        assertTrue(".setCategory(spec.category)" in build)
        assertTrue("NotificationCompat.Builder(context, spec.channel)" in build)
        assertTrue("if (spec.fullScreenIntent) b.setFullScreenIntent(content, true)" in build)
        // No fallback without the call style (its plain actions were hidden on the lock screen).
        assertFalse("addAction" in notifier)
        // Whether full-screen is allowed only decides what is reported, not the notification.
        val show = notifier.substringAfter("fun show(").substringBefore("fun silence(")
        assertTrue("val n = build(context, spec, title, person, content, answer, decline)" in show)
        assertFalse(Regex("""if \(fullScreen\)\s*\{[^}]*(setStyle|build\()""").containsMatchIn(show))
        // The ringtone channel is high importance and public on the lock screen.
        val channels = notifier.substringAfter("private fun channels(").substringBefore("fun show(")
        assertEquals(2, Regex("""NotificationManager\.IMPORTANCE_HIGH""").findAll(channels).count())
        assertEquals(2, Regex("""lockscreenVisibility = Notification\.VISIBILITY_PUBLIC""").findAll(channels).count())
    }

    @Test
    fun theNotificationStartsTheAppWithoutABackgroundActivityStart() {
        val intent = notifier.substringAfter("private fun activityIntent(").substringBefore("fun show(")
        // Both activities from the system's PendingIntent: the app's, with the token check on top.
        assertTrue("PendingIntent.getActivities(context, requestCode(callId, action), arrayOf(app, gate), flags)" in intent)
        val gateActivity = src("CallActionActivity.kt")
        assertFalse("startActivity(" in gateActivity, "the trampoline must not start the app from the background")
        assertTrue("PendingUiRequest.post(request)" in gateActivity)
        // An app activity that already exists is put over the lock screen when the request arrives.
        val plugin = src("VpLinphonePlugin.kt")
        assertTrue(Regex("""PendingUiRequest\.listener = \{ request ->\s*(//[^\n]*\s*)*handleIntent\(null\)""").containsMatchIn(plugin))
    }

    // ---- the engine service's notification

    private fun call(id: String, incoming: Boolean, state: CallStateMsg) = ServiceNotice.Call(id, incoming, state)

    @Test
    fun noCallIsReadyForCalls() {
        assertEquals(ServiceNotice.Notice(ServiceNotice.Kind.READY), ServiceNotice.decide(emptyList(), true, emptySet()))
        val ended = listOf(call("a", true, CallStateMsg.ENDED))
        assertEquals(ServiceNotice.Kind.READY, ServiceNotice.decide(ended, true, setOf("a")).kind)
    }

    @Test
    fun aRingingCallIsTheIncomingNotificationNeverCallInProgress() {
        val ringing = listOf(call("a", true, CallStateMsg.INCOMING))
        // Before Telecom asks for the notification: still "Ready", never "Call in progress".
        assertEquals(ServiceNotice.Kind.READY, ServiceNotice.decide(ringing, true, emptySet()).kind)
        // Then the incoming-call notification is the service's own, without the microphone type.
        assertEquals(
            ServiceNotice.Notice(ServiceNotice.Kind.INCOMING, "a", microphone = false),
            ServiceNotice.decide(ringing, true, setOf("a")),
        )
    }

    @Test
    fun callInProgressOnlyOnceACallIsUp() {
        for (s in listOf(CallStateMsg.CONNECTED, CallStateMsg.HELD_BY_ME, CallStateMsg.HELD_BY_REMOTE, CallStateMsg.TRANSFERRING)) {
            val n = ServiceNotice.decide(listOf(call("a", true, s)), micGranted = true, ringing = emptySet())
            assertEquals(ServiceNotice.Notice(ServiceNotice.Kind.IN_CALL, microphone = true), n, s.name)
            assertFalse(ServiceNotice.decide(listOf(call("a", true, s)), false, emptySet()).microphone, s.name)
        }
    }

    @Test
    fun anOutgoingCallNotYetAnsweredIsCalling() {
        for (s in listOf(CallStateMsg.DIALLING, CallStateMsg.RINGING)) {
            assertEquals(
                ServiceNotice.Notice(ServiceNotice.Kind.CALLING),
                ServiceNotice.decide(listOf(call("o", false, s)), true, emptySet()),
                s.name,
            )
        }
    }

    @Test
    fun callWaitingKeepsCallInProgressAndRingsSeparately() {
        val calls = listOf(call("a", false, CallStateMsg.CONNECTED), call("b", true, CallStateMsg.INCOMING))
        assertEquals(ServiceNotice.Kind.IN_CALL, ServiceNotice.decide(calls, true, setOf("b")).kind)
        // The first call ends while the second still rings: it becomes the service's notification.
        val after = listOf(call("a", false, CallStateMsg.ENDED), call("b", true, CallStateMsg.INCOMING))
        assertEquals(ServiceNotice.Notice(ServiceNotice.Kind.INCOMING, "b"), ServiceNotice.decide(after, true, setOf("b")))
    }

    @Test
    fun theServiceAndEngineFollowTheNotice() {
        val service = src("EngineService.kt")
        assertTrue("ServiceNotice.decide(calls, micGranted, ringing.keys)" in service)
        assertTrue("startForeground(ring.first, ring.second, notice.microphone)" in service)
        assertFalse("setInCall" in service)
        val engine = src("LinphoneEngine.kt")
        assertFalse("setInCall" in engine)
        // Every call change updates the service; nothing switches it to "in call" at the first ring.
        val emit = engine.substringAfter("private fun emitCall(").substringBefore("private fun onCallState(")
        assertTrue("updateService()" in emit)
        val first = engine.substringAfter("override fun onFirstCallStarted(").substringBefore("override fun onLastCallEnded(")
        assertTrue("updateService()" in first)
        // The incoming notification goes through the service first, and is removed from it before it's cancelled.
        assertTrue("ringHost?.ring(info.callId, id, n) == true" in notifier)
        val cancel = notifier.substringAfter("fun cancel(").substringBefore("internal fun build(")
        assertTrue(cancel.indexOf("ringHost?.unring(callId)") < cancel.indexOf(".cancel(notificationId(callId))"))
    }
}
