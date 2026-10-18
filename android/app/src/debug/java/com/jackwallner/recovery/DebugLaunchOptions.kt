package com.jackwallner.recovery

import android.content.Intent
import java.time.Instant
import java.time.ZoneId

import androidx.activity.ComponentActivity

import com.jackwallner.recovery.model.*

object DebugLaunchOptions {
    fun apply(activity: ComponentActivity, graph: AppGraph, intent: Intent?) {
        if (intent == null) return
        if (intent.getBooleanExtra("uiTest", false)) {
            graph.review.isAutomationRun = true
            graph.values.put("hasRequestedReadyNotifications", "true")
        }
        if (intent.getBooleanExtra("forcePro", false)) graph.store.forceProForDebug()
        if (intent.getBooleanExtra("skipOnboarding", false)) graph.settings.completeSetup()
        intent.getStringExtra("appearance")?.let {
            graph.settings.updateAppearance(when (it) { "light" -> 1; "dark" -> 2; else -> 0 })
        }
        graph.initialTab = intent.getIntExtra("tab", 0).coerceIn(0, 2)
        if (!intent.getBooleanExtra("seedScreenshotData", false)) return

        graph.settings.setDeferredHealth(false)
        val now = Instant.now()
        val zone = ZoneId.systemDefault()
        val scene = intent.getStringExtra("scene") ?: "recovering"
        graph.settings.updateProfile(AthleteProfile(
            age = 35, sex = AthleteSex.male, experience = TrainingExperience.threeToTenYears,
            bounceBack = BounceBackHabit.nextDay, weeklyVolume = WeeklyVolume.fiveOrSix,
            vo2Max = 52.0, observedMaxHeartRate = 188.0, bodyMassKilograms = 75.0,
            healthDerivedFields = setOf("vo2Max", "observedMaxHeartRate", "bodyMass")
        ), fromHealth = true)
        val historical = (1..16).map { index ->
            val end = now.daysAgo(index + if (scene == "ready") 20 else 0).hoursAfter(-2.0)
            val strength = index % 3 == 0
            WorkoutRecord(
                "fixture-$index", if (strength) 50 else 37, end.hoursAfter(-1.0), end, 60.0,
                if (strength) 300.0 else 600.0, if (strength) 110.0 else 145.0, 182.0,
                if (strength) 0.25 else 0.98, source = "Local fixture",
                reportedEffort = if (strength) 7.0 else null
            )
        }
        val end = when (scene) {
            "ready" -> now.hoursAfter(-18.0)
            "stale" -> now.daysAgo(10)
            else -> now.hoursAfter(-1.0)
        }
        val effort = scene == "effort"
        val minutes = if (scene == "ready") 30.0 else 60.0
        val latest = WorkoutRecord(
            "fixture-latest", if (effort) 50 else 37, end.hoursAfter(-minutes / 60), end, minutes,
            if (effort) 280.0 else 580.0,
            if (scene == "ready") 130.0 else if (effort) 108.0 else 150.0, 185.0,
            if (effort) 0.20 else 0.98, source = "Local fixture"
        )
        val days = (0..30).map { offset ->
            DailyContext(
                now.atZone(zone).toLocalDate().minusDays(offset.toLong()).atStartOfDay(zone).toInstant(),
                if (offset % 4 == 0) 6.5 else 8.1, 52.0 + (offset % 3), 58.0 + (offset % 5), 14.0
            )
        }
        graph.health.seedForDebug(if (scene == "stale") listOf(latest) else historical + latest, days)
    }
}
