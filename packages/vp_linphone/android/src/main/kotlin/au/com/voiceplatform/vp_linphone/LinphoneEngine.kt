package au.com.voiceplatform.vp_linphone

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import java.io.File
import java.util.concurrent.CopyOnWriteArraySet
import org.linphone.core.Account
import org.linphone.core.AudioDevice
import org.linphone.core.AuthInfo
import org.linphone.core.Call
import org.linphone.core.Core
import org.linphone.core.CoreListenerStub
import org.linphone.core.Factory
import org.linphone.core.LogCollectionState
import org.linphone.core.LogLevel
import org.linphone.core.LoggingService
import org.linphone.core.LoggingServiceListener
import org.linphone.core.MediaEncryption
import org.linphone.core.Reason
import org.linphone.core.RegistrationState
import org.linphone.core.TransportType

/**
 * The one liblinphone [Core] of the app. It is created by [EngineService]
 * (the foreground service) and lives exactly as long as it does. Everything
 * here runs on the main looper, where liblinphone iterates.
 *
 * Credentials: the password is handed to liblinphone's in-memory AuthInfo, to
 * the log scrubber and to [CredentialStore] (Keystore-encrypted, so a push can
 * re-register while the app is not running). The Core's config has no file;
 * the password is never logged and never in an event.
 */
object LinphoneEngine {

    interface Listener {
        fun onRegistration(event: RegistrationMsg)
        fun onCall(call: CallMsg)
        fun onAudio(audio: AudioMsg)
        fun onInputLevel(dbm0: Double)
        fun onCallQuality(quality: QualityMsg) {}
    }

    const val USER_AGENT = "VoicePlatform-app"
    const val VERSION = "0.1.0"
    private const val LEVEL_INTERVAL_MS = 50L
    private const val SILENCE_DBM0 = -130.0
    private const val QUALITY_EVERY_TICKS = 40 // 2 s at 50 ms
    private const val UNREGISTER_TIMEOUT_MS = 5000L

    private val main = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArraySet<Listener>()
    val scrubber = LogScrubber()

    private var logFile: CallLogFile? = null
    private var core: Core? = null
    private var account: Account? = null
    private var authInfo: AuthInfo? = null
    private var domain: String? = null
    private var service: EngineService? = null

    private var pendingUnregister: (() -> Unit)? = null

    private class Tracked(val id: String, val call: Call, val incoming: Boolean, val startedAt: Long) {
        var state: CallStateMsg = if (incoming) CallStateMsg.INCOMING else CallStateMsg.DIALLING
        var connectedAt: Long? = null
        var intent: Mapping.LocalIntent? = null
        var transferring = false
        var endReason: EndReasonMsg? = null
        var hdrCalled: String? = null
        var hdrAlsoRinging: String? = null
        var hdrRepeat: String? = null
        var hdrLastAnswered: String? = null
        var announced = false
    }

    private val calls = LinkedHashMap<String, Tracked>()
    private val idByPointer = HashMap<Long, String>()

    fun addListener(l: Listener) = listeners.add(l)
    fun removeListener(l: Listener) = listeners.remove(l)

    val isStarted: Boolean get() = core != null

    // ---------------------------------------------------------------- logging

    private var factoryLogging = false

    /** The call log file; cheap, no native code loaded. */
    @Synchronized
    fun attach(context: Context) {
        appContext = context.applicationContext
        if (logFile == null) logFile = CallLogFile(File(context.noBackupFilesDir, "vp_linphone"), scrubber)
        if (TelecomBridge.control == null) TelecomBridge.control = telecomControl
    }

    /** Once per process, before the first Core: no logcat, no liblinphone log files. */
    @Synchronized
    private fun initLogging(context: Context) {
        attach(context)
        if (factoryLogging) return
        factoryLogging = true
        val factory = Factory.instance()
        factory.setLoggerDomain("vp_linphone")
        factory.enableLogcatLogs(false)
        factory.enableLogCollection(LogCollectionState.Disabled)
        val logging = factory.loggingService
        // Warning and above only: at Message level belle-sip dumps whole SIP
        // messages (with Authorization headers). The scrubber is the second line.
        logging.setLogLevel(LogLevel.Warning)
        logging.addListener(object : LoggingServiceListener {
            override fun onLogMessageWritten(
                logService: LoggingService,
                domain: String,
                level: LogLevel?,
                message: String,
            ) {
                logFile?.write(level?.name?.uppercase() ?: "LOG", message)
            }
        })
    }

    private fun log(message: String) {
        logFile?.write("ENGINE", message)
    }

    /** For the Telecom and push code: one scrubbed line in the call log. */
    fun logLine(level: String, message: String) {
        logFile?.write(level, message)
    }

    // ---------------------------------------------------------------- service lifecycle

    private var appContext: Context? = null

    private val lifecycle = EngineLifecycle(
        startService = {
            val ctx = appContext ?: throw IllegalStateException("no context")
            ContextCompat.startForegroundService(ctx, Intent(ctx, EngineService::class.java))
        },
        stopService = {
            appContext?.let { it.stopService(Intent(it, EngineService::class.java)) }
        },
    )

