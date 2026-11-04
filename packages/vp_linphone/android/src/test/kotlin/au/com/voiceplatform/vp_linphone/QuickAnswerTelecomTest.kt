package au.com.voiceplatform.vp_linphone

import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.telecom.ConnectionRequest
import android.telecom.PhoneAccount
import android.telecom.TelecomManager
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A code like *97 answers before Telecom asks for the connection: the connection
 * must still end up in the call's state, or Telecom shows it dialling throughout.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class QuickAnswerTelecomTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun snapshot(id: String, state: CallStateMsg) = CallMsg(
        id = id,
        incoming = false,
        state = state,
        remoteNumber = "*97",
        muted = false,
        encrypted = false,
        hdAudio = false,
    )

    private fun connect(id: String) {
        val extras = Bundle().apply {
            putBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, Bundle().apply { putString(TelecomBridge.EXTRA_CALL_ID, id) })
        }
        val request = ConnectionRequest(TelecomBridge.handle(context), Uri.fromParts(PhoneAccount.SCHEME_SIP, "*97", null), extras)
        TelecomBridge.createConnection(context, request, incoming = false)
    }

    private fun place(id: String) = TelecomBridge.placeOutgoing(context, TelecomBridge.CallInfo(id, false, "*97", null))

    @Test
    fun `answered before the connection exists, the connection starts active`() {
        place("quick")
        TelecomBridge.onSnapshot(context, snapshot("quick", CallStateMsg.CONNECTED))
        connect("quick")
        assertEquals(TelecomState.ACTIVE, TelecomBridge.connection("quick")?.machine?.state)
    }

    @Test
    fun `not answered yet, the connection stays dialing`() {
        place("slow")
        TelecomBridge.onSnapshot(context, snapshot("slow", CallStateMsg.RINGING))
        connect("slow")
        assertEquals(TelecomState.DIALING, TelecomBridge.connection("slow")?.machine?.state)
    }

    @Test
    fun `a later snapshot reaches the connection as before`() {
        place("later")
        connect("later")
        TelecomBridge.onSnapshot(context, snapshot("later", CallStateMsg.CONNECTED))
        assertEquals(TelecomState.ACTIVE, TelecomBridge.connection("later")?.machine?.state)
    }
}
