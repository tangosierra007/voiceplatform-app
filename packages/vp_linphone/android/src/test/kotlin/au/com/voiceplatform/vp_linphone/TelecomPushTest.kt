package au.com.voiceplatform.vp_linphone

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class ConnectionMachineTest {

    @Test
    fun incomingRingsThenAnswersFromTheSystem() {
        val m = ConnectionMachine("call-1", incoming = true)
        assertEquals(TelecomAction.SetState(TelecomState.RINGING), m.onEngine(CallStateMsg.INCOMING, null))
        assertEquals(EngineCommand.Answer("call-1"), m.onUser(UserEvent.Answer))
        assertEquals(TelecomAction.SetState(TelecomState.ACTIVE), m.onEngine(CallStateMsg.CONNECTED, null))
        // A late "incoming" snapshot never takes it back to ringing.
        assertNull(m.onEngine(CallStateMsg.INCOMING, null))
        assertNull(m.onUser(UserEvent.Answer))
    }

    @Test
    fun rejectAndHeadsetHangupWhileRingingAreDeclines() {
        val m = ConnectionMachine("call-1", incoming = true)
        m.onEngine(CallStateMsg.INCOMING, null)
        assertEquals(EngineCommand.Decline("call-1"), m.onUser(UserEvent.Reject))
        assertEquals(EngineCommand.Decline("call-1"), m.onUser(UserEvent.Disconnect))
        assertEquals(
            TelecomAction.Disconnect(DisconnectKind.REJECTED),
            m.onEngine(CallStateMsg.ENDED, EndReasonMsg.DECLINED),
        )
    }

    @Test
    fun answeredElsewhereClearsTheConnectionWithItsOwnCause() {
        val m = ConnectionMachine("call-1", incoming = true)
        m.onEngine(CallStateMsg.INCOMING, null)
        assertEquals(
            TelecomAction.Disconnect(DisconnectKind.ANSWERED_ELSEWHERE),
            m.onEngine(CallStateMsg.ENDED, EndReasonMsg.ANSWERED_ELSEWHERE),
        )
        assertEquals(TelecomState.DISCONNECTED, m.state)
        // Terminal: nothing after it.
        assertNull(m.onEngine(CallStateMsg.CONNECTED, null))
        assertNull(m.onUser(UserEvent.Disconnect))
    }

    @Test
    fun outgoingDialsHoldsResumesSendsDtmfAndHangsUp() {
        val m = ConnectionMachine("call-2", incoming = false)
        assertEquals(TelecomAction.SetState(TelecomState.DIALING), m.onEngine(CallStateMsg.DIALLING, null))
        assertNull(m.onEngine(CallStateMsg.RINGING, null)) // still dialing for Telecom
        assertNull(m.onUser(UserEvent.Hold))
        m.onEngine(CallStateMsg.CONNECTED, null)
        assertEquals(EngineCommand.Dtmf("call-2", "5"), m.onUser(UserEvent.Dtmf('5')))
        assertNull(m.onUser(UserEvent.Dtmf('x')))
        assertEquals(EngineCommand.Hold("call-2"), m.onUser(UserEvent.Hold))
        assertEquals(TelecomAction.SetState(TelecomState.HOLDING), m.onEngine(CallStateMsg.HELD_BY_ME, null))
        assertEquals(EngineCommand.Resume("call-2"), m.onUser(UserEvent.Unhold))
        m.onEngine(CallStateMsg.CONNECTED, null)
        assertNull(m.onEngine(CallStateMsg.HELD_BY_REMOTE, null)) // remote hold: still active here
        assertEquals(EngineCommand.Hangup("call-2"), m.onUser(UserEvent.Disconnect))
        assertEquals(TelecomAction.Disconnect(DisconnectKind.LOCAL), m.onEngine(CallStateMsg.ENDED, EndReasonMsg.LOCAL))
    }

    @Test
    fun disconnectCauses() {
        assertEquals(DisconnectKind.MISSED, ConnectionMachine.disconnect(EndReasonMsg.REMOTE, incoming = true, wasActive = false))
        assertEquals(DisconnectKind.REMOTE, ConnectionMachine.disconnect(EndReasonMsg.REMOTE, incoming = true, wasActive = true))
        assertEquals(DisconnectKind.BUSY, ConnectionMachine.disconnect(EndReasonMsg.BUSY, incoming = false, wasActive = false))
        assertEquals(DisconnectKind.REJECTED, ConnectionMachine.disconnect(EndReasonMsg.TO_VOICEMAIL, incoming = true, wasActive = false))
        assertEquals(DisconnectKind.ERROR, ConnectionMachine.disconnect(EndReasonMsg.NETWORK_LOST, incoming = false, wasActive = true))
        for (r in EndReasonMsg.values()) ConnectionMachine.disconnect(r, true, false) // exhaustive, no throw
    }
}

