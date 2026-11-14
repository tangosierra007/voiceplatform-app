package au.com.voiceplatform.vp_linphone

import java.io.File
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/**
 * FU81: after a fresh install the engine service starts before
 * POST_NOTIFICATIONS is answered, so Android runs it without showing
 * "Ready for calls". Once notifications are allowed and the app is in front
 * again, the service puts its notice up again instead of waiting for a call.
 */
class ReadyNoticeRepostTest {

    @Test
    fun putUpAgainOnlyWhenItWasHiddenAndIsAllowedNow() {
        assertTrue(ServiceNotice.needsRepost(postedHidden = true, allowedNow = true))
        // Still not allowed: nothing to gain.
        assertFalse(ServiceNotice.needsRepost(postedHidden = true, allowedNow = false))
        // Shown already: never posted twice.
        assertFalse(ServiceNotice.needsRepost(postedHidden = false, allowedNow = true))
        assertFalse(ServiceNotice.needsRepost(postedHidden = false, allowedNow = false))
    }

    private fun src(name: String) = File("src/main/kotlin/au/com/voiceplatform/vp_linphone/$name").readText()

    @Test
    fun theServiceRemembersAHiddenNoticeAndPutsItUpAgain() {
        val service = src("EngineService.kt")
        val apply = service.substringAfter("private fun apply(").substringBefore("fun repostIfNowAllowed(")
        // Every notice put up records whether Android could show it.
        assertTrue("postedHidden = !notificationsAllowed()" in apply)
        val repost = service.substringAfter("fun repostIfNowAllowed()").substringBefore("private fun notificationsAllowed(")
        assertTrue("ServiceNotice.needsRepost(postedHidden, notificationsAllowed())" in repost)
        // Forgetting what is shown makes apply() call startForeground again.
        assertTrue("shown = null" in repost)
        assertTrue("apply()" in repost)
    }

    @Test
    fun theAppComingToTheFrontAsksTheService() {
        val engine = src("LinphoneEngine.kt")
        assertTrue("service?.repostIfNowAllowed()" in engine.substringAfter("fun onAppResumed()"))
        val plugin = src("VpLinphonePlugin.kt")
        assertTrue("registerActivityLifecycleCallbacks(resumeCallbacks)" in plugin)
        assertTrue("unregisterActivityLifecycleCallbacks(resumeCallbacks)" in plugin)
        assertTrue("if (a === activity) LinphoneEngine.onAppResumed()" in plugin)
    }
}
