package au.com.voiceplatform.vp_linphone

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.VisibleForTesting
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ListenableWorker
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.google.android.gms.tasks.Tasks
import com.google.firebase.messaging.FirebaseMessaging
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * BOOT_COMPLETED and MY_PACKAGE_REPLACED: queue [ReregisterWorker]. Nothing
 * else runs here, and no service is started (see [BackgroundRegistration]).
 * Not LOCKED_BOOT_COMPLETED: the app isn't direct-boot aware, and the stored
 * account (noBackupFilesDir, an Android Keystore key) can't be read before
 * the first unlock anyway; BOOT_COMPLETED comes right after it.
 */
class ReregisterReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reason = ReregisterWork.reasonFor(intent.action) ?: return
        ReregisterWork.enqueue(context, reason)
    }
}

object ReregisterWork {
    const val UNIQUE_NAME = "vp_linphone_reregister"
    const val KEY_REASON = "reason"
    const val REASON_BOOT = "boot"
    const val REASON_UPDATE = "update"
    const val REASON_REGISTER_FAILED = "register_failed"

    /** The job's own attempts before it gives up; the next push, boot, update or app start registers anyway. */
    const val MAX_ATTEMPTS = 5

    fun reasonFor(action: String?): String? = when (action) {
        Intent.ACTION_BOOT_COMPLETED -> REASON_BOOT
        Intent.ACTION_MY_PACKAGE_REPLACED -> REASON_UPDATE
        else -> null
    }

    /**
     * One job, as soon as there is a network. Expedited on Android 12+ (a
     * JobScheduler expedited job: no foreground service, no notification);
     * below 12 WorkManager would run expedited work as a foreground service,
     * so there it is a plain job.
     */
    fun request(reason: String, sdkInt: Int = Build.VERSION.SDK_INT): OneTimeWorkRequest {
        val b = OneTimeWorkRequestBuilder<ReregisterWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setInputData(workDataOf(KEY_REASON to reason))
            .addTag(UNIQUE_NAME)
        if (sdkInt >= Build.VERSION_CODES.S) b.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
        return b.build()
    }

    /**
     * The app's own register (right after `POST /devices/me/sip-credentials`,
     * which rotated the password): if it throws, queue the job, which
     * registers the stored account (kept with the new password before the
     * register ran) without another POST, so the phone isn't left
     * unreachable until the app is next opened. The error still goes to
     * the app. The job itself never comes through here, so it can't queue
     * itself.
     */
    fun <T> registerOrQueue(context: Context, register: () -> T): T =
        try {
            register()
        } catch (e: Exception) {
            enqueue(context, REASON_REGISTER_FAILED)
            throw e
        }

    /** KEEP: a boot and an update close together make one job, and a running one isn't cut short. */
    fun enqueue(context: Context, reason: String) {
        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(UNIQUE_NAME, ExistingWorkPolicy.KEEP, request(reason))
    }

    fun result(outcome: BackgroundRegistration.Outcome, runAttemptCount: Int): ListenableWorker.Result =
        when (outcome) {
            BackgroundRegistration.Outcome.REGISTERED,
            BackgroundRegistration.Outcome.ENGINE_RUNNING,
            BackgroundRegistration.Outcome.NO_ACCOUNT -> ListenableWorker.Result.success()
            BackgroundRegistration.Outcome.REFUSED -> ListenableWorker.Result.failure()
            BackgroundRegistration.Outcome.FAILED,
            BackgroundRegistration.Outcome.ENGINE_STARTING ->
                if (runAttemptCount + 1 < MAX_ATTEMPTS) ListenableWorker.Result.retry() else ListenableWorker.Result.failure()
        }
}

/**
 * Checks the FCM token, then registers the stored account once
 * ([LinphoneEngine.refreshInBackground]). Runs on WorkManager's own job,
 * never in a foreground service.
 */
class ReregisterWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    /** The two steps, replaced in tests. */
    interface Steps {
        /** Today's FCM token, or null (no Play services, no Firebase config, no answer). */
        suspend fun fcmToken(): String?
        suspend fun register(fcmToken: String?): BackgroundRegistration.Outcome
    }

    override suspend fun doWork(): Result {
        val s = steps(applicationContext)
        val token = s.fcmToken()
        val outcome = s.register(token)
        LinphoneEngine.logLine(
            "ENGINE",
            "background registration (${inputData.getString(ReregisterWork.KEY_REASON)}, attempt ${runAttemptCount + 1}): $outcome",
        )
        return ReregisterWork.result(outcome, runAttemptCount)
    }

    companion object {
        private const val TOKEN_TIMEOUT_MS = 20_000L
        private const val REGISTER_TIMEOUT_MS = 45_000L

        @Volatile
        @VisibleForTesting
        internal var steps: (Context) -> Steps = { EngineSteps(it) }
    }

    private class EngineSteps(private val context: Context) : Steps {
        private val main = Handler(Looper.getMainLooper())

        override suspend fun fcmToken(): String? = withContext(Dispatchers.IO) {
            runCatching {
                // The registration token, as the Dart side uses (VpPushTokens).
                Tasks.await(FirebaseMessaging.getInstance().token, TOKEN_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            }.getOrNull()?.takeIf { it.isNotBlank() }
        }

        override suspend fun register(fcmToken: String?): BackgroundRegistration.Outcome =
            withContext(Dispatchers.Main) {
                LinphoneEngine.attach(context)
                withTimeoutOrNull(REGISTER_TIMEOUT_MS) {
                    suspendCancellableCoroutine { cont ->
                        // WorkManager stopped the job (or the timeout): the Core of our own goes.
                        cont.invokeOnCancellation {
                            main.post { LinphoneEngine.endBackgroundRefresh(BackgroundRegistration.Outcome.FAILED) }
                        }
                        LinphoneEngine.refreshInBackground(context, fcmToken) { if (cont.isActive) cont.resume(it) }
                    }
                } ?: run {
                    LinphoneEngine.endBackgroundRefresh(BackgroundRegistration.Outcome.FAILED)
                    BackgroundRegistration.Outcome.FAILED
                }
            }
    }
}