    /** True when CallEngine.start() asked for the engine; a push wake alone leaves it false. */
    private val startedByApp: Boolean get() = lifecycle.startedByApp

    fun requestStart(context: Context, byApp: Boolean = true, done: (Throwable?) -> Unit) {
        appContext = context.applicationContext
        lifecycle.requestStart(byApp, done)
    }

    fun requestStop(context: Context, done: () -> Unit) {
        appContext = context.applicationContext
        lifecycle.requestStop(done)
    }

    /** Called by [EngineService] once it is in the foreground; throws if the Core can't start. */
    internal fun onServiceCreated(svc: EngineService) {
        service = svc
        if (!lifecycle.onServiceCreated()) {
            log("engine stop requested while starting: stopping")
            return
        }
        startCore(svc.applicationContext)
        lifecycle.onCoreStarted()
    }

    /** The service's start failed (foreground refused, or the Core); it stops itself next. */
    internal fun onServiceStartFailed(error: Throwable) {
        log("engine start failed: ${error.javaClass.simpleName}")
        lifecycle.onStartFailed(error)
    }

    internal fun onServiceDestroyed() {
        stopCore()
        service = null
        lifecycle.onServiceDestroyed()
    }

    /**
     * The bare UUID the current Core puts in `+sip.instance` (liblinphone reads
     * it from the config's `[misc] uuid` once, when the Core is created, and
     * sends `+sip.instance="<urn:uuid:...>"`). Null until register() names one.
     */
    private var coreInstance: String? = null
    private var lastInstance: String? = null

    private fun startCore(context: Context) {
        if (core != null) return
        initLogging(context)
        val factory = Factory.instance()
        // A config with no file: nothing (auth info included) is written to disk.
        val config = factory.createConfigFromString("")
        lastInstance?.let { config.setString("misc", "uuid", it) }
        val c = factory.createCoreWithConfig(config, context)
        coreInstance = lastInstance
        try {
            configure(c)
            c.addListener(coreListener)
            check(c.start() == 0) { "Core.start failed" }
        } catch (t: Throwable) {
            c.removeListener(coreListener)
            c.stop()
            throw t
        }
        core = c
        log("core started ${c.version}")
        emitAudio()
    }

    private fun stopCore() {
        val c = core ?: return
        main.removeCallbacks(levelTick)
        c.removeListener(coreListener)
        c.terminateAllCalls()
        c.stop()
        core = null
        account = null
        authInfo = null
        domain = null
        calls.clear()
        idByPointer.clear()
        scrubber.clearSecrets()
        log("core stopped")
    }


    private fun configure(c: Core) {
        c.setUserAgent(USER_AGENT, VERSION)
        // Client TLS only: no UDP or TCP listener, a random local TLS port.
        val t = c.transports
        t.udpPort = 0
        t.tcpPort = 0
        t.tlsPort = -1
        c.setTransports(t)
        c.verifyServerCertificates(true)
        c.verifyServerCn(true)
        // SRTP SDES offered when the far end takes it; never mandatory.
        if (c.isMediaEncryptionSupported(MediaEncryption.SRTP)) c.setMediaEncryption(MediaEncryption.SRTP)
        c.setMediaEncryptionMandatory(false)
        c.isVideoCaptureEnabled = false
        c.isVideoDisplayEnabled = false
        // RFC 4733 telephone-event, never SIP INFO.
        c.useRfc2833ForDtmf = true
        c.useInfoForDtmf = false
        // No liblinphone push handling: RFC 8599 params are set by us (updatePush).
        c.isPushNotificationEnabled = false
        c.disableChat(Reason.NotImplemented)
        // The platform's no-answer timer decides when ringing stops.
        c.incTimeout = 600
        // The incoming-call notification rings (ringtone channel), not liblinphone.
        c.disableCallRinging(true)
        c.isKeepAliveEnabled = true
        applyCodecOrder(c)
    }

    private fun applyCodecOrder(c: Core) {
        val types = c.audioPayloadTypes
        val plan = Mapping.codecPlan(types.map { it.mimeType })
        val ordered = plan.map { (index, enabled) -> types[index].also { it.enable(enabled) } }
        c.setAudioPayloadTypes(ordered.toTypedArray())
        log("audio codecs ${ordered.filter { it.enabled() }.joinToString(",") { it.mimeType + "/" + it.clockRate }}")
    }

    private fun requireCore(): Core = core ?: throw VpFlutterError("invalid_state", "Engine not started")

    // ---------------------------------------------------------------- registration

