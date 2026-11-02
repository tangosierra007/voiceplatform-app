package au.com.voiceplatform.vp_linphone

import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Test

/** A cold start from the full-screen intent must not lose the incoming-call request. */
class PendingUiRequestTest {

    @AfterEach
    fun reset() {
        PendingUiRequest.listener = null
        PendingUiRequest.take()
    }

    private val incoming = UiRequestMsg(UiRequestKindMsg.SHOW_INCOMING, "call-1")

    @Test
    fun withNoFlutterEngineTheRequestWaitsForTake() {
        PendingUiRequest.post(incoming)
        assertEquals(incoming, PendingUiRequest.take())
        assertNull(PendingUiRequest.take(), "once")
    }

    @Test
    fun anEngineWhoseDartSideNeverReceivedItStillGetsItFromTake() {
        // Attached, but the send failed (Dart not listening yet): no ack.
        val sent = mutableListOf<UiRequestMsg>()
        PendingUiRequest.listener = { sent += it }
        PendingUiRequest.post(incoming)
        assertEquals(listOf(incoming), sent)
        assertEquals(incoming, PendingUiRequest.take())
    }

    @Test
    fun aRequestDartReceivedLiveIsNotHandedOutAgain() {
        PendingUiRequest.listener = { PendingUiRequest.delivered(it) }
        PendingUiRequest.post(incoming)
        assertNull(PendingUiRequest.take())
        // An ack for an older request doesn't hide a newer one.
        val newer = UiRequestMsg(UiRequestKindMsg.SHOW_CALL, "call-1")
        PendingUiRequest.listener = null
        PendingUiRequest.post(newer)
        PendingUiRequest.delivered(incoming)
        assertEquals(newer, PendingUiRequest.take())
    }

    @Test
    fun thePluginAcksOnlyAfterDartReceivedIt() {
        val plugin = File("src/main/kotlin/au/com/voiceplatform/vp_linphone/VpLinphonePlugin.kt").readText()
        val send = plugin.substringAfter("PendingUiRequest.listener = { request ->").substringBefore("\n        }\n")
        assertTrue(send.indexOf("it.onUiRequest(request)") < send.indexOf("PendingUiRequest.delivered(request)"))
    }
}
