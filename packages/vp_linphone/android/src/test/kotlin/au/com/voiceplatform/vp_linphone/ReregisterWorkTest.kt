package au.com.voiceplatform.vp_linphone

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.NetworkType
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.testing.WorkManagerTestInitHelper
import au.com.voiceplatform.vp_linphone.BackgroundRegistration.Outcome
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The receiver queues the job (WorkManager's test helpers, on Robolectric),
 * and the worker turns each outcome into its result. The registration itself
 * (liblinphone, the edge) is replaced by [ReregisterWorker.Steps].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReregisterWorkTest {

    private lateinit var context: Context
    private val defaultSteps = ReregisterWorker.steps

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            Configuration.Builder().setMinimumLoggingLevel(Log.DEBUG).setExecutor(SynchronousExecutor()).build(),
        )
    }

    @After
    fun tearDown() {
        ReregisterWorker.steps = defaultSteps
    }

    private fun queued(): List<WorkInfo> =
        WorkManager.getInstance(context).getWorkInfosForUniqueWork(ReregisterWork.UNIQUE_NAME).get()

    private fun receive(action: String) = ReregisterReceiver().onReceive(context, Intent(action))

    @Test
    fun bootQueuesOneJobThatWaitsForANetwork() {
        receive(Intent.ACTION_BOOT_COMPLETED)
        val infos = queued()
        assertEquals(1, infos.size)
        assertEquals(WorkInfo.State.ENQUEUED, infos[0].state)
        assertEquals(NetworkType.CONNECTED, infos[0].constraints.requiredNetworkType)
        assertTrue(ReregisterWork.UNIQUE_NAME in infos[0].tags)
    }

    @Test
    fun anAppUpdateQueuesTheJobToo() {
        receive(Intent.ACTION_MY_PACKAGE_REPLACED)
        assertEquals(1, queued().size)
    }

    @Test
    fun otherBroadcastsQueueNothing() {
        receive(Intent.ACTION_LOCKED_BOOT_COMPLETED)
        receive(Intent.ACTION_PACKAGE_REPLACED)
        receive(Intent.ACTION_TIME_CHANGED)
        assertTrue(queued().isEmpty())
    }

    @Test
    fun aBootAndAnUpdateTogetherMakeOneJob() {
        receive(Intent.ACTION_BOOT_COMPLETED)
        val first = queued().single().id
        receive(Intent.ACTION_MY_PACKAGE_REPLACED)
        assertEquals(first, queued().single().id)
    }

    @Test
    fun theJobRunsOnceTheNetworkIsUp() {
        val ran = mutableListOf<String?>()
        ReregisterWorker.steps = { fake(token = "token-2", outcome = Outcome.REGISTERED, seen = ran) }
        receive(Intent.ACTION_BOOT_COMPLETED)
        val id = queued().single().id
        WorkManagerTestInitHelper.getTestDriver(context)!!.setAllConstraintsMet(id)
        // A CoroutineWorker finishes on its own dispatcher, not the synchronous executor.
        val deadline = System.currentTimeMillis() + 5_000
        while (!queued().single().state.isFinished && System.currentTimeMillis() < deadline) Thread.sleep(20)
        assertEquals(WorkInfo.State.SUCCEEDED, queued().single().state)
        assertEquals(listOf<String?>("token-2"), ran)
    }

    @Test
    fun expeditedOnAndroid12AndLaterOnlyNeverAForegroundService() {
        assertTrue(ReregisterWork.request(ReregisterWork.REASON_BOOT, sdkInt = 35).workSpec.expedited)
        assertTrue(ReregisterWork.request(ReregisterWork.REASON_BOOT, sdkInt = 31).workSpec.expedited)
        // Below 12 WorkManager would run expedited work as a foreground service.
        assertFalse(ReregisterWork.request(ReregisterWork.REASON_BOOT, sdkInt = 30).workSpec.expedited)
        assertFalse(ReregisterWork.request(ReregisterWork.REASON_BOOT, sdkInt = 29).workSpec.expedited)
    }

    @Test
    fun theReasonTravelsWithTheJob() {
        val r = ReregisterWork.request(ReregisterWork.REASON_UPDATE)
        assertEquals(ReregisterWork.REASON_UPDATE, r.workSpec.input.getString(ReregisterWork.KEY_REASON))
    }

    private fun fake(token: String?, outcome: Outcome, seen: MutableList<String?> = mutableListOf()) =
        object : ReregisterWorker.Steps {
            override suspend fun fcmToken() = token
            override suspend fun register(fcmToken: String?): Outcome {
                seen += fcmToken
                return outcome
            }
        }

    private fun runWorker(outcome: Outcome, attempt: Int = 0, token: String? = "token-1"): ListenableWorker.Result {
        ReregisterWorker.steps = { fake(token, outcome) }
        val worker = TestListenableWorkerBuilder<ReregisterWorker>(context).setRunAttemptCount(attempt).build()
        return runBlocking { worker.doWork() }
    }

    @Test
    fun registeredEngineRunningOrSignedOutAreDone() {
        assertEquals(ListenableWorker.Result.success(), runWorker(Outcome.REGISTERED))
        assertEquals(ListenableWorker.Result.success(), runWorker(Outcome.ENGINE_RUNNING))
        assertEquals(ListenableWorker.Result.success(), runWorker(Outcome.NO_ACCOUNT))
    }

    @Test
    fun aStartingEngineIsCheckedAgainOnTheNextAttempt() {
        assertEquals(ListenableWorker.Result.retry(), runWorker(Outcome.ENGINE_STARTING))
        assertEquals(
            ListenableWorker.Result.failure(),
            runWorker(Outcome.ENGINE_STARTING, ReregisterWork.MAX_ATTEMPTS - 1),
        )
    }

    @Test
    fun theNotYetSentFlagIsKeptUntilTheAppSendsTheToken() {
        assertFalse(PushTokenFlag.isUnsent(context))
        PushTokenFlag.setUnsent(context)
        assertTrue(PushTokenFlag.isUnsent(context))
        PushTokenFlag.markSent(context)
        assertFalse(PushTokenFlag.isUnsent(context))
    }

    @Test
    fun aRefusedAccountIsNotTriedAgain() {
        assertEquals(ListenableWorker.Result.failure(), runWorker(Outcome.REFUSED))
    }

    @Test
    fun aFailureIsRetriedUpToFiveAttempts() {
        for (attempt in 0 until ReregisterWork.MAX_ATTEMPTS - 1) {
            assertEquals(ListenableWorker.Result.retry(), runWorker(Outcome.FAILED, attempt))
        }
        assertEquals(ListenableWorker.Result.failure(), runWorker(Outcome.FAILED, ReregisterWork.MAX_ATTEMPTS - 1))
    }

    @Test
    fun theTokenCheckFeedsTheRegistration() {
        val seen = mutableListOf<String?>()
        ReregisterWorker.steps = { fake(token = null, outcome = Outcome.REGISTERED, seen = seen) }
        val worker = TestListenableWorkerBuilder<ReregisterWorker>(context).build()
        runBlocking { worker.doWork() }
        assertEquals(listOf<String?>(null), seen)
    }
}
