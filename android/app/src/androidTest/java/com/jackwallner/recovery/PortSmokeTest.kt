package com.jackwallner.recovery

import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.provider.MediaStore
import java.time.Instant

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.*
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

import com.jackwallner.recovery.data.*
import com.jackwallner.recovery.model.*

@RunWith(AndroidJUnit4::class)
class PortSmokeTest {
    @get:Rule val compose = createEmptyComposeRule()
    private var scenario: ActivityScenario<MainActivity>? = null
    private val app get() = ApplicationProvider.getApplicationContext<RechargeApplication>()
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    private fun launch(pro: Boolean = false, seed: Boolean = true, onboarding: Boolean = false, scene: String = "recovering", dark: Boolean = false) {
        val intent = Intent(app, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra("uiTest", true).putExtra("skipOnboarding", !onboarding)
            .putExtra("seedScreenshotData", seed).putExtra("forcePro", pro)
            .putExtra("scene", scene).putExtra("appearance", if (dark) "dark" else "light")
        scenario = ActivityScenario.launch(intent)
        compose.waitForIdle()
    }
    private fun click(text: String) {
        val node = compose.onNodeWithText(text)
        if (!node.isDisplayed()) node.performScrollTo()
        node.performClick()
        compose.waitForIdle()
    }
    private fun tab(index: Int) { compose.onNodeWithTag("tab-$index").performClick(); compose.waitForIdle() }
    private fun screenshot(name: String) {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "$name.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/sol-recharge")
        }
        val uri = app.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)!!
        app.contentResolver.openOutputStream(uri)!!.use {
            instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it)
        }
    }
    @After fun close() { scenario?.close() }

    @Test fun reviewerAccessRejectsWrongCodeAndPersistsValidGrant() = runBlocking {
        val code = checkNotNull(InstrumentationRegistry.getArguments().getString("reviewCode")) { "Supply the private reviewer code through the local test harness." }
        launch(seed = false)
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithText("Version 1.1.0 · Model v17").performScrollTo().performTouchInput { longClick() }
        compose.onNodeWithText("Reviewer code").performTextInput("wrong")
        click("Unlock")
        compose.onNodeWithText("That code isn't valid.").assertIsDisplayed()
        assertFalse(app.graph.store.current.isPro)
        compose.onNodeWithText("Reviewer code").performTextClearance()
        compose.onNodeWithText("Reviewer code").performTextInput(code)
        click("Unlock")
        assertTrue(app.graph.store.current.isPro)
        app.graph.store.start()
        assertTrue(app.graph.store.current.isPro)
        assertTrue(StoreService(app, app.graph.diagnostics).current.isPro)
    }

    @Test fun firstRunCanCompleteWithoutAccessOrPurchase() {
        launch(seed = false, onboarding = true)
        compose.onNodeWithText("Recovery time,\nfrom your workouts").assertIsDisplayed()
        click("Continue")
        // The real Health Connect permission request is dismissed with Back.
        click("Continue")
        androidx.test.uiautomator.UiDevice.getInstance(instrumentation).pressBack()
        compose.waitUntil(15000) { compose.onAllNodesWithText("Skip this one").fetchSemanticsNodes().isNotEmpty() }
        repeat(4) { click("Skip this one") }
        click("I understand")
        click("Get Started")
        compose.onNodeWithTag("tab-0").assertIsDisplayed()
        assertFalse(app.graph.store.current.isPro)
        screenshot("01-empty")
    }
    @Test fun freeCountdownRendersWithoutPaidNumber() {
        launch()
        compose.onNodeWithText("left").assertIsDisplayed()
        compose.onNodeWithContentDescription("Hidden until you upgrade").performScrollTo().assertExists()
        assertFalse(app.graph.store.current.isPro)
        screenshot("02-today")
    }
    @Test fun readySceneHasNoOutstandingCountdown() {
        launch(scene = "ready")
        compose.onNodeWithText("Ready").assertIsDisplayed()
        compose.onNodeWithText("Recovery estimate complete.").assertIsDisplayed()
        screenshot("03-ready")
    }
    @Test fun staleWorkoutDoesNotNarrateLiveWindow() {
        launch(scene = "stale")
        compose.onNodeWithText("No recent workout").assertIsDisplayed()
        compose.onAllNodesWithText("left").assertCountEquals(0)
    }
    @Test fun historyShowsEveryScoredSessionAndOpensDetail() {
        launch(); tab(1)
        compose.onAllNodesWithText("Run").onFirst().performClick()
        compose.onNodeWithText("Why").performScrollTo().assertIsDisplayed()
        screenshot("04-detail")
        compose.onNodeWithContentDescription("Back").performClick()
        compose.onAllNodesWithText("History").assertCountEquals(2)
        compose.onAllNodesWithText("History").onFirst().assertIsDisplayed()
        screenshot("05-history")
    }
    @Test fun freeSessionCorrectionOpensPaywall() {
        launch(); tab(1)
        compose.onAllNodesWithText("Run").onFirst().performClick()
        click("Correct this session")
        compose.onNodeWithText("Personalized recovery from your history.").assertIsDisplayed()
        compose.onNodeWithText("Continue with Recharge+").assertIsDisplayed()
    }
    @Test fun weakStrengthEffortAnswerIsFreeAndRecalculates() {
        launch(scene = "effort")
        val before = app.graph.health.state.value.scored.awaitingEffort
        assertNotNull(before)
        click("How hard was your lifting session?")
        click("Hard")
        compose.waitUntil(15000) { app.graph.health.state.value.workouts.any { it.id == before!!.id && it.reportedEffort == 9.0 } }
        assertFalse(app.graph.store.current.isPro)
        assertNull(app.graph.health.state.value.scored.awaitingEffort)
    }
    @Test fun subscriberHubHasAnalysisAndReceiptInDarkMode() {
        launch(pro = true, dark = true); tab(2)
        compose.onNodeWithText("Recharge+ active").assertIsDisplayed()
        screenshot("06-plus-dark")
        compose.onNodeWithText("Read from Health Connect").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Heart rate variability (RMSSD)").performScrollTo().assertIsDisplayed()
        screenshot("07-receipt-dark")
    }
    @Test fun subscriberCorrectionRecalculatesAndCanReset() {
        launch(pro = true); tab(1)
        compose.onAllNodesWithText("Run").onFirst().performClick()
        click("Light")
        compose.waitUntil(15000) { app.graph.health.state.value.workouts.any { it.intensityOverride == SessionIntensity.light } }
        click("Use Recharge's")
        compose.waitUntil(15000) { app.graph.health.state.value.workouts.none { it.intensityOverride != null } }
    }
    @Test fun subscriberCanPinRecoveryHours() {
        launch(pro = true)
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onAllNodesWithText("Moderate").onFirst().performScrollTo().performClick()
        click("30h")
        assertEquals(30.0, app.graph.settings.manualWindows.moderate!!, 0.0)
    }
    @Test fun freeSettingsKeepsReadyAlertAndSeparateFeedback() {
        launch(); compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithText("Notify me when countdown ends").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Rate Recharge").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Send feedback").performScrollTo().assertIsDisplayed()
        compose.onAllNodesWithText("Your own recharge times").assertCountEquals(0)
    }
    @Test fun appearanceChangesAndSurvivesRecreation() {
        launch(); compose.onNodeWithContentDescription("Settings").performClick()
        click("Appearance"); click("Dark")
        assertEquals(2, app.graph.settings.appearance)
        scenario!!.onActivity { it.intent.removeExtra("appearance") }
        scenario!!.recreate(); compose.waitForIdle()
        assertEquals(2, app.graph.settings.appearance)
        screenshot("08-settings")
    }
    @Test fun maximumHeartRateRejectsInvalidInput() {
        launch(); compose.onNodeWithContentDescription("Settings").performClick()
        click("Max heart rate")
        compose.onNodeWithText("Maximum heart rate").performTextInput("999")
        compose.onNodeWithText("Save").assertIsNotEnabled()
        click("Cancel")
    }
    @Test fun actualHealthConnectReadsAllGrantedTypesWithoutInventingWorkouts() {
        val service = app.graph.health
        val permissions = service.permissions().filter { it != HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY }
        permissions.forEach { instrumentation.uiAutomation.grantRuntimePermission(app.packageName, it) }
        instrumentation.waitForIdleSync()
        runBlocking { service.refresh() }
        val state = service.state.value
        assertTrue("${state.status}; ${state.error}", state.granted.containsAll(permissions))
        assertNull(state.error)
        assertFalse(state.lastImportFailed)
        assertTrue(state.workouts.isEmpty())
        assertTrue(state.scored.estimates.isEmpty())
        assertNotNull(state.updated)
        assertTrue(app.getFileStreamPath("recovery-cache.json").exists())
    }
    @Test fun actualSharedWorkoutIsReadScoredAndPersisted() {
        val service = app.graph.health
        val writerContext = instrumentation.context
        listOf("android.permission.health.WRITE_EXERCISE", "android.permission.health.WRITE_HEART_RATE").forEach {
            instrumentation.uiAutomation.grantRuntimePermission(writerContext.packageName, it)
        }
        listOf(ExerciseSessionRecord::class, HeartRateRecord::class).forEach {
            instrumentation.uiAutomation.grantRuntimePermission(app.packageName, HealthPermission.getReadPermission(it))
        }
        runBlocking {
            writeHealthFixture("seed")
            try {
                service.refresh()
                val state = service.state.value
                assertNull(state.error)
                val record = state.workouts.single { it.source == writerContext.packageName }
                assertEquals(50.0, record.minutes, 0.0)
                assertEquals(155.0, record.averageHR!!, 0.0)
                assertTrue(record.coverage >= 0.95)
                val estimate = state.scored.estimates.single { it.sessionID == record.id }
                assertTrue(estimate.hours >= 6.0)
                assertEquals(LoadSource.heartRate, estimate.load.source)
                val saved = JSONObject(app.getFileStreamPath("recovery-cache.json").readText())
                assertEquals(record.id, saved.getJSONArray("workouts").getJSONObject(0).getString("id"))
            } finally {
                writeHealthFixture("clear")
            }
        }
    }
    private suspend fun writeHealthFixture(operation: String) {
        val result = kotlinx.coroutines.CompletableDeferred<String?>()
        val request = java.util.UUID.randomUUID().toString()
        val receiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context, intent: Intent) {
                if (intent.getStringExtra("request") == request) result.complete(intent.getStringExtra("error"))
            }
        }
        androidx.core.content.ContextCompat.registerReceiver(app, receiver,
            android.content.IntentFilter(FixtureWriterActivity.RESULT_ACTION),
            androidx.core.content.ContextCompat.RECEIVER_EXPORTED)
        try {
            app.startActivity(Intent().setClassName(instrumentation.context.packageName, FixtureWriterActivity::class.java.name)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("operation", operation).putExtra("request", request))
            val error = kotlinx.coroutines.withTimeout(90_000) { result.await() }
            assertNull("Fixture writer: $error", error)
        } finally { app.unregisterReceiver(receiver) }
    }

    @Test fun optionalRevocationSanitizesPersistedInputsAndRecalculates() {
        val core = HealthPermission.getReadPermission(ExerciseSessionRecord::class)
        instrumentation.uiAutomation.grantRuntimePermission(app.packageName, core)
        val now = Instant.now()
        val workout = WorkoutRecord("cache-fixture", 37, now.hoursAfter(-2.0), now.hoursAfter(-1.0), 60.0, 600.0, 160.0, 185.0, 0.98)
        val day = DailyContext(now, 8.0, 50.0, 55.0, 13.0)
        val prior = RecoveryEngine.score(listOf(workout), listOf(day), app.graph.settings.modelOptions(false))
        val cache = JSONObject().put("workouts", JSONArray(listOf(CacheCodec.workout(workout))))
            .put("days", JSONArray(listOf(CacheCodec.day(day))))
            .put("estimates", JSONArray(prior.estimates.map(CacheCodec::estimate)))
            .put("granted", JSONArray(listOf(core, HealthPermission.getReadPermission(HeartRateRecord::class))))
            .put("updated", now.toString())
        app.getFileStreamPath("recovery-cache.json").writeText(cache.toString())
        runBlocking { app.graph.health.refresh(cachedOnly = true) }
        val state = app.graph.health.state.value
        assertNull(state.workouts.single().averageHR)
        assertNull(state.workouts.single().energy)
        assertEquals(0.0, state.workouts.single().coverage, 0.0)
        assertNull(state.days.single().sleep)
        assertNull(state.days.single().hrv)
        assertFalse(state.scored.estimates.single().load.source == LoadSource.heartRate)
        assertEquals(setOf(core), state.granted)
    }
    @Test fun noWorkoutPermissionRemovesCacheAndDerivedProfile() {
        app.getFileStreamPath("recovery-cache.json").writeText("{}")
        app.graph.settings.updateProfile(AthleteProfile(age = 40, vo2Max = 55.0, healthDerivedFields = setOf("vo2Max")))
        runBlocking { app.graph.health.refresh() }
        assertFalse(app.getFileStreamPath("recovery-cache.json").exists())
        assertNull(app.graph.settings.profile.vo2Max)
        assertEquals(40, app.graph.settings.profile.age)
        assertTrue(app.graph.health.state.value.scored.estimates.isEmpty())
    }
    @Test fun readyNotificationIsFreeAndDoesNotRepeat() {
        launch(scene = "ready")
        instrumentation.uiAutomation.grantRuntimePermission(app.packageName, "android.permission.POST_NOTIFICATIONS")
        val graph = app.graph
        graph.notifications.deliver(graph.health.state.value)
        val manager = app.getSystemService(android.app.NotificationManager::class.java)
        assertTrue(graph.notifications.allowed())
        compose.waitUntil(15_000) { manager.activeNotifications.any { it.id == 4101 } }
        graph.notifications.schedule(graph.health.state.value)
        assertTrue("Refreshing a finished countdown must preserve the Ready alert", manager.activeNotifications.any { it.id == 4101 })
        val notification = manager.activeNotifications.single { it.id == 4101 }
        assertEquals("Ready", notification.notification.extras.getString(android.app.Notification.EXTRA_TITLE))
        assertFalse(graph.store.current.isPro)
        val token = graph.values.string("lastReadyNotification")
        assertNotNull(token)
        manager.cancel(4101)
        compose.waitUntil(15_000) { manager.activeNotifications.none { it.id == 4101 } }
        graph.notifications.deliver(graph.health.state.value)
        assertTrue(manager.activeNotifications.none { it.id == 4101 })
    }
    @Test fun disabledReadyNotificationIsNotDelivered() {
        launch(scene = "ready")
        instrumentation.uiAutomation.grantRuntimePermission(app.packageName, "android.permission.POST_NOTIFICATIONS")
        app.graph.settings.setNotifications(false)
        app.graph.notifications.deliver(app.graph.health.state.value)
        assertTrue(app.getSystemService(android.app.NotificationManager::class.java).activeNotifications.none { it.id == 4101 })
    }
    @Test fun deleteLocalDataKeepsProfileAndPurchases() {
        launch(pro = true)
        runBlocking { app.graph.health.deleteLocalData() }
        assertTrue(app.graph.health.state.value.workouts.isEmpty())
        assertTrue(app.graph.store.current.isPro)
        assertEquals(35, app.graph.settings.profile.age)
        assertNull(app.graph.settings.profile.vo2Max)
    }
}
