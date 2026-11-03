package au.com.voiceplatform.vp_linphone

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class HeadlessCoreTest {

    private var now = 0L
    private val timers = mutableListOf<Triple<Long, () -> Unit, BooleanArray>>()
    private val steps = mutableListOf<String>()

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
                steps += "decline 480"
            }
            override fun log(message: String) {}
        },
    )

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
        core.onIncomingCall(serviceUp = false)
        advance(HeadlessCore.TAKEOVER_MS - 1)
        core.onServiceTookOver()
        advance(HeadlessCore.TAKEOVER_MS)
        assertEquals(emptyList(), steps)
    }

    @Test
    fun aCallNoServiceTakesOverIsDeclinedAndTheCoreStops() {
        core.onCoreCreated()
        core.onIncomingCall(serviceUp = false)
        advance(HeadlessCore.TAKEOVER_MS - 1)
        assertEquals(emptyList(), steps)
        advance(1)
        assertEquals(listOf("decline 480"), steps)
        // The call ends (the 480 went out): the Core stops at once.
        core.onLastCallEnded()
        assertEquals(listOf("decline 480", "stop"), steps)
        advance(HeadlessCore.DECLINE_FLUSH_MS)
        assertEquals(listOf("decline 480", "stop"), steps, "stopped once")
    }

    @Test
    fun theCoreStopsAfterTheDeclineEvenIfTheCallNeverEnds() {
        core.onCoreCreated()
        core.onIncomingCall(serviceUp = false)
        advance(HeadlessCore.TAKEOVER_MS + HeadlessCore.DECLINE_FLUSH_MS)
        assertEquals(listOf("decline 480", "stop"), steps)
    }

    @Test
    fun aCallOnTheCoreKeepsItAfterTheJobUntilTheCallEnds() {
        core.onCoreCreated()
        core.onIncomingCall(serviceUp = false)
        core.onJobEnded(engineStopped = true, liveCall = true)
        assertEquals(emptyList(), steps)
        core.onLastCallEnded()
        assertEquals(listOf("stop"), steps)
        advance(HeadlessCore.TAKEOVER_MS + HeadlessCore.DECLINE_FLUSH_MS)
        assertEquals(listOf("stop"), steps, "no decline after the Core stopped")
    }

    @Test
    fun aCallThatEndsWhileTheJobStillRunsLeavesTheCoreToTheJob() {
        core.onCoreCreated()
        core.onIncomingCall(serviceUp = false)
        core.onLastCallEnded()
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
}