    fun register(
        authUsername: String,
        password: String,
        sipDomain: String,
        outboundProxy: String,
        displayName: String,
        expiresSeconds: Int,
        instanceId: String,
        pushProvider: String?,
        pushPrid: String?,
        pushParam: String?,
    ) {
        requireCore()
        val uuid = Rules.instanceUuid(instanceId)
            ?: throw VpFlutterError("invalid_state", "instanceId must be urn:uuid:<uuid>")
        lastInstance = uuid
        if (uuid != coreInstance) {
            // liblinphone takes the instance only when a Core is created, so a
            // new device id means a new Core (no call can be in progress).
            if (calls.values.any { it.state != CallStateMsg.ENDED }) {
                throw VpFlutterError("invalid_state", "Calls in progress")
            }
            val svc = service ?: throw VpFlutterError("invalid_state", "Engine not started")
            stopCore()
            startCore(svc.applicationContext)
            log("core restarted for a new instance id")
        }
        val c = requireCore()
        dropAccount(c)
        scrubber.clearSecrets()
        scrubber.addSecret(password)
        scrubber.addSecret(pushPrid)
        val factory = Factory.instance()
        val identity = factory.createAddress("sip:$authUsername@$sipDomain")
            ?: throw VpFlutterError("invalid_state", "Bad account identity")
        identity.setDisplayName(displayName)
        // Request-URI is the tenant domain; every request goes through the
        // outbound proxy over TLS with plain sip: URIs (decision 70).
        val server = factory.createAddress("sip:$sipDomain;transport=tls")
            ?: throw VpFlutterError("invalid_state", "Bad SIP domain")
        val proxy = factory.createAddress(outboundProxy)
            ?: throw VpFlutterError("invalid_state", "Bad outbound proxy")
        if (proxy.transport != TransportType.Tls) proxy.setTransport(TransportType.Tls)
        proxy.setUriParam("lr", null)

        val params = c.createAccountParams()
        params.setIdentityAddress(identity)
        params.setServerAddress(server)
        params.setRoutesAddresses(arrayOf(proxy))
        params.isRegisterEnabled = true
        params.expires = expiresSeconds
        params.isPublishEnabled = false
        params.pushNotificationAllowed = false
        params.remotePushNotificationAllowed = false
        // Stopping the engine after a push wake must keep the push contact.
        params.isUnregisterAtStopEnabled = false
        applyPush(params, pushProvider, pushPrid, pushParam)

        val auth = factory.createAuthInfo(authUsername, null, password, null, null, sipDomain)
        c.addAuthInfo(auth)
        val acc = c.createAccount(params)
        check(c.addAccount(acc) == 0) { "addAccount failed" }
        c.defaultAccount = acc
        account = acc
        authInfo = auth
        domain = sipDomain
        appContext?.let {
            runCatching {
                CredentialStore(it).save(
                    AccountRecord(
                        authUsername, password, sipDomain, outboundProxy, displayName, expiresSeconds, instanceId,
                        pushProvider, pushPrid, pushParam,
                    ),
                )
            }.onFailure { e -> log("account not kept for push wakes: ${e.javaClass.simpleName}") }
        }
        log("register ${if (pushPrid != null) "with" else "without"} push params, expires $expiresSeconds")
    }

    private fun applyPush(params: org.linphone.core.AccountParams, provider: String?, prid: String?, param: String?) {
        params.clearContactUriParameters()
        if (provider != null && prid != null && param != null) {
            // RFC 8599 contact URI parameters.
            params.addContactUriParameter("pn-provider", provider)
            params.addContactUriParameter("pn-prid", prid)
            params.addContactUriParameter("pn-param", param)
        }
    }

    /** New push params on the live account: a re-REGISTER, calls untouched. */
    fun updatePush(provider: String, prid: String, param: String) {
        val acc = account ?: throw VpFlutterError("not_registered", "No account")
        scrubber.addSecret(prid)
        val params = acc.params.clone()
        applyPush(params, provider, prid, param)
        acc.setParams(params)
        acc.refreshRegister()
        appContext?.let { ctx ->
            val store = CredentialStore(ctx)
            store.load()?.let { store.save(it.copy(pushProvider = provider, pushPrid = prid, pushParam = param)) }
        }
        log("push params updated")
    }

    fun unregister(done: () -> Unit) {
        appContext?.let { CredentialStore(it).clear() }
        val c = core
        val acc = account
        if (c == null || acc == null) {
            scrubber.clearSecrets()
            return done()
        }
        val registered = acc.state == RegistrationState.Ok ||
            acc.state == RegistrationState.Progress ||
            acc.state == RegistrationState.Refreshing
        if (!registered) {
            dropAccount(c)
            emitRegistration(RegistrationMsg(RegStateMsg.CLEARED))
            return done()
        }
        pendingUnregister = done
        val params = acc.params.clone()
        params.isRegisterEnabled = false
        acc.setParams(params)
        main.postDelayed(unregisterTimeout, UNREGISTER_TIMEOUT_MS)
    }

    private val unregisterTimeout = Runnable { finishUnregister() }

    private fun finishUnregister() {
        main.removeCallbacks(unregisterTimeout)
        core?.let { dropAccount(it) }
        val done = pendingUnregister
        pendingUnregister = null
        done?.invoke()
    }

