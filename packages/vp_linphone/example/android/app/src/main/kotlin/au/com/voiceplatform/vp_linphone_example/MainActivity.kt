package au.com.voiceplatform.vp_linphone_example

import android.os.Handler
import android.os.Looper
import au.com.voiceplatform.vp_linphone.AudioRouteMsg
import au.com.voiceplatform.vp_linphone.CallMsg
import au.com.voiceplatform.vp_linphone.CallStateMsg
import au.com.voiceplatform.vp_linphone.EndReasonMsg
import au.com.voiceplatform.vp_linphone.EngineCommand
import au.com.voiceplatform.vp_linphone.TelecomBridge
import au.com.voiceplatform.vp_linphone.VpPush
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bench hooks for exercising Telecom on a real phone without SIP: a fake
 * engine stands in for liblinphone behind TelecomBridge, so the system UI,
 * the lock screen, Bluetooth and the notification drive fake calls. Example
 * app only; nothing here is in the plugin's API to the app.
 */
class MainActivity : FlutterActivity() {
    private val log = mutableListOf<String>()
    private val states = HashMap<String, Pair<Boolean, CallStateMsg>>()
    private val main = Handler(Looper.getMainLooper())

    private fun note(s: String) {
        log += s
        if (log.size > 200) log.removeAt(0)
    }

    private fun snapshot(id: String, state: CallStateMsg, end: EndReasonMsg? = null) {
        val incoming = states[id]?.first ?: true
        states[id] = incoming to state
        note("fake $id ${state.name}${end?.let { " $it" } ?: ""}")
        TelecomBridge.onSnapshot(
            this,
            CallMsg(
                id = id, incoming = incoming, state = state, remoteNumber = "0491570737", remoteName = "Ava Nguyen",
                startedAtMs = System.currentTimeMillis(), muted = false, encrypted = false, hdAudio = false, endReason = end,
            ),
        )
    }

    private val fake = object : TelecomBridge.Control {
        override fun execute(command: EngineCommand) {
            note("system command $command")
            when (command) {
                is EngineCommand.Answer -> snapshot(command.callId, CallStateMsg.CONNECTED)
                is EngineCommand.Decline -> snapshot(command.callId, CallStateMsg.ENDED, EndReasonMsg.DECLINED)
                is EngineCommand.Hangup -> snapshot(command.callId, CallStateMsg.ENDED, EndReasonMsg.LOCAL)
                is EngineCommand.Hold -> snapshot(command.callId, CallStateMsg.HELD_BY_ME)
                is EngineCommand.Resume -> snapshot(command.callId, CallStateMsg.CONNECTED)
                is EngineCommand.Dtmf -> {}
            }
        }

        override fun onTelecomAudio(route: AudioRouteMsg, available: List<AudioRouteMsg>) =
            note("telecom audio $route of $available")

        override fun onTelecomRefused(callId: String, incoming: Boolean) {
            note("telecom refused $callId")
            snapshot(callId, CallStateMsg.ENDED, EndReasonMsg.FAILED)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vp_linphone_example/bench").setMethodCallHandler { call, result ->
            val id = call.argument<String>("id") ?: "fake-1"
            when (call.method) {
                "fakeIncoming" -> {
                    TelecomBridge.control = fake
                    states[id] = true to CallStateMsg.INCOMING
                    val delay = (call.argument<Int>("delayMs") ?: 0).toLong()
                    main.postDelayed({
                        TelecomBridge.addIncoming(applicationContext, TelecomBridge.CallInfo(id, true, "0491570737", "Ava Nguyen"))
                        note("fake $id incoming")
                    }, delay)
                    result.success(null)
                }
                "fakeOutgoing" -> {
                    TelecomBridge.control = fake
                    val number = call.argument<String>("number") ?: "0355501201"
                    states[id] = false to CallStateMsg.DIALLING
                    try {
                        TelecomBridge.placeOutgoing(this, TelecomBridge.CallInfo(id, false, number, null))
                        main.postDelayed({ snapshot(id, CallStateMsg.CONNECTED) }, 2000)
                        result.success(null)
                    } catch (e: Exception) {
                        note("outgoing refused: ${e.message}")
                        result.error("refused", e.message, null)
                    }
                }
                "fakeRemoteEnd" -> {
                    snapshot(id, CallStateMsg.ENDED, EndReasonMsg.REMOTE)
                    result.success(null)
                }
                "fakeAnsweredElsewhere" -> {
                    snapshot(id, CallStateMsg.ENDED, EndReasonMsg.ANSWERED_ELSEWHERE)
                    result.success(null)
                }
                "simulatePush" -> {
                    val type = call.argument<String>("type") ?: "incoming_call"
                    result.success(VpPush.simulate(this, type, "bench-${System.nanoTime()}"))
                }
                "log" -> result.success(log.toList())
                else -> result.notImplemented()
            }
        }
    }
}
