package au.com.voiceplatform.vp_linphone

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class HeadlessCoreTest {

    private var now = 0L
    private val timers = mutableListOf<Triple<Long, () -> Unit, BooleanArray>>()
    private val steps = mutableListOf<String>()

    /** Calls ringing on the Core, and whether one is answered or connected. */
    private var ringing = 0
    private var connected = false

    private val scheduler = Scheduler { delay, task ->
        val cancelled = booleanArrayOf(false)
        timers += Triple(now + delay, task, cancelled)
        Cancellable { cancelled[0] = true }
    }

    /** Runs due timers in time order; a timer set by another runs from that one's time. */
    private fun advance(ms: Long) {
        val until = now + ms
        while (true) {
            val due = timers.filter { it.first <= until && !it.third[0] }.minByOrNull { it.first } ?: break
            timers.remove(due)
            now = due.first
            due.second()
        }
        now = until
    }

    private val core = HeadlessCore(
        scheduler,
        object : HeadlessCore.Actions {
            override fun stopCore() {
                steps += "stop"
            }
            override fun declineCalls() {
                // Only calls still ringing are declined.
                if (ringing == 0) return
                ringing = 0
                steps += "decline 480"
            }
            override fun hasConnectedCall() = connected
            override fun log(message: String) {}
        },
    )

    private fun ring() {
        ringing++
        core.onIncomingCall(serviceUp = false)
    }

    private fun answer() {
        ringing--
        connected = true
        core.onCallAnswered()
    }

    private fun endCall() {
        ringing = 0
        connected = false
        core.onLastCallEnded()
    }

    @Test
    fun theJobsCoreStopsWhenTheJobEndsWithTheEngineStopped() {
        core.onCoreCreated()
        core.onJobEnded(engineStopped = true, liveCall = false)
        assertEquals(listOf("stop"), steps)
        assertFalse(core.owned)
    }

    @Test
    fun aServiceThatIsStartingKeepsTheCoreItsPushNeeds() {
        // The push wake is starting the service when the job's REGISTER completes.
        core.onCoreCreated()
        core.onJobEnded(engineStopped = false, liveCall = false)
        assertEquals(emptyList(), steps)
        assertFalse(core.owned, "the service's lifecycle decides from now on")
        assertTrue(core.serviceMayStopCore())
    }

    @Test
    fun aServiceThatTookTheCoreOverOwnsIt() {
        core.onCoreCreated()
        core.onServiceTookOver()
        core.onJobEnded(engineStopped = true, liveCall = false)
        core.onLastCallEnded()
        assertEquals(emptyList(), steps)
        assertTrue(core.serviceMayStopCore())
    }

    @Test
    fun aServiceDestroyedBeforeTakingTheCoreOverLeavesItToTheJob() {
        // call_cancelled while the service was starting: it stops without the Core.
        core.onCoreCreated()
        assertFalse(core.serviceMayStopCore())
        core.onJobEnded(engineStopped = true, liveCall = false)
        assertEquals(listOf("stop"), steps)
    }

    @Test
    fun aCallWaitsForThePushStartedServiceToTakeItOver() {
        core.onCoreCreated()
        ring()
        advance(HeadlessCore.TAKEOVER_MS - 1)
        core.onServiceTookOver()
        advance(HeadlessCore.TAKEOVER_MS)
        assertEquals(emptyList(), steps)
    }

    @Test
    fun aCallNoServiceTakesOverIsDeclinedAndTheCoreStops() {
        core.onCoreCreated()
        ring()
        advance(HeadlessCore.TAKEOVER_MS - 1)
        assertEquals(emptyList(), steps)
        advance(1)
        assertEquals(listOf("decline 480"), steps)
        // The call ends (the 480 went out): the Core stops at once.
        endCall()
        assertEquals(listOf("decline 480", "stop"), steps)
        advance(HeadlessCore.DECLINE_FLUSH_MS)
        assertEquals(listOf("decline 480", "stop"), steps, "stopped once")
    }

    @Test
    fun theCoreStopsAfterTheDeclineEvenIfTheCallNeverEnds() {
        core.onCoreCreated()
        ring()
        advance(HeadlessCore.TAKEOVER_MS + HeadlessCore.DECLINE_FLUSH_MS)
        assertEquals(listOf("decline 480", "stop"), steps)
    }

    @Test
    fun aCallOnTheCoreKeepsItAfterTheJobUntilTheCallEnds() {
        core.onCoreCreated()
        ring()
        core.onJobEnded(engineStopped = true, liveCall = true)
        assertEquals(emptyList(), steps)
        endCall()
        assertEquals(listOf("stop"), steps)
        advance(HeadlessCore.TAKEOVER_MS + HeadlessCore.DECLINE_FLUSH_MS)
        assertEquals(listOf("stop"), steps, "no decline after the Core stopped")
    }

    @Test
    fun aCallThatEndsWhileTheJobStillRunsLeavesTheCoreToTheJob() {
        core.onCoreCreated()
        ring()
        endCall()
        assertEquals(emptyList(), steps)
        core.onJobEnded(engineStopped = true, liveCall = false)
        assertEquals(listOf("stop"), steps)
    }

    @Test
    fun withAServiceUpOrNoJobCoreNothingWaits() {
        core.onIncomingCall(serviceUp = false)
        core.onCoreCreated()
        core.onIncomingCall(serviceUp = true)
        advance(HeadlessCore.TAKEOVER_MS * 2)
        assertEquals(emptyList(), steps)
    }

    @Test
    fun anAnsweredCallIsNeitherDeclinedNorEndedByTheTimers() {
        // WS6: answered at 5 s, the old timers ended the call at about 12 s.
        core.onCoreCreated()
        ring()
        advance(5_000)
        answer()
        advance(HeadlessCore.TAKEOVER_MS + HeadlessCore.DECLINE_FLUSH_MS + 60_000)
        assertEquals(emptyList(), steps)
        assertTrue(core.owned, "until the service the answer started takes it over")
        core.onServiceTookOver()
        assertFalse(core.owned)
    }

    @Test
    fun aConnectedCallKeepsTheCoreThroughTheJobsEnd() {
        core.onCoreCreated()
        ring()
        answer()
        core.onJobEnded(engineStopped = true, liveCall = true)
        assertEquals(emptyList(), steps)
        endCall()
        assertEquals(listOf("stop"), steps)
    }

    @Test
    fun noReleaseWhileACallIsConnected() {
        core.onCoreCreated()
        ring()
        advance(HeadlessCore.TAKEOVER_MS)
        assertEquals(listOf("decline 480"), steps)
        // Another call on the Core is answered before the 2 s release.
        connected = true
        advance(HeadlessCore.DECLINE_FLUSH_MS)
        core.onJobEnded(engineStopped = true, liveCall = false)
        assertEquals(listOf("decline 480"), steps)
        endCall()
        assertEquals(listOf("decline 480", "stop"), steps)
    }

    @Test
    fun aReleaseDeclinesRingingCallsWith480BeforeTheStop() {
        // A bare stop could end them with a 603 and stop the edge trying other devices.
        core.onCoreCreated()
        ring()
        advance(HeadlessCore.TAKEOVER_MS)
        ringing = 1 // a second call rings while the first's 480 goes out
        advance(HeadlessCore.DECLINE_FLUSH_MS)
        assertEquals(listOf("decline 480", "decline 480", "stop"), steps)
    }

    @Test
    fun theJobEndingWithACallStillRingingKeepsTheCore() {
        core.onCoreCreated()
        ring()
        core.onJobEnded(engineStopped = true, liveCall = true)
        assertEquals(emptyList(), steps)
        advance(HeadlessCore.TAKEOVER_MS + HeadlessCore.DECLINE_FLUSH_MS)
        assertEquals(listOf("decline 480", "stop"), steps)
    }
}
