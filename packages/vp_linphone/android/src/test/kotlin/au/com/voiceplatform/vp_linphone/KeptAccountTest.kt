package au.com.voiceplatform.vp_linphone

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import org.junit.jupiter.api.Test

/**
 * Q356-1: the kept account stores its issue time, so the app can register
 * with it for up to 7 days and ask for a new one after. Example values only;
 * the password here is a fixture, not a real credential.
 */
class KeptAccountTest {

    private val issuedAt = 1_795_000_000_000L

    private val record = AccountRecord(
        authUsername = "app-abcde12345",
        password = "fixture-pw-not-real",
        domain = "democo.sip.example.com",
        outboundProxy = "sip:edge.example.com:5061;transport=tls",
        displayName = "Ava Nguyen",
        expiresSeconds = 604_800,
        instanceId = "urn:uuid:00000000-0000-4000-8000-000000000001",
        pushProvider = "fcm",
        pushPrid = "fcm-token-1",
        pushParam = "voiceplatform-app",
        issuedAtMillis = issuedAt,
    )

    @Test
    fun theIssueTimeIsStoredBesideTheAccount() {
        val back = assertNotNull(AccountRecord.decode(record.encode()))
        assertEquals(record, back)
        assertEquals(issuedAt, back.issuedAtMillis)
    }

    @Test
    fun aRecordWithNoIssueTimeReadsBackWithNone() {
        val back = assertNotNull(AccountRecord.decode(record.copy(issuedAtMillis = null).encode()))
        assertNull(back.issuedAtMillis)
    }

    @Test
    fun aRecordKeptBeforeTheTimeWasStoredStillReadsWithNoTime() {
        // The v1 layout: ten fields, no issue time. The app treats it as too
        // old and asks the API once; push wakes keep working meanwhile.
        val fields = listOf(
            record.authUsername, record.password, record.domain, record.outboundProxy, record.displayName,
            record.expiresSeconds.toString(), record.instanceId, record.pushProvider, record.pushPrid,
            record.pushParam,
        )
        val v1 = "v1|" + fields.joinToString("") { f -> "${f!!.length}:$f" }
        val back = assertNotNull(AccountRecord.decode(v1.toByteArray(Charsets.UTF_8)))
        assertEquals(record.copy(issuedAtMillis = null), back)
    }

    @Test
    fun aBadIssueTimeIsNotARecord() {
        val bad = String(record.encode(), Charsets.UTF_8).replace("13:$issuedAt", "13:abcdefghijklm")
        assertNull(AccountRecord.decode(bad.toByteArray(Charsets.UTF_8)))
    }

    @Test
    fun theRecordNeverPrintsItsPassword() {
        assertFalse(record.password in record.toString())
        assertEquals("AccountRecord(app-abcde12345@democo.sip.example.com)", record.toString())
    }

    @Test
    fun newPushParamsKeepThePasswordAndTheIssueTime() {
        val next = AccountSetup.withPush(record, "fcm", "fcm-token-2", "voiceplatform-app")
        assertEquals("fcm-token-2", next.pushPrid)
        assertEquals(record.password, next.password)
        assertEquals(issuedAt, next.issuedAtMillis)
    }

    @Test
    fun noPushParamsLeaveTheKeptOnes() {
        assertSame(record, AccountSetup.withPush(record, null, null, null))
        assertSame(record, AccountSetup.withPush(record, "fcm", null, "voiceplatform-app"))
    }
}
