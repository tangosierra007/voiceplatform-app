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
    fun theIncomingNotificationAlwaysHasAnswerAndDeclineAndIsACall() {
        // The only inputs are how it sounds; nothing turns Answer off.
        for (silent in listOf(false, true)) {
            for (waiting in listOf(false, true)) {
                val s = IncomingSpec.spec(silent, waiting)
                val at = "silent=$silent waiting=$waiting"
                assertEquals(listOf(IncomingSpec.Button.DECLINE, IncomingSpec.Button.ANSWER), s.buttons, at)
                assertEquals("call", s.category, at)
                // Always set: if Android refuses it, it shows the same notification as a sticky heads-up.
                assertTrue(s.fullScreenIntent, at)
                assertTrue(s.publicOnLockScreen, at)
                assertTrue(s.ongoing, at)
            }
        }
    }

    @Test
    fun ringingSilencedAndWaitingSoundDifferent() {
        assertEquals(IncomingSpec.CHANNEL_RING, IncomingSpec.spec(silent = false, waiting = false).channel)
        assertTrue(IncomingSpec.spec(silent = false, waiting = false).insistent)
        assertFalse(IncomingSpec.spec(silent = false, waiting = false).waitingTone)
        assertEquals(IncomingSpec.CHANNEL_SILENT, IncomingSpec.spec(silent = true, waiting = false).channel)
        assertFalse(IncomingSpec.spec(silent = true, waiting = false).insistent)
        // A second call while one is up: no insistent ringtone over the call, one waiting tone.
        val w = IncomingSpec.spec(silent = false, waiting = true)
        assertEquals(IncomingSpec.CHANNEL_WAITING, w.channel)
        assertFalse(w.insistent)
        assertTrue(w.waitingTone)
        assertFalse(IncomingSpec.spec(silent = true, waiting = true).waitingTone)
    }

    @Test
    fun theAppStateAndFullScreenAccessCannotChangeTheNotification() {
        // They are not inputs of the spec: show() passes only the sound inputs.
        val show = notifier.substringAfter("fun show(").substringBefore("fun silence(")
        assertTrue("val spec = IncomingSpec.spec(silent, isWaiting)" in show)
        assertEquals(1, Regex("""IncomingSpec\.spec\(""").findAll(notifier).count())
        val specParams = File("src/main/kotlin/au/com/voiceplatform/vp_linphone/IncomingSpec.kt").readText()
            .substringAfter("fun spec(").substringBefore(")")
        assertEquals("silent: Boolean, waiting: Boolean", specParams)
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
        assertEquals(3, Regex("""NotificationManager\.IMPORTANCE_HIGH""").findAll(channels).count())
        assertEquals(3, Regex("""lockscreenVisibility = Notification\.VISIBILITY_PUBLIC""").findAll(channels).count())
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
        assertTrue("startForeground(ring.first, ring.second, mic)" in service)
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

    // ---- follow-ups (WS6)

    @Test
    fun theCallScreenShowsOverTheLockScreenWhileTheCallIsLive() {
        val show = UiRequestKindMsg.SHOW_CALL
        val incoming = UiRequestKindMsg.SHOW_INCOMING
        // After Answer from the locked phone: the call is still INCOMING, then CONNECTED.
        for (s in CallStateMsg.values().filter { it != CallStateMsg.ENDED }) {
            assertTrue(LockScreenPolicy.showOverLock(show, s), s.name)
        }
        assertFalse(LockScreenPolicy.showOverLock(show, CallStateMsg.ENDED))
        assertFalse(LockScreenPolicy.showOverLock(show, null))
        // The incoming screen only while that call rings.
        assertTrue(LockScreenPolicy.showOverLock(incoming, CallStateMsg.INCOMING))
        for (s in CallStateMsg.values().filter { it != CallStateMsg.INCOMING }) {
            assertFalse(LockScreenPolicy.showOverLock(incoming, s), s.name)
        }
        assertFalse(LockScreenPolicy.showOverLock(incoming, null))
        val plugin = src("VpLinphonePlugin.kt")
        assertTrue("LockScreenPolicy.showOverLock(request.kind, LinphoneEngine.callState(request.callId))" in plugin)
        // Cleared when the last call ends.
        assertTrue("if (call.state == CallStateMsg.ENDED && !LinphoneEngine.hasLiveCall) showOverLock(false)" in plugin)
    }

    @Test
    fun aRefusedForegroundFallsBackInsteadOfThrowing() {
        val tried = mutableListOf<Boolean>()
        // Microphone refused: phoneCall only.
        assertEquals(
            ServiceNotice.Shown.PLAIN,
            ServiceNotice.show(true) { mic -> tried += mic; if (mic) throw SecurityException("mic") },
        )
        assertEquals(listOf(true, false), tried)
        // Even the plain type refused: reported, never thrown.
        tried.clear()
        assertEquals(ServiceNotice.Shown.FAILED, ServiceNotice.show(true) { mic -> tried += mic; throw IllegalStateException("no") })
        assertEquals(listOf(true, false), tried)
        assertEquals(ServiceNotice.Shown.FAILED, ServiceNotice.show(false) { throw IllegalStateException("no") })
        assertEquals(ServiceNotice.Shown.WITH_MICROPHONE, ServiceNotice.show(true) { })
        assertEquals(ServiceNotice.Shown.PLAIN, ServiceNotice.show(false) { })
        // ring() then returns false, and the notifier posts the notification itself.
        val service = src("EngineService.kt")
        assertTrue("if (!apply()) return false" in service)
        assertTrue("if (result == ServiceNotice.Shown.FAILED)" in service)
        assertTrue("apply(strict = true)" in service, "only the service start throws")
        val show = notifier.substringAfter("fun show(").substringBefore("fun silence(")
        assertTrue(show.indexOf("ringHost?.ring(") < show.indexOf("NotificationManagerCompat.from(context).notify(id, n)"))
    }

    @Test
    fun aWaitingCallIsQuietAndRingsOnceAlone() {
        assertTrue("val isWaiting = LinphoneEngine.hasOtherCallUp(info.callId)" in notifier)
        assertTrue("if (spec.waitingTone && firstWait) playWaitingTone()" in notifier)
        assertTrue("ToneGenerator.TONE_SUP_CALL_WAITING" in notifier)
        val channels = notifier.substringAfter("private fun channels(").substringBefore("private fun activityIntent(")
        assertTrue("waiting.setSound(null, null)" in channels)
        assertTrue("waiting.enableVibration(false)" in channels)
        // When the other call ends, the waiting one rings like any incoming call.
        val engine = src("LinphoneEngine.kt")
        val emit = engine.substringAfter("private fun emitCall(").substringBefore("private fun onCallState(")
        assertTrue("if (msg.state == CallStateMsg.ENDED) appContext?.let { IncomingCallNotifier.ringWaitingCalls(it) }" in emit)
    }

    @Test
    fun answeringKeepsCallInProgressWhileTheNotificationGoes() {
        val answering = listOf(ServiceNotice.Call("a", true, CallStateMsg.INCOMING, answering = true))
        // The notification is already gone (unring), the call not yet CONNECTED.
        assertEquals(ServiceNotice.Notice(ServiceNotice.Kind.IN_CALL, microphone = true), ServiceNotice.decide(answering, true, emptySet()))
        val bridge = src("TelecomBridge.kt")
        val answer = bridge.substringAfter("fun answerFromNotification(").substringBefore("fun declineFromNotification(")
        assertTrue(answer.indexOf("LinphoneEngine.markAnswering(callId)") < answer.indexOf("IncomingCallNotifier.cancel(context, callId)"))
        // If the answer fails, the call shows as ringing again: see aFailedAnswerShowsTheCallRingingAgain.
    }

    @Test
    fun aFailedAnswerShowsTheCallRingingAgain() {
        // Answer from the notification, then the answer fails (microphone denied):
        // the call still rings, so its notification comes back...
        assertTrue(ServiceNotice.reshowAfterFailedAnswer(wasAnswering = true, state = CallStateMsg.INCOMING))
        // ...but not for a call that has moved on, or an in-app Answer (the notification is still up).
        assertFalse(ServiceNotice.reshowAfterFailedAnswer(true, CallStateMsg.ENDED))
        assertFalse(ServiceNotice.reshowAfterFailedAnswer(true, CallStateMsg.CONNECTED))
        assertFalse(ServiceNotice.reshowAfterFailedAnswer(false, CallStateMsg.INCOMING))
        // Shown again and no longer answering, the service shows it as the ringing call,
        // not "Ready for calls" and not "Call in progress".
        val ringingAgain = listOf(ServiceNotice.Call("a", true, CallStateMsg.INCOMING, answering = false))
        assertEquals(ServiceNotice.Notice(ServiceNotice.Kind.INCOMING, "a"), ServiceNotice.decide(ringingAgain, true, setOf("a")))
        // The engine does exactly that in answer()'s catch, before rethrowing.
        val engine = src("LinphoneEngine.kt")
        val catchBlock = engine.substringAfter("    fun answer(callId: String) {").substringBefore("    fun decline(")
            .substringAfter("} catch (e: Throwable) {")
        val reshow = catchBlock.indexOf("val reshow = ServiceNotice.reshowAfterFailedAnswer(t.answering, t.state)")
        val off = catchBlock.indexOf("t.answering = false")
        val show = catchBlock.indexOf("if (reshow) appContext?.let { IncomingCallNotifier.show(it, incomingInfo(t)) }")
        assertTrue(reshow in 0 until off && off < show && show < catchBlock.indexOf("throw e"))
    }

    @Test
    fun stoppingTheEngineEndsEveryCallSoTheLockScreenFlagClears() {
        val engine = src("LinphoneEngine.kt")
        val stop = engine.substringAfter("private fun stopCore()").substringBefore("private fun endTrackedCalls()")
        // Each call not yet ended is sent as ENDED before the calls are forgotten.
        assertTrue(stop.indexOf("endTrackedCalls()") in 0 until stop.indexOf("calls.clear()"))
        // Waiting calls are forgotten first: ending the others must not make one ring (WS6).
        assertTrue(stop.indexOf("IncomingCallNotifier.reset()") in 0 until stop.indexOf("endTrackedCalls()"))
        val end = engine.substringAfter("private fun endTrackedCalls()").substringBefore("private fun incomingInfo(")
        assertTrue("t.state = CallStateMsg.ENDED" in end && "emitCall(t)" in end)
        // The plugin clears the flag on ENDED with no live call, and on stop().
        val plugin = src("VpLinphonePlugin.kt")
        assertTrue("if (call.state == CallStateMsg.ENDED && !LinphoneEngine.hasLiveCall) showOverLock(false)" in plugin)
        val stopFn = plugin.substringAfter("override suspend fun stop()").substringBefore("override fun register(")
        assertTrue("showOverLock(false)" in stopFn)
        val unreg = plugin.substringAfter("override suspend fun unregister()").substringBefore("override fun updatePush(")
        assertTrue("if (!LinphoneEngine.hasLiveCall) showOverLock(false)" in unreg)
    }

    @Test
    fun theWaitingToneIsPlayedOncePerWaitingCall() {
        val show = notifier.substringAfter("fun show(").substringBefore("fun silence(")
        assertTrue("val firstWait = if (isWaiting) waitingCalls.put(info.callId, info) == null else false" in show)
        assertTrue("if (spec.waitingTone && firstWait) playWaitingTone()" in show)
        assertTrue("waitingCalls.clear()" in notifier.substringAfter("fun reset()"))
    }
}
