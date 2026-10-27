package au.com.voiceplatform.vp_linphone

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test
import org.linphone.core.AudioDevice
import org.linphone.core.Call
import org.linphone.core.Reason

class MappingTest {

    @Test
    fun everyLinphoneCallStateIsMapped() {
        for (s in Call.State.values()) Mapping.callState(s) // no exception, exhaustive
        assertEquals(CallStateMsg.INCOMING, Mapping.callState(Call.State.IncomingReceived))
        assertEquals(CallStateMsg.DIALLING, Mapping.callState(Call.State.OutgoingProgress))
        assertEquals(CallStateMsg.RINGING, Mapping.callState(Call.State.OutgoingRinging))
        assertEquals(CallStateMsg.RINGING, Mapping.callState(Call.State.OutgoingEarlyMedia))
        assertEquals(CallStateMsg.CONNECTED, Mapping.callState(Call.State.StreamsRunning))
        assertEquals(CallStateMsg.HELD_BY_ME, Mapping.callState(Call.State.Paused))
        assertEquals(CallStateMsg.HELD_BY_REMOTE, Mapping.callState(Call.State.PausedByRemote))
        assertEquals(CallStateMsg.ENDED, Mapping.callState(Call.State.Error))
        assertNull(Mapping.callState(Call.State.EarlyUpdating))
    }

    private fun facts(
        incoming: Boolean = true,
        connected: Boolean = false,
        intent: Mapping.LocalIntent? = null,
        state: Call.State = Call.State.End,
        status: Call.Status? = null,
        reason: Reason? = null,
        protocol: String? = null,
        code: Int = 0,
    ) = Mapping.EndFacts(incoming, connected, intent, state, status, reason, protocol, code)

    @Test
    fun cancelWithCause200IsAnsweredElsewhere() {
        assertEquals(EndReasonMsg.ANSWERED_ELSEWHERE, Mapping.endReason(facts(protocol = "SIP", code = 200)))
        assertEquals(EndReasonMsg.ANSWERED_ELSEWHERE, Mapping.endReason(facts(status = Call.Status.AcceptedElsewhere)))
        // A plain CANCEL from the caller is the remote ending it.
        assertEquals(EndReasonMsg.REMOTE, Mapping.endReason(facts(status = Call.Status.Missed)))
    }

    @Test
    fun localIntentWins() {
        assertEquals(EndReasonMsg.DECLINED, Mapping.endReason(facts(intent = Mapping.LocalIntent.DECLINE)))
        assertEquals(EndReasonMsg.TO_VOICEMAIL, Mapping.endReason(facts(intent = Mapping.LocalIntent.TO_VOICEMAIL)))
        assertEquals(EndReasonMsg.LOCAL, Mapping.endReason(facts(connected = true, intent = Mapping.LocalIntent.HANGUP)))
    }

    @Test
    fun outgoingFailures() {
        assertEquals(EndReasonMsg.BUSY, Mapping.endReason(facts(incoming = false, code = 486, state = Call.State.Error)))
        assertEquals(EndReasonMsg.DECLINED, Mapping.endReason(facts(incoming = false, code = 603, state = Call.State.Error)))
        assertEquals(EndReasonMsg.NO_ANSWER, Mapping.endReason(facts(incoming = false, code = 480, state = Call.State.Error)))
        assertEquals(EndReasonMsg.FAILED, Mapping.endReason(facts(incoming = false, code = 404, state = Call.State.Error)))
        assertEquals(EndReasonMsg.FAILED, Mapping.endReason(facts(incoming = false, reason = Reason.IOError, state = Call.State.Error)))
    }

    @Test
    fun droppedConnectedCallIsNetworkLost() {
        assertEquals(EndReasonMsg.NETWORK_LOST, Mapping.endReason(facts(connected = true, reason = Reason.IOError, state = Call.State.Error)))
        assertEquals(EndReasonMsg.REMOTE, Mapping.endReason(facts(connected = true)))
    }

    @Test
    fun registrationFailures() {
        assertEquals(RegFailureMsg.BAD_CREDENTIALS, Mapping.registrationFailure(401, null, "Unauthorized"))
        assertEquals(RegFailureMsg.BAD_CREDENTIALS, Mapping.registrationFailure(407, null, null))
        assertEquals(RegFailureMsg.FORBIDDEN, Mapping.registrationFailure(403, Reason.Forbidden, "Forbidden"))
        assertEquals(RegFailureMsg.TLS, Mapping.registrationFailure(0, Reason.IOError, "TLS handshake failed"))
        assertEquals(RegFailureMsg.TIMEOUT, Mapping.registrationFailure(408, null, "Request Timeout"))
        assertEquals(RegFailureMsg.NETWORK, Mapping.registrationFailure(503, null, "Service Unavailable"))
        assertEquals(RegFailureMsg.UNKNOWN, Mapping.registrationFailure(500, null, "Server Internal Error"))
    }

