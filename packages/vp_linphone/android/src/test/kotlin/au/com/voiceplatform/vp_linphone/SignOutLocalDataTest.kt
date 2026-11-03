package au.com.voiceplatform.vp_linphone

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The privacy policy: "When you sign out, or an administrator signs your
 * phone out, the app deletes everything it keeps on your phone." Both native
 * sign-out paths, on the real engine object with no Core: the app's
 * unregister and the `signed_out` push.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SignOutLocalDataTest {

    private lateinit var context: Context

    private val engineDir get() = File(context.noBackupFilesDir, "vp_linphone")
    private val account get() = File(engineDir, "account.bin")
    private val callLog get() = File(engineDir, "calls/0000000000001-0000.log")
    private val prefs get() = context.getSharedPreferences("vp_linphone_push", Context.MODE_PRIVATE)

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        LinphoneEngine.resetLogForTest()
        VpPush.resetForTest()
        callLog.parentFile!!.mkdirs()
        callLog.writeText("first user's call\n")
        account.writeBytes(byteArrayOf(1, 2, 3))
        prefs.edit()
            .putString("late", "1761534900123")
            .putString("pending", "VOICEMAIL|p1|")
            .apply()
        PushTokenFlag.setUnsent(context)
    }

    private fun assertForgotten() {
        assertFalse("account", account.exists())
        assertFalse("call log", callLog.exists())
        assertEquals(0, LinphoneEngine.exportLastCallLog().size)
        assertFalse("late-wake times", prefs.contains("late"))
        assertFalse("token flag", PushTokenFlag.isUnsent(context))
    }

    @Test
    fun theAppsUnregisterForgetsWhatThePhoneKeeps() {
        LinphoneEngine.attach(context)
        assertTrue(LinphoneEngine.exportLastCallLog().isNotEmpty())
        var done = false
        LinphoneEngine.unregister { done = true }
        assertTrue(done)
        assertForgotten()
        assertFalse("pending pushes", prefs.contains("pending"))
    }

    @Test
    fun aSignedOutPushForgetsItWithNoFlutterRunning() {
        // Nothing attached: the process was started by the push alone.
        val handled = VpPush.get(context).onMessage(mapOf("type" to "signed_out", "pushId" to "p2", "sentAt" to null))
        assertTrue(handled)
        assertForgotten()
        // Only the signed_out itself waits, so the app can say why it was signed out.
        val pending = VpPush.takePending(context)
        assertEquals(listOf(PushTypeMsg.SIGNED_OUT), pending.map { it.type })
    }

    @Test
    fun aNewSignInsLogStartsEmpty() {
        LinphoneEngine.attach(context)
        LinphoneEngine.unregister {}
        LinphoneEngine.logLine("ENGINE", "first user's teardown")
        // No Core: register() throws after opening the log for the new account.
        kotlin.runCatching {
            LinphoneEngine.register(
                "app-abcde12345", "new-password", "tenant.example.test", "sip:edge.example.test:5061;transport=tls",
                "Second User", 604_800, "urn:uuid:00000000-0000-4000-8000-000000000002", null, null, null,
            )
        }
        assertEquals(0, LinphoneEngine.exportLastCallLog().size)
        assertFalse(callLog.exists())
    }
}
