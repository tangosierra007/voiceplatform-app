package au.com.voiceplatform.vp_linphone

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

// Sample lines use ACMA fictional numbers only (0491 570 737, 03 5550 1201).
class LogScrubberTest {

    private val password = "testpasswordtestpassword"

    private fun scrubber() = LogScrubber().apply { addSecret(password) }

    @Test
    fun authorizationHeaderValueIsRemoved() {
        val line = "Authorization: Digest username=\"app-abcde12345\", realm=\"democo.sip.voiceplatform.com.au\", " +
            "nonce=\"5f2c1a\", uri=\"sip:democo.sip.voiceplatform.com.au\", response=\"6629fae49393a05397450978507c4ef1\""
        val out = scrubber().scrub(line)
        assertEquals("Authorization: [scrubbed]", out)
    }

    @Test
    fun proxyAuthorizationInsideAMultiLineMessage() {
        val msg = "INVITE sip:204@democo.sip.voiceplatform.com.au SIP/2.0\r\n" +
            "Proxy-Authorization: Digest username=\"app-abcde12345\", response=\"0a4f113eab\"\r\n" +
            "Max-Forwards: 70\r\n"
        val out = scrubber().scrub(msg)
        assertFalse("0a4f113eab" in out)
        assertTrue("Proxy-Authorization: [scrubbed]\r\n" in out)
        assertTrue("Max-Forwards: 70" in out)
    }

    @Test
    fun digestParametersOutsideAuthorization() {
        val out = scrubber().scrub("challenge: nonce=\"abc123def\", opaque=\"xyz\", cnonce=a1b2c3")
        assertFalse("abc123def" in out)
        assertFalse("xyz\"" in out)
        assertFalse("a1b2c3" in out)
    }

    @Test
    fun knownPasswordAnywhere() {
        val out = scrubber().scrub("auth info for app-abcde12345 with $password set")
        assertFalse(password in out)
        assertTrue("[scrubbed]" in out)
    }

    @Test
    fun passwordKeyValuePairs() {
        val s = LogScrubber()
        assertEquals("password=[scrubbed] next", s.scrub("password=hunter2hunter next"))
        assertEquals("passwd: [scrubbed]", s.scrub("passwd: \"q w e\""))
        assertEquals("ha1 = [scrubbed];", s.scrub("ha1 = 5ebe2294ecd0e0f08eab7690d2a6ee69;"))
    }

    @Test
    fun pushTokenAndBearer() {
        val s = LogScrubber()
        val out = s.scrub("Contact: <sip:app-x@192.0.2.10;transport=tls;pn-provider=fcm;pn-prid=dXk3:APA91bH-x_y;pn-param=voiceplatform-app>")
        assertFalse("APA91" in out)
        assertTrue("pn-prid=[scrubbed]" in out)
        assertTrue("pn-param=voiceplatform-app" in out)
        assertEquals("Authorisation Bearer [scrubbed] ok", s.scrub("Authorisation Bearer abc.def-ghi_jkl ok"))
    }

    @Test
    fun fullPhoneNumbersAreRemoved() {
        val s = LogScrubber()
        assertEquals("From: <sip:[n]@democo.sip.voiceplatform.com.au>", s.scrub("From: <sip:+61491570737@democo.sip.voiceplatform.com.au>"))
        assertEquals("dial [n] now", s.scrub("dial 0491 570 737 now"))
        assertEquals("dial [n] now", s.scrub("dial 0491-570-737 now"))
        assertEquals("dial ([n] now", s.scrub("dial (03) 5550 1201 now"))
        assertFalse(Regex("""\d{6,}""").containsMatchIn(s.scrub("a 0355501201 b 61355501201")))
    }

    @Test
    fun shortNumbersAndAddressesSurvive() {
        val s = LogScrubber()
        assertEquals("ext 204 port 5061 ip 192.0.2.20 code 486", s.scrub("ext 204 port 5061 ip 192.0.2.20 code 486"))
        assertEquals("sip:204@democo.sip.voiceplatform.com.au", s.scrub("sip:204@democo.sip.voiceplatform.com.au"))
    }

    @Test
    fun emailsGoButSipUrisStay() {
        val s = LogScrubber()
        assertEquals("user [email] signed in", s.scrub("user ava.nguyen@example.com signed in"))
        assertEquals("<sip:app-abc@democo.sip.voiceplatform.com.au>", s.scrub("<sip:app-abc@democo.sip.voiceplatform.com.au>"))
    }

    @Test
    fun authenticationInfoParameters() {
        val out = LogScrubber().scrub("Authentication-Info: nextnonce=\"47364c23432d2e\", qop=auth, rspauth=\"6629fae4\", cnonce=\"0a4f\"")
        assertEquals("Authentication-Info: nextnonce=[scrubbed], qop=auth, rspauth=[scrubbed], cnonce=[scrubbed]", out)
    }

    @Test
    fun jsonStyleKeys() {
        val s = LogScrubber()
        assertEquals("{\"password\":[scrubbed],\"user\":\"ava\"}", s.scrub("{\"password\":\"hunter2hunter\",\"user\":\"ava\"}"))
        assertEquals("{\"token\": [scrubbed]}", s.scrub("{\"token\": \"abc.def\"}"))
        assertEquals("{password: [scrubbed]}", s.scrub("{password: hunter2hunter}"))
        assertEquals("{\"access_token\":[scrubbed]}", s.scrub("{\"access_token\":abcdef}"))
        assertEquals("pass=[scrubbed]&u=1", s.scrub("pass=hunter2hunter&u=1"))
    }

    @Test
    fun numbersWithDotsAndSlashes() {
        val s = LogScrubber()
        assertEquals("dial [n] now", s.scrub("dial 0491.570.737 now"))
        assertEquals("dial [n] now", s.scrub("dial 03/5550/1201 now"))
        assertEquals("dial [n] now", s.scrub("dial +61.3.5550.1201 now"))
        // A dotted IPv4 address is not a number to hide.
        assertEquals("via 192.0.2.20:5061", s.scrub("via 192.0.2.20:5061"))
    }

    @Test
    fun clearSecretsForgetsThePassword() {
        val s = scrubber()
        s.clearSecrets()
        // Still caught by the rules when it appears as a key/value pair.
        assertEquals("password=[scrubbed]", s.scrub("password=$password"))
    }

    @Test
    fun scrubbingIsIdempotent() {
        val s = scrubber()
        val once = s.scrub("Authorization: Digest response=\"x\" from 0491 570 737 $password")
        assertEquals(once, s.scrub(once))
    }
}