    /** Forgets the account and its password (liblinphone's copy and ours). */
    private fun dropAccount(c: Core) {
        account?.let { c.removeAccount(it) }
        authInfo?.let { c.removeAuthInfo(it) }
        c.clearAllAuthInfo()
        account = null
        authInfo = null
        scrubber.clearSecrets()
    }

    private fun emitRegistration(event: RegistrationMsg) = listeners.forEach { it.onRegistration(event) }

    private fun onRegistrationState(acc: Account, state: RegistrationState) {
        if (acc != account && pendingUnregister == null) return
        val event = when (state) {
            RegistrationState.None -> RegistrationMsg(RegStateMsg.NONE)
            RegistrationState.Progress -> RegistrationMsg(RegStateMsg.PROGRESS)
            RegistrationState.Ok -> {
                appContext?.let { VpPush.get(it).onRegistered() }
                RegistrationMsg(RegStateMsg.OK, sipCode = 200)
            }
            RegistrationState.Cleared -> RegistrationMsg(RegStateMsg.CLEARED)
            RegistrationState.Failed -> {
                val ei = acc.errorInfo
                val code = ei.protocolCode
                RegistrationMsg(
                    RegStateMsg.FAILED,
                    Mapping.registrationFailure(code, acc.error, ei.phrase),
                    if (code > 0) code.toLong() else null,
                )
            }
            RegistrationState.Refreshing -> null // still registered
        }
        log("registration $state")
        event?.let { emitRegistration(it) }
        if (pendingUnregister != null && (state == RegistrationState.Cleared || state == RegistrationState.Failed)) {
            finishUnregister()
        }
    }

    // ---------------------------------------------------------------- calls