class PushHandlerTest {
    private var now = 1_000_000L
    private var wall = 1_793_000_000_000L
    private val timers = mutableListOf<Pair<Long, () -> Unit>>()
    private val calls = mutableListOf<String>()
    private var liveCall = false
    private val delivered = mutableListOf<PushHandler.PushData>()
    private val lateTimes = mutableListOf<Long>()

    private val wakeLog = WakeLog(object : WakeLog.Store {
        override fun load() = lateTimes.toList()
        override fun save(times: List<Long>) {
            lateTimes.clear()
            lateTimes += times
        }
    })

    private val handler = PushHandler(
        clock = { now },
        wallClock = { wall },
        scheduler = { delay, task ->
            val entry = (now + delay) to task
            timers += entry
            Cancellable { timers.remove(entry) }
        },
        actions = object : PushHandler.Actions {
            override fun wakeAndRegister() {
                calls += "wake"
            }
            override fun sleep() {
                calls += "sleep"
            }
            override fun hasLiveCall() = liveCall
            override fun signOut() {
                calls += "signOut"
            }
            override fun deliver(push: PushHandler.PushData) {
                calls += "deliver ${push.type}"
                delivered += push
            }
        },
        wakeLog = wakeLog,
    )

    private fun advance(ms: Long) {
        now += ms
        wall += ms
        val due = timers.filter { it.first <= now }
        timers.removeAll(due)
        due.forEach { it.second() }
    }

    private fun msg(type: String, id: String, sentAt: String? = null) =
        mapOf("type" to type, "pushId" to id, "sentAt" to sentAt)

    @Test
    fun incomingCallWakesAndRegistersOnce() {
        assertTrue(handler.onMessage(msg("incoming_call", "p1")))
        assertTrue(handler.onMessage(msg("incoming_call", "p1"))) // duplicate
        assertEquals(listOf("wake"), calls)
        assertTrue(handler.wakeInProgress)
    }

    @Test
    fun registrationInsideTheBudgetIsNotLate() {
        handler.onMessage(msg("incoming_call", "p1"))
        advance(3_000)
        handler.onRegistered()
        assertEquals(0, wakeLog.lateInLastWeek(wall))
    }

    @Test
    fun registrationAfterEightSecondsIsRecordedLate() {
        handler.onMessage(msg("incoming_call", "p1"))
        advance(8_500)
        handler.onRegistered()
        handler.onRegistered() // once per wake
        assertEquals(1, wakeLog.lateInLastWeek(wall))
        assertEquals(8_500, wakeLog.lastLate?.sinceReceiptMs)
    }

    @Test
    fun sentAtCountsFcmDeliveryDelay() {
        // Sent 7 s before it arrived, registered 2 s later: 9 s since sentAt.
        val sent = java.time.Instant.ofEpochMilli(wall - 7_000).toString()
        handler.onMessage(msg("incoming_call", "p1", sent))
        advance(2_000)
        handler.onRegistered()
        assertEquals(1, wakeLog.lateInLastWeek(wall))
        assertEquals(9_000, wakeLog.lastLate?.sinceSentMs)
    }

    @Test
    fun callCancelledStopsTheWakeAtOnce() {
        handler.onMessage(msg("incoming_call", "p1"))
        advance(500)
        handler.onMessage(msg("call_cancelled", "p2"))
        assertEquals(listOf("wake", "sleep"), calls)
        assertFalse(handler.wakeInProgress)
        advance(PushHandler.IDLE_WAKE_MS) // the idle timer was cancelled
        assertEquals(listOf("wake", "sleep"), calls)
    }

    @Test
    fun callCancelledLeavesALiveCallAlone() {
        handler.onMessage(msg("incoming_call", "p1"))
        liveCall = true
        handler.onMessage(msg("call_cancelled", "p2"))
        assertEquals(listOf("wake"), calls)
    }

    @Test
    fun noInviteWithinTheIdleTimeGoesBackToSleep() {
        handler.onMessage(msg("incoming_call", "p1"))
        advance(PushHandler.IDLE_WAKE_MS - 1)
        assertEquals(listOf("wake"), calls)
        advance(1)
        assertEquals(listOf("wake", "sleep"), calls)
    }

