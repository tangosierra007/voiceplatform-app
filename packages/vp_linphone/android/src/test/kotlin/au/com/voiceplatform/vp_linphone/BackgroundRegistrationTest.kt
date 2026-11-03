package au.com.voiceplatform.vp_linphone

import au.com.voiceplatform.vp_linphone.BackgroundRegistration.EngineState
import au.com.voiceplatform.vp_linphone.BackgroundRegistration.Outcome
import au.com.voiceplatform.vp_linphone.BackgroundRegistration.Plan
import kotlin.test.assertEquals
import kotlin.test.assertSame
import org.junit.jupiter.api.Test

class BackgroundRegistrationTest {

    private val record = AccountRecord(
        authUsername = "app-abcdefghij",
        password = "secret",
        domain = "tenant.example.test",
        outboundProxy = "sip:sip.example.test:5061;transport=tls",
        displayName = "Test User",
        expiresSeconds = 600,
        instanceId = "urn:uuid:00000000-0000-4000-8000-000000000001",
        pushProvider = "fcm",
        pushPrid = "token-1",
        pushParam = "voiceplatform-app",
    )
    private val noPush = record.copy(pushProvider = null, pushPrid = null, pushParam = null)

    private val stopped = EngineState(coreUp = false, accountUp = false, stopped = true)
    private val starting = EngineState(coreUp = false, accountUp = false, stopped = false)
    private val upNoAccount = EngineState(coreUp = true, accountUp = false, stopped = false)
    private val registered = EngineState(coreUp = true, accountUp = true, stopped = false)

    @Test
    fun signedOutRegistersNothing() {
        for (e in listOf(stopped, starting, upNoAccount, registered)) {
            assertEquals(Plan.NoAccount, BackgroundRegistration.plan(null, stored = false, e, "token-1"))
        }
    }

    @Test
    fun aStoredAccountThatCantBeReadIsRetriedNotTakenForASignOut() {
        for (e in listOf(stopped, starting, upNoAccount, registered)) {
            assertEquals(Plan.Unreadable, BackgroundRegistration.plan(null, stored = true, e, "token-1"))
        }
    }

    @Test
    fun nothingRunningRegistersTheStoredAccountWithoutTheService() {
        assertEquals(Plan.Headless(record), BackgroundRegistration.plan(record, stored = true, stopped, "token-1"))
        assertEquals(Plan.Headless(record), BackgroundRegistration.plan(record, stored = true, stopped, null))
    }

    @Test
    fun aNewTokenBecomesThePnPrid() {
        assertEquals(
            Plan.Headless(record.copy(pushPrid = "token-2")),
            BackgroundRegistration.plan(record, stored = true, stopped, "token-2"),
        )
        assertEquals(Plan.RefreshRunning("token-2"), BackgroundRegistration.plan(record, stored = true, registered, "token-2"))
    }

    @Test
    fun aRunningEngineIsRefreshedNotReplaced() {
        assertEquals(Plan.RefreshRunning(null), BackgroundRegistration.plan(record, stored = true, registered, "token-1"))
        assertEquals(Plan.RefreshRunning(null), BackgroundRegistration.plan(record, stored = true, registered, null))
    }

    @Test
    fun aStartingServiceOrOneWithNoAccountYetIsLeftAlone() {
        assertEquals(Plan.LeaveToEngine, BackgroundRegistration.plan(record, stored = true, starting, "token-2"))
        assertEquals(Plan.LeaveToEngine, BackgroundRegistration.plan(record, stored = true, upNoAccount, "token-2"))
    }

    @Test
    fun noTokenOrABlankOneKeepsTheStoredPnPrid() {
        assertSame(record, BackgroundRegistration.withToken(record, null))
        assertSame(record, BackgroundRegistration.withToken(record, " "))
        assertSame(record, BackgroundRegistration.withToken(record, "token-1"))
    }

    @Test
    fun anAccountWithoutPushParamsGetsNoneFromTheJob() {
        assertSame(noPush, BackgroundRegistration.withToken(noPush, "token-2"))
        val otherProvider = record.copy(pushProvider = "apns")
        assertSame(otherProvider, BackgroundRegistration.withToken(otherProvider, "token-2"))
    }

    @Test
    fun theEdgesRefusalIsFinalTheRestIsRetried() {
        assertEquals(Outcome.REFUSED, BackgroundRegistration.failure(401))
        assertEquals(Outcome.REFUSED, BackgroundRegistration.failure(403))
        assertEquals(Outcome.REFUSED, BackgroundRegistration.failure(400))
        assertEquals(Outcome.FAILED, BackgroundRegistration.failure(408))
        assertEquals(Outcome.FAILED, BackgroundRegistration.failure(503))
        assertEquals(Outcome.FAILED, BackgroundRegistration.failure(0))
    }

    @Test
    fun aRunningServiceWithNoAccountGetsTheStoredOneTheAppsRegisterFailed() {
        // The app's register failed after its POST and queued the job: the
        // stored account has the rotated password; the service's Core is up.
        val running = EngineState(coreUp = true, accountUp = false, stopped = false, running = true)
        assertEquals(Plan.RegisterOnRunning(record), BackgroundRegistration.plan(record, stored = true, running, "token-1"))
        assertEquals(
            Plan.RegisterOnRunning(record.copy(pushPrid = "token-2")),
            BackgroundRegistration.plan(record, stored = true, running, "token-2"),
        )
        // Still starting: left to the service, checked again.
        assertEquals(Plan.LeaveToEngine, BackgroundRegistration.plan(record, stored = true, upNoAccount, "token-1"))
        // Registered: refreshed, never replaced.
        val registeredRunning = EngineState(coreUp = true, accountUp = true, stopped = false, running = true)
        assertEquals(Plan.RefreshRunning(null), BackgroundRegistration.plan(record, stored = true, registeredRunning, "token-1"))
        assertEquals(Plan.NoAccount, BackgroundRegistration.plan(null, stored = false, running, "token-1"))
    }

    @Test
    fun a401WithANewerStoredPasswordIsRetriedOnceWithIt() {
        // KEEP kept a job mid-register while a later POST rotated the password.
        val newer = record.copy(password = "rotated")
        assertEquals(newer, BackgroundRegistration.retryWithNewPassword(401, "secret", newer, alreadyRetried = false))
        assertEquals(newer, BackgroundRegistration.retryWithNewPassword(403, "secret", newer, alreadyRetried = false))
        // Once only.
        assertEquals(null, BackgroundRegistration.retryWithNewPassword(401, "rotated", newer, alreadyRetried = true))
        // The same password: a real refusal.
        assertEquals(null, BackgroundRegistration.retryWithNewPassword(401, "secret", record, alreadyRetried = false))
        // Not an auth refusal, or nothing stored.
        assertEquals(null, BackgroundRegistration.retryWithNewPassword(503, "secret", newer, alreadyRetried = false))
        assertEquals(null, BackgroundRegistration.retryWithNewPassword(408, "secret", newer, alreadyRetried = false))
        assertEquals(null, BackgroundRegistration.retryWithNewPassword(401, "secret", null, alreadyRetried = false))
        assertEquals(null, BackgroundRegistration.retryWithNewPassword(401, null, newer, alreadyRetried = false))
    }
}