    @Test
    fun codecOrderIsOpusG722PcmaPcmu() {
        val have = listOf("PCMU", "speex", "opus", "PCMA", "telephone-event", "G722", "GSM", "speex")
        val plan = Mapping.codecPlan(have)
        val enabled = plan.filter { it.second }.map { have[it.first] }
        assertEquals(listOf("opus", "G722", "PCMA", "PCMU", "telephone-event"), enabled)
        assertEquals(have.size, plan.size)
        assertEquals(have.indices.toSet(), plan.map { it.first }.toSet())
        assertTrue(plan.filter { !it.second }.all { have[it.first] in setOf("speex", "GSM") })
    }

    @Test
    fun hdIsOpusOrG722() {
        assertTrue(Mapping.isHdCodec("opus"))
        assertTrue(Mapping.isHdCodec("G722"))
        assertFalse(Mapping.isHdCodec("PCMA"))
        assertFalse(Mapping.isHdCodec(null))
    }

    @Test
    fun audioRoutes() {
        assertEquals(AudioRouteMsg.EARPIECE, Mapping.route(AudioDevice.Type.Earpiece))
        assertEquals(AudioRouteMsg.BLUETOOTH, Mapping.route(AudioDevice.Type.Bluetooth))
        assertEquals(AudioRouteMsg.WIRED_HEADSET, Mapping.route(AudioDevice.Type.Headset))
        assertNull(Mapping.route(AudioDevice.Type.Microphone))
        assertTrue(Mapping.deviceTypes(AudioRouteMsg.CAR).isEmpty())
    }
}

class RulesTest {

    @Test
    fun emergencyNumbers() {
        for (n in listOf("000", "112", "106", "0000", "0112", "0106", " 0 0 0 ", "1-1-2", "(000)")) {
            assertTrue(Rules.isEmergency(n), n)
        }
        for (n in listOf("0001", "1122", "*000", "000#", "0491 570 737", "", "sos")) {
            assertFalse(Rules.isEmergency(n), n)
        }
    }

    @Test
    fun dialStrings() {
        assertEquals("0491570737", Rules.dialString("0491 570 737"))
        assertEquals("+61355501201", Rules.dialString(" +61 3 5550 1201"))
        assertEquals("*97", Rules.dialString("*97"))
        assertEquals("61355501201", Rules.dialString("61+355501201"))
        assertTrue(Rules.isDialable("204"))
        assertTrue(Rules.isDialable("+61355501201"))
        assertFalse(Rules.isDialable("+"))
        assertFalse(Rules.isDialable(""))
    }

    @Test
    fun emergencyWithAnAccountIsPlaced() {
        for (n in listOf("000", "112", "106", "0000")) {
            assertNull(Rules.callGate(n, hasAccount = true, registered = true, micGranted = true), n)
            // Even while not registered right now or without the microphone.
            assertNull(Rules.callGate(n, hasAccount = true, registered = false, micGranted = false), n)
        }
    }

    @Test
    fun noAccountIsNotRegisteredForEmergencyAndNormalAlike() {
        assertEquals("not_registered", Rules.callGate("000", hasAccount = false, registered = false, micGranted = true))
        assertEquals("not_registered", Rules.callGate("204", hasAccount = false, registered = false, micGranted = true))
        assertEquals(
            Rules.callGate("0491 570 737", hasAccount = false, registered = false, micGranted = false),
            Rules.callGate("112", hasAccount = false, registered = false, micGranted = false),
        )
    }

    @Test
    fun normalNumbersNeedRegistrationAndMicrophone() {
        assertNull(Rules.callGate("204", hasAccount = true, registered = true, micGranted = true))
        assertEquals("not_registered", Rules.callGate("204", hasAccount = true, registered = false, micGranted = true))
        assertEquals("microphone_denied", Rules.callGate("204", hasAccount = true, registered = true, micGranted = false))
    }

    @Test
    fun noRuleRefusesOnTheNumberItself() {
        // The only codes callGate can return are about the account and the mic.
        for (n in listOf("000", "112", "106", "0000", "0112", "0106", "(000)", "1-1-2")) {
            for (acc in listOf(true, false)) for (reg in listOf(true, false)) for (mic in listOf(true, false)) {
                val r = Rules.callGate(n, acc, reg, mic)
                assertTrue(r == null || (r == "not_registered" && !acc), "$n $acc $reg $mic -> $r")
            }
            assertTrue(Rules.isDialable(Rules.dialString(n)), n)
        }
    }

    @Test
    fun instanceIds() {
        assertEquals(
            "0e2f3c4a-5b6c-4d7e-8f90-a1b2c3d4e5f6",
            Rules.instanceUuid("urn:uuid:0E2F3C4A-5B6C-4D7E-8F90-A1B2C3D4E5F6"),
        )
        assertNull(Rules.instanceUuid("0e2f3c4a-5b6c-4d7e-8f90-a1b2c3d4e5f6"))
        assertNull(Rules.instanceUuid("urn:uuid:not-a-uuid"))
        assertNull(Rules.instanceUuid("<urn:uuid:0e2f3c4a-5b6c-4d7e-8f90-a1b2c3d4e5f6>"))
    }

    @Test
    fun dtmf() {
        assertTrue(Rules.isValidDtmf("123*#A"))
        assertFalse(Rules.isValidDtmf("12x"))
        assertFalse(Rules.isValidDtmf(""))
    }
}