    @Test
    fun anArrivedCallEndsThePushWake() {
        handler.onMessage(msg("incoming_call", "p1"))
        handler.onCallArrived()
        advance(PushHandler.IDLE_WAKE_MS)
        assertEquals(listOf("wake"), calls)
    }

    @Test
    fun otherTypesGoToTheAppAndUnknownsAreNotOurs() {
        for ((i, t) in listOf("voicemail", "message", "signed_out", "config").withIndex()) {
            assertTrue(handler.onMessage(msg(t, "x$i", "2026-10-28T00:00:00Z")))
        }
        assertEquals(
            listOf(PushTypeMsg.VOICEMAIL, PushTypeMsg.MESSAGE, PushTypeMsg.SIGNED_OUT, PushTypeMsg.CONFIG),
            delivered.map { it.type },
        )
        assertFalse(handler.onMessage(msg("something_else", "y")))
        assertFalse(handler.onMessage(mapOf("type" to "voicemail")))
        assertEquals(listOf("signOut"), calls.filter { !it.startsWith("deliver") })
    }

    @Test
    fun lateWakesCountOnlyTheLastWeek() {
        val log = WakeLog(object : WakeLog.Store {
            var times = listOf<Long>()
            override fun load() = times
            override fun save(times: List<Long>) {
                this.times = times
            }
        })
        log.recordLate(0, 9_000, null)
        log.recordLate(WakeLog.WEEK_MS + 10, 9_000, null)
        assertEquals(1, log.lateInLastWeek(WakeLog.WEEK_MS + 20))
    }

    @Test
    fun signedOutForgetsTheAccountNativelyThenTellsTheApp() {
        handler.onMessage(msg("incoming_call", "p1"))
        handler.onMessage(msg("signed_out", "p2"))
        assertEquals(listOf("wake", "signOut", "deliver SIGNED_OUT"), calls)
        assertFalse(handler.wakeInProgress)
        advance(PushHandler.IDLE_WAKE_MS) // no stray sleep after
        assertEquals(listOf("wake", "signOut", "deliver SIGNED_OUT"), calls)
    }
}

/** The push handler driving the engine lifecycle, with a fake clock. */
class CancelDuringStartTest {
    private var now = 0L
    private val timers = mutableListOf<Pair<Long, () -> Unit>>()
    private val log = mutableListOf<String>()
    private lateinit var handler: PushHandler

    private val lifecycle = EngineLifecycle(
        startService = { log += "startService" },
        stopService = { log += "stopService" },
    )

    private fun advance(ms: Long) {
        now += ms
        val due = timers.filter { it.first <= now }
        timers.removeAll(due)
        due.forEach { it.second() }
    }

    private fun setUp() {
        handler = PushHandler(
            clock = { now },
            wallClock = { now },
            scheduler = { delay, task ->
                val e = (now + delay) to task
                timers += e
                Cancellable { timers.remove(e) }
            },
            actions = object : PushHandler.Actions {
                override fun wakeAndRegister() {
                    // As LinphoneEngine.wakeForPush: register only if the wake is still wanted.
                    lifecycle.requestStart(byApp = false) { error ->
                        if (error == null && (lifecycle.startedByApp || handler.wakeInProgress)) log += "register"
                        else log += "no register (${error?.javaClass?.simpleName ?: "not wanted"})"
                    }
                }
                override fun sleep() {
                    if (!lifecycle.startedByApp) lifecycle.requestStop { log += "stopped" }
                }
                override fun hasLiveCall() = false
                override fun signOut() {}
                override fun deliver(push: PushHandler.PushData) {}
            },
            wakeLog = WakeLog(object : WakeLog.Store {
                override fun load() = emptyList<Long>()
                override fun save(times: List<Long>) {}
            }),
        )
    }

    @Test
    fun cancelWhileTheServiceIsStartingStopsItAndNeverRegisters() {
        setUp()
        handler.onMessage(mapOf("type" to "incoming_call", "pushId" to "p1"))
        assertEquals(EngineLifecycle.State.STARTING, lifecycle.state)
        advance(300)
        handler.onMessage(mapOf("type" to "call_cancelled", "pushId" to "p2"))
        assertEquals(listOf("startService"), log) // stop is held until the service is up
        advance(400)
        // The service reaches the foreground: it must not start the Core.
        assertFalse(lifecycle.onServiceCreated())
        assertEquals(listOf("startService", "no register (StartCancelled)", "stopService"), log)
        lifecycle.onServiceDestroyed()
        assertEquals("stopped", log.last())
        assertEquals(EngineLifecycle.State.STOPPED, lifecycle.state)
    }

