package au.com.voiceplatform.app

import au.com.voiceplatform.app.keys.DeviceKeyStore
import au.com.voiceplatform.app.keys.DeviceKeysApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity: local_auth (biometric unlock) needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DeviceKeysApi.setUp(flutterEngine.dartExecutor.binaryMessenger, DeviceKeyStore(applicationContext))
    }
}