    private fun micGranted(): Boolean {
        val ctx = service ?: return false
        return ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun target(number: String): org.linphone.core.Address {
        // Backstop for transfers too: never a SIP request towards an emergency number.
        if (Rules.isEmergency(number)) {
            throw VpFlutterError("emergency_use_dialler", "Emergency numbers use the phone dialler")
        }
        val d = domain ?: throw VpFlutterError("not_registered", "No account")
        val dial = Rules.dialString(number)
        if (!Rules.isDialable(dial)) throw VpFlutterError("invalid_state", "Not a dialable number")
        return Factory.instance().createAddress("sip:$dial@$d")
            ?: throw VpFlutterError("invalid_state", "Not a dialable number")
    }

    fun call(number: String, callerId: String?): String {
        // First, before the core state or anything else: never an INVITE for
        // an emergency number (the Dart side refuses it already).
        if (Rules.isEmergency(number)) {
            log("emergency number refused: use the phone dialler")
            throw VpFlutterError("emergency_use_dialler", "Emergency numbers use the phone dialler")
        }
        val c = requireCore()
        val acc = account
        when (
            Rules.callGate(
                number,
                hasAccount = acc != null,
                registered = acc?.state == RegistrationState.Ok || acc?.state == RegistrationState.Refreshing,
                micGranted = micGranted(),
            )
        ) {
            "emergency_use_dialler" ->
                throw VpFlutterError("emergency_use_dialler", "Emergency numbers use the phone dialler")
            "not_registered" -> throw VpFlutterError("not_registered", "Not registered")
            "microphone_denied" -> throw VpFlutterError("microphone_denied", "Microphone permission not granted")
        }
        if (acc == null) throw VpFlutterError("not_registered", "Not registered")
        val address = target(number)
        val params = c.createCallParams(null) ?: throw VpFlutterError("invalid_state", "No call params")
        params.account = acc
        params.isVideoEnabled = false
        if (callerId != null) params.addCustomHeader("X-VP-Caller-Id", callerId)
        val call = c.inviteAddressWithParams(address, params)
            ?: throw VpFlutterError("invalid_state", "Call could not be placed")
        val t = track(call)
        log("call ${t.id} outgoing")
        service?.let { TelecomBridge.placeOutgoing(it, TelecomBridge.CallInfo(t.id, false, Rules.dialString(number), null)) }
        emitCall(t)
        return t.id
    }

    private fun tracked(callId: String): Tracked =
        calls[callId] ?: throw VpFlutterError("no_such_call", "No call $callId")

    fun answer(callId: String) {
        val c = requireCore()
        val t = tracked(callId)
        if (t.state != CallStateMsg.INCOMING) throw VpFlutterError("invalid_state", "Call is not ringing")
        if (!micGranted()) throw VpFlutterError("microphone_denied", "Microphone permission not granted")
        val params = c.createCallParams(t.call)
        params?.isVideoEnabled = false
        val rc = if (params != null) t.call.acceptWithParams(params) else t.call.accept()
        if (rc != 0) throw VpFlutterError("invalid_state", "Answer failed")
    }

    /** 486 Busy Here for this device only; the platform keeps the other branches ringing. */
    fun decline(callId: String) {
        val t = tracked(callId)
        if (t.state != CallStateMsg.INCOMING) throw VpFlutterError("invalid_state", "Call is not ringing")
        t.intent = Mapping.LocalIntent.DECLINE
        if (t.call.decline(Reason.Busy) != 0) throw VpFlutterError("invalid_state", "Decline failed")
    }

    /** 302 to the extension's voicemail; the platform treats it as "voicemail now" (A5). */
    fun toVoicemail(callId: String, voicemailUser: String) {
        val t = tracked(callId)
        if (t.state != CallStateMsg.INCOMING) throw VpFlutterError("invalid_state", "Call is not ringing")
        val d = domain ?: throw VpFlutterError("not_registered", "No account")
        val user = Rules.dialString(voicemailUser)
        if (!Rules.isDialable(user)) throw VpFlutterError("invalid_state", "Bad voicemail target")
        val vm = Factory.instance().createAddress("sip:$user@$d")
            ?: throw VpFlutterError("invalid_state", "Bad voicemail address")
        t.intent = Mapping.LocalIntent.TO_VOICEMAIL
        if (t.call.redirectTo(vm) != 0) throw VpFlutterError("invalid_state", "Redirect failed")
    }

    fun hangup(callId: String) {
        val t = tracked(callId)
        t.intent = Mapping.LocalIntent.HANGUP
        if (t.state == CallStateMsg.ENDED) return
        t.call.terminate()
    }

    fun hold(callId: String) {
        val t = tracked(callId)
        if (t.state == CallStateMsg.HELD_BY_ME) return
        if (t.state != CallStateMsg.CONNECTED && t.state != CallStateMsg.HELD_BY_REMOTE) {
            throw VpFlutterError("invalid_state", "Call is not connected")
        }
        if (t.call.pause() != 0) throw VpFlutterError("invalid_state", "Hold failed")
    }

    fun resume(callId: String) {
        val t = tracked(callId)
        if (t.state != CallStateMsg.HELD_BY_ME) throw VpFlutterError("invalid_state", "Call is not on hold")
        if (t.call.resume() != 0) throw VpFlutterError("invalid_state", "Resume failed")
    }

    fun setMuted(muted: Boolean) {
        val c = requireCore()
        c.isMicEnabled = !muted
        calls.values.filter { it.state != CallStateMsg.ENDED }.forEach { emitCall(it) }
    }

    fun sendDtmf(callId: String, digits: String) {
        val t = tracked(callId)
        if (t.state != CallStateMsg.CONNECTED) throw VpFlutterError("invalid_state", "Call is not connected")
        if (!Rules.isValidDtmf(digits)) throw VpFlutterError("invalid_state", "Not DTMF digits")
        if (t.call.sendDtmfs(digits.uppercase()) != 0) throw VpFlutterError("invalid_state", "DTMF failed")
    }

    fun transferBlind(callId: String, targetNumber: String) {
        val t = tracked(callId)
        if (t.state == CallStateMsg.ENDED || t.state == CallStateMsg.INCOMING) {
            throw VpFlutterError("invalid_state", "Call is not connected")
        }
        val address = target(targetNumber)
        t.intent = Mapping.LocalIntent.HANGUP
        if (t.call.transferTo(address) != 0) {
            t.intent = null
            throw VpFlutterError("invalid_state", "Transfer failed")
        }
        log("call ${t.id} blind transfer")
    }

    /** REFER to [callId]'s party with Replaces naming [consultCallId]'s dialog. */
    fun transferAttended(callId: String, consultCallId: String) {
        val held = tracked(callId)
        val consult = tracked(consultCallId)
        if (callId == consultCallId) throw VpFlutterError("invalid_state", "Same call")
        if (held.state == CallStateMsg.ENDED || consult.state != CallStateMsg.CONNECTED &&
            consult.state != CallStateMsg.HELD_BY_ME
        ) {
            throw VpFlutterError("invalid_state", "Both calls must be up")
        }
        held.transferring = true
        held.intent = Mapping.LocalIntent.HANGUP
        if (held.call.transferToAnother(consult.call) != 0) {
            held.transferring = false
            held.intent = null
            throw VpFlutterError("invalid_state", "Transfer failed")
        }
        held.state = CallStateMsg.TRANSFERRING
        emitCall(held)
        log("call ${held.id} attended transfer via ${consult.id}")
    }

    /** Local 3-way: liblinphone mixes both calls on this device. */
    fun merge(callIdA: String, callIdB: String) {
        val c = requireCore()
        val a = tracked(callIdA)
        val b = tracked(callIdB)
        if (callIdA == callIdB) throw VpFlutterError("invalid_state", "Same call")
        val up = setOf(CallStateMsg.CONNECTED, CallStateMsg.HELD_BY_ME)
        if (a.state !in up || b.state !in up) throw VpFlutterError("invalid_state", "Both calls must be up")
        val existing = a.call.conference ?: b.call.conference
        if (existing != null) {
            val other = if (a.call.conference == null) a.call else b.call
            if (existing.addParticipant(other) != 0) throw VpFlutterError("invalid_state", "Merge failed")
        } else {
            val params = c.createConferenceParams(null)
            params.isVideoEnabled = false
            params.isAudioEnabled = true
            params.isLocalParticipantEnabled = true
            val conference = c.createConferenceWithParams(params)
                ?: throw VpFlutterError("invalid_state", "Merge failed")
            if (conference.addParticipants(arrayOf(a.call, b.call)) != 0) {
                throw VpFlutterError("invalid_state", "Merge failed")
            }
        }
        log("merge ${a.id} ${b.id}")
    }

    // ---------------------------------------------------------------- audio

    fun setAudioRoute(route: AudioRouteMsg) {
        // With a Telecom connection up, Telecom owns the route (Bluetooth, car).
        if (TelecomBridge.requestRoute(route)) return
        applyLinphoneRoute(route)
        emitAudio()
    }

    private fun applyLinphoneRoute(route: AudioRouteMsg) {
        val c = requireCore()
        val devices = c.audioDevices
        val out = Mapping.deviceTypes(route).firstNotNullOfOrNull { type ->
            devices.firstOrNull { it.type == type && it.hasCapability(AudioDevice.Capabilities.CapabilityPlay) }
        } ?: throw VpFlutterError("invalid_state", "Audio route not available")
        val input = when (route) {
            AudioRouteMsg.BLUETOOTH, AudioRouteMsg.WIRED_HEADSET ->
                devices.firstOrNull { it.id == out.id && it.hasCapability(AudioDevice.Capabilities.CapabilityRecord) }
            else -> null
        } ?: devices.firstOrNull {
            it.type == AudioDevice.Type.Microphone && it.hasCapability(AudioDevice.Capabilities.CapabilityRecord)
        }
        c.outputAudioDevice = out
        input?.let { c.inputAudioDevice = it }
        for (t in calls.values) {
            if (t.state == CallStateMsg.ENDED) continue
            t.call.outputAudioDevice = out
            input?.let { t.call.inputAudioDevice = it }
        }
    }

    private var telecomAudio: AudioMsg? = null

    private fun emitAudio() {
        if (TelecomBridge.hasConnections) telecomAudio?.let { msg -> listeners.forEach { it.onAudio(msg) }; return }
        val c = core ?: return
        val devices = c.audioDevices
        val available = devices
            .filter { it.hasCapability(AudioDevice.Capabilities.CapabilityPlay) }
            .mapNotNull { Mapping.route(it.type) }
            .distinct()
        val current = (c.currentCall?.outputAudioDevice ?: c.outputAudioDevice)?.let { Mapping.route(it.type) }
            ?: AudioRouteMsg.EARPIECE
        val msg = AudioMsg(current, available)
        listeners.forEach { it.onAudio(msg) }
    }

    private var ticks = 0

    private val levelTick = object : Runnable {
        override fun run() {
            val c = core ?: return
            val call = c.currentCall
            if (call != null && call.state == Call.State.StreamsRunning) {
                val level = if (c.isMicEnabled) call.recordVolume.toDouble() else SILENCE_DBM0
                listeners.forEach { it.onInputLevel(level) }
            }
            if (++ticks % QUALITY_EVERY_TICKS == 0) emitQuality()
            main.postDelayed(this, LEVEL_INTERVAL_MS)
        }
    }

    // ---------------------------------------------------------------- Telecom and push

    val hasLiveCall: Boolean get() = calls.values.any { it.state != CallStateMsg.ENDED }

    /** Engine commands from the system UI, headsets and cars, through Telecom. */
    private val telecomControl = object : TelecomBridge.Control {
        override fun execute(command: EngineCommand) {
            try {
                when (command) {
                    is EngineCommand.Answer -> answer(command.callId)
                    is EngineCommand.Decline -> decline(command.callId)
                    is EngineCommand.Hangup -> hangup(command.callId)
                    is EngineCommand.Hold -> hold(command.callId)
                    is EngineCommand.Resume -> resume(command.callId)
                    is EngineCommand.Dtmf -> sendDtmf(command.callId, command.digits)
                }
            } catch (e: VpFlutterError) {
                log("system command refused: ${e.code}")
            }
        }

        override fun onTelecomAudio(route: AudioRouteMsg, available: List<AudioRouteMsg>) {
            // Keep liblinphone's devices in step with Telecom's route.
            runCatching { applyLinphoneRoute(if (route == AudioRouteMsg.CAR) AudioRouteMsg.BLUETOOTH else route) }
            val msg = AudioMsg(route, available)
            telecomAudio = msg
            listeners.forEach { it.onAudio(msg) }
        }

        override fun onTelecomRefused(callId: String, incoming: Boolean) {
            val t = calls[callId] ?: return
            log("call $callId refused by Telecom")
            runCatching { if (incoming) decline(callId) else hangup(callId) }
            if (!incoming) t.intent = Mapping.LocalIntent.HANGUP
        }
    }

    /**
     * An `incoming_call` push: start the service and Core if they aren't, then
     * register with the stored account (same pn-prid), or refresh the
     * registration that is already there, so the platform relays the INVITE.
     */
    fun wakeForPush(context: Context) {
        requestStart(context, byApp = false) { error ->
            if (error != null) {
                log("push wake failed: ${error.javaClass.simpleName}")
                return@requestStart
            }
            // call_cancelled may have come while the service was starting.
            if (!startedByApp && !VpPush.get(context).wakeInProgress) {
                log("push wake no longer wanted")
                return@requestStart
            }
            val acc = account
            if (acc != null) {
                acc.refreshRegister()
                log("push wake: registration refreshed")
                return@requestStart
            }
            val record = CredentialStore(context).load()
            if (record == null) {
                log("push wake: no stored account")
                return@requestStart
            }
            try {
                register(
                    record.authUsername, record.password, record.domain, record.outboundProxy, record.displayName,
                    record.expiresSeconds, record.instanceId, record.pushProvider, record.pushPrid, record.pushParam,
                )
                log("push wake: registering")
            } catch (e: VpFlutterError) {
                log("push wake: register refused ${e.code}")
            }
        }
    }

    /**
     * A `signed_out` push (device revoked): forget the account and its stored
     * copy and stop, natively, whether or not Flutter is running. The app
     * still gets the push and shows AppSignedOut.
     */
    fun signOutFromPush(context: Context) {
        CredentialStore(context).clear()
        core?.let { dropAccount(it) }
        account = null
        domain = null
        scrubber.clearSecrets()
        log("signed out by push: account forgotten, engine stops")
        if (!hasLiveCall) requestStop(context) {}
    }

    /** After a push wake that brought no call (or `call_cancelled`): stop unless the app started us. */
    fun sleepAfterPush(context: Context) {
        if (startedByApp || hasLiveCall) return
        log("push wake over: engine stops")
        requestStop(context) {}
    }

    private fun currentRegistration(): RegistrationMsg = when (account?.state) {
        RegistrationState.Ok, RegistrationState.Refreshing -> RegistrationMsg(RegStateMsg.OK, sipCode = 200)
        RegistrationState.Progress -> RegistrationMsg(RegStateMsg.PROGRESS)
        RegistrationState.Failed -> RegistrationMsg(RegStateMsg.FAILED, RegFailureMsg.UNKNOWN)
        RegistrationState.Cleared -> RegistrationMsg(RegStateMsg.CLEARED)
        else -> RegistrationMsg(RegStateMsg.NONE)
    }

    /** Re-sends everything to a Flutter engine that attaches late (after a push wake). */
    fun syncState() {
        emitRegistration(currentRegistration())
        calls.values.filter { it.state != CallStateMsg.ENDED }.forEach { emitCall(it) }
        emitAudio()
    }

    /**
     * MOS hooks (v1.x): liblinphone's RTCP statistics for each connected call.
     * Jitter is the far end's report (ms), loss rates in percent, round trip
     * from RTCP (ms), and liblinphone's 0..5 quality estimate. Not sent anywhere.
     */
    private fun emitQuality() {
        for (t in calls.values) {
            if (t.state != CallStateMsg.CONNECTED) continue
            val stats = runCatching { t.call.audioStats }.getOrNull() ?: continue
            val msg = QualityMsg(
                callId = t.id,
                // No estimate yet (liblinphone gives a negative value): null, never 0.
                quality = t.call.currentQuality.toDouble().takeIf { it >= 0 },
                jitterMs = stats.receiverInterarrivalJitter.toDouble(),
                localLossPercent = stats.localLossRate.toDouble(),
                remoteLossPercent = stats.receiverLossRate.toDouble(),
                roundTripMs = stats.roundTripDelay.toDouble() * 1000,
            )
            listeners.forEach { it.onCallQuality(msg) }
        }
    }

    // ---------------------------------------------------------------- log export

    fun exportLastCallLog(): ByteArray = logFile?.export() ?: ByteArray(0)

    // ---------------------------------------------------------------- call tracking

    private fun track(call: Call): Tracked {
        val ptr = call.nativePointer
        idByPointer[ptr]?.let { id -> calls[id]?.let { return it } }
        val id = CallActionGate.randomCallId()
        val t = Tracked(id, call, call.dir == Call.Dir.Incoming, System.currentTimeMillis())
        calls[id] = t
        idByPointer[ptr] = id
        return t
    }

    private fun readHeaders(t: Tracked) {
        if (!t.incoming || t.hdrCalled != null || t.hdrAlsoRinging != null ||
            t.hdrRepeat != null || t.hdrLastAnswered != null
        ) {
            return
        }
        val remote = t.call.remoteParams ?: return
        t.hdrCalled = remote.getCustomHeader("X-VP-Called")
        t.hdrAlsoRinging = remote.getCustomHeader("X-VP-Also-Ringing")
        t.hdrRepeat = remote.getCustomHeader("X-VP-Repeat")
        t.hdrLastAnswered = remote.getCustomHeader("X-VP-Last-Answered")
    }

    private fun snapshot(t: Tracked): CallMsg {
        val c = core
        val call = t.call
        val remote = call.remoteAddress
        val number = remote.username?.takeIf { it.isNotBlank() } ?: "anonymous"
        val name = remote.displayName?.takeIf { it.isNotBlank() }
        val current = if (t.state == CallStateMsg.ENDED) null else call.currentParams
        val tls = account?.params?.transport == TransportType.Tls
        val srtp = current?.mediaEncryption == MediaEncryption.SRTP
        return CallMsg(
            id = t.id,
            incoming = t.incoming,
            state = t.state,
            remoteNumber = number,
            remoteName = name,
            startedAtMs = t.startedAt,
            connectedAtMs = t.connectedAt,
            muted = c?.isMicEnabled == false,
            encrypted = tls && srtp && t.connectedAt != null,
            hdAudio = Mapping.isHdCodec(current?.usedAudioPayloadType?.mimeType),
            endReason = t.endReason,
            headerCalled = t.hdrCalled,
            headerAlsoRinging = t.hdrAlsoRinging,
            headerRepeat = t.hdrRepeat,
            headerLastAnswered = t.hdrLastAnswered,
        )
    }

    private fun emitCall(t: Tracked) {
        val msg = snapshot(t)
        appContext?.let { TelecomBridge.onSnapshot(it, msg) }
        if (msg.state == CallStateMsg.CONNECTED) service?.setInCall(true, micGranted())
        listeners.forEach { it.onCall(msg) }
    }

    private fun onCallState(call: Call, state: Call.State) {
        val t = track(call)
        log("call ${t.id} $state")
        if (state == Call.State.Released) {
            calls.remove(t.id)
            idByPointer.remove(call.nativePointer)
            return
        }
        if (t.state == CallStateMsg.ENDED) return
        if (state == Call.State.IncomingReceived || state == Call.State.IncomingEarlyMedia) {
            readHeaders(t)
            if (!t.announced) {
                t.announced = true
                appContext?.let { ctx ->
                    VpPush.get(ctx).onCallArrived()
                    val remote = call.remoteAddress
                    TelecomBridge.addIncoming(
                        ctx,
                        TelecomBridge.CallInfo(
                            t.id,
                            true,
                            remote.username?.takeIf { it.isNotBlank() } ?: "anonymous",
                            remote.displayName?.takeIf { it.isNotBlank() },
                        ),
                    )
                }
            }
        }
        var mapped = Mapping.callState(state) ?: return
        if (mapped == CallStateMsg.CONNECTED && t.connectedAt == null) t.connectedAt = System.currentTimeMillis()
        if (t.transferring && mapped != CallStateMsg.ENDED) mapped = CallStateMsg.TRANSFERRING
        t.state = mapped
        if (mapped == CallStateMsg.ENDED) {
            val ei = call.errorInfo
            t.endReason = Mapping.endReason(
                Mapping.EndFacts(
                    incoming = t.incoming,
                    wasConnected = t.connectedAt != null,
                    localIntent = t.intent,
                    finalState = state,
                    logStatus = call.callLog.status,
                    reason = call.reason,
                    protocol = ei.protocol,
                    protocolCode = ei.protocolCode,
                ),
            )
            log("call ${t.id} ended ${t.endReason}")
        }
        emitCall(t)
    }

    private val coreListener = object : CoreListenerStub() {
        override fun onAccountRegistrationStateChanged(
            core: Core,
            account: Account,
            state: RegistrationState?,
            message: String,
        ) {
            if (state != null) onRegistrationState(account, state)
        }

        override fun onCallStateChanged(core: Core, call: Call, state: Call.State?, message: String) {
            if (state != null) onCallState(call, state)
        }

        override fun onTransferStateChanged(core: Core, transferred: Call, callState: Call.State?) {
            val id = idByPointer[transferred.nativePointer] ?: return
            val t = calls[id] ?: return
            log("call ${t.id} transfer $callState")
            if (callState == Call.State.Error && t.transferring) {
                t.transferring = false
                t.intent = null
                t.state = Mapping.callState(transferred.state) ?: t.state
                emitCall(t)
            }
        }

        override fun onFirstCallStarted(core: Core) {
            logFile?.beginCall()
            // phoneCall only while ringing or dialling; microphone is added once
            // a call is connected (the app may be in the background until then).
            service?.setInCall(true, false)
            main.removeCallbacks(levelTick)
            main.post(levelTick)
        }

        override fun onLastCallEnded(core: Core) {
            main.removeCallbacks(levelTick)
            service?.setInCall(false, false)
            // A few seconds more so the call's teardown is in the log.
            main.postDelayed({ logFile?.endCall() }, 3000)
        }

        override fun onAudioDevicesListUpdated(core: Core) = emitAudio()

        override fun onAudioDeviceChanged(core: Core, audioDevice: AudioDevice) = emitAudio()

        override fun onNetworkReachable(core: Core, reachable: Boolean) {
            log("network reachable $reachable")
        }
    }
}