    @Test
    fun aNormalWakeRegisters() {
        setUp()
        handler.onMessage(mapOf("type" to "incoming_call", "pushId" to "p1"))
        advance(500)
        assertTrue(lifecycle.onServiceCreated())
        lifecycle.onCoreStarted()
        assertEquals(listOf("startService", "register"), log)
    }

    @Test
    fun theAppStartingMeanwhileWinsOverAPendingStop() {
        setUp()
        handler.onMessage(mapOf("type" to "incoming_call", "pushId" to "p1"))
        handler.onMessage(mapOf("type" to "call_cancelled", "pushId" to "p2"))
        lifecycle.requestStart(byApp = true) { log += "app started ${it?.javaClass?.simpleName ?: "ok"}" }
        assertTrue(lifecycle.onServiceCreated())
        lifecycle.onCoreStarted()
        assertEquals(EngineLifecycle.State.RUNNING, lifecycle.state)
        assertTrue("app started ok" in log)
        assertFalse("stopService" in log)
    }
}

class CallActionGateTest {
    @Test
    fun onlyTheNotificationsTokenActsAndAnswerUsesItUp() {
        var n = 0
        val gate = CallActionGate(random = { "token-${++n}" })
        val t = gate.issue("call-abc")
        assertTrue(gate.authorise(CallActionGate.Action.SHOW_INCOMING, "call-abc", t))
        assertTrue(gate.authorise(CallActionGate.Action.SHOW_INCOMING, "call-abc", t)) // showing again is fine
        assertTrue(gate.authorise(CallActionGate.Action.ANSWER, "call-abc", t))
        assertFalse(gate.authorise(CallActionGate.Action.ANSWER, "call-abc", t)) // once
    }

    @Test
    fun anExternalIntentWithAValidLookingIdDoesNothing() {
        val gate = CallActionGate()
        val t = gate.issue("call-abc")
        assertFalse(gate.authorise(CallActionGate.Action.ANSWER, "call-abc", null))
        assertFalse(gate.authorise(CallActionGate.Action.ANSWER, "call-abc", "guess"))
        assertFalse(gate.authorise(CallActionGate.Action.DECLINE, "call-abc", t.reversed()))
        assertFalse(gate.authorise(CallActionGate.Action.SHOW_INCOMING, "call-xyz", t))
        assertFalse(gate.authorise(CallActionGate.Action.ANSWER, null, t))
        // The real token still works afterwards: failed guesses don't burn it.
        assertTrue(gate.authorise(CallActionGate.Action.DECLINE, "call-abc", t))
    }

    @Test
    fun forgottenCallsHaveNoToken() {
        val gate = CallActionGate()
        val t = gate.issue("call-abc")
        gate.forget("call-abc")
        assertFalse(gate.authorise(CallActionGate.Action.ANSWER, "call-abc", t))
    }

    @Test
    fun callIdsAndTokensAreRandom() {
        val ids = List(200) { CallActionGate.randomCallId() }.toSet()
        assertEquals(200, ids.size)
        assertTrue(ids.all { Regex("^call-[0-9a-f]{16}$").matches(it) })
        assertEquals(32, CallActionGate.randomToken().length)
    }
}
class AccountRecordTest {
    @Test
    fun roundTripsWithAndWithoutPush() {
        val r = AccountRecord(
            "app-abcde12345", "testpasswordtestpassword", "democo.sip.voiceplatform.com.au",
            "sip:sip.voiceplatform.com.au:5061;transport=tls", "Ava: \"N\" 1:2", 600,
            "urn:uuid:0e2f3c4a-5b6c-4d7e-8f90-a1b2c3d4e5f6", "fcm", "tok:en-1", "voiceplatform-app",
        )
        assertEquals(r, AccountRecord.decode(r.encode()))
        val noPush = r.copy(pushProvider = null, pushPrid = null, pushParam = null)
        assertEquals(noPush, AccountRecord.decode(noPush.encode()))
        assertFalse("testpassword" in r.toString())
    }

    @Test
    fun garbageDecodesToNull() {
        assertNull(AccountRecord.decode("nope".toByteArray()))
        assertNull(AccountRecord.decode("v1|3:abc".toByteArray()))
        assertNull(AccountRecord.decode("v1|99:abc".toByteArray()))
    }
}
