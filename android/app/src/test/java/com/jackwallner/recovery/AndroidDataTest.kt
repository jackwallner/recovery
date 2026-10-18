package com.jackwallner.recovery

import java.time.Instant
import java.time.ZoneId

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

import com.jackwallner.recovery.data.AndroidWorkoutTypes
import com.jackwallner.recovery.data.CacheCodec
import com.jackwallner.recovery.data.Settings
import com.jackwallner.recovery.model.*

private class MemoryValues : Values {
    private val data = mutableMapOf<String, String>()
    override fun string(key: String) = data[key]
    override fun put(key: String, value: String) { data[key] = value }
    override fun entries(): Map<String, String> = data.toMap()
}
class AndroidDataTest {
    private val now = Instant.parse("2026-06-01T12:00:00Z")
    private fun workout() = WorkoutRecord("roundtrip", 37, now.hoursAfter(-2.0), now.hoursAfter(-1.0), 60.0, 600.0, 150.0, 185.0, 0.98, HeartRateDistribution.fromSamples(listOf(145.0, 155.0), 60.0), "device", 8.0, SessionIntensity.hard)
    @Test fun workoutCachePreservesEffortCorrectionAndDistribution() { val w = workout(); assertEquals(w, CacheCodec.workout(JSONObject(CacheCodec.workout(w).toString()))) }
    @Test fun absentSignalsStayAbsentInWorkoutCache() { val w = workout().copy(averageHR=null, peakHR=null, energy=null, distribution=null, reportedEffort=null, intensityOverride=null); assertEquals(w, CacheCodec.workout(JSONObject(CacheCodec.workout(w).toString()))) }
    @Test fun estimateCachePreservesFrozenHistoryAndResiduals() { val e = RecoveryEngine.score(listOf(workout()), emptyList(), ModelOptions(isPro=true), now=now).estimates.single(); assertEquals(e, CacheCodec.estimate(JSONObject(CacheCodec.estimate(e).toString()))) }
    @Test fun dailyCachePreservesAllNightSignals() { val d = DailyContext(now, 8.0, 50.0, 60.0, 13.0, null); assertEquals(d, CacheCodec.day(JSONObject(CacheCodec.day(d).toString()))) }
    @Test fun profileCachePreservesProvenanceAndAllFields() { val p=AthleteProfile(35,AthleteSex.male,TrainingExperience.threeToTenYears,BounceBackHabit.nextDay,WeeklyVolume.fiveOrSix,WorkoutProfile.endurance,52.0,195.0,75.0,setOf("vo2Max","weeklyVolume")); assertEquals(p,CacheCodec.profile(JSONObject(CacheCodec.profile(p).toString()))) }
    @Test fun emptyCacheUsesUnknownProfile() { assertEquals(AthleteProfile(),CacheCodec.profile(JSONObject())) }
    @Test fun androidExerciseMappingsResolveToKnownSwiftTypes() { assertTrue(AndroidWorkoutTypes.names.size>=55); AndroidWorkoutTypes.names.forEach { (type,name)->assertNotEquals(name,9999,AndroidWorkoutTypes.code(type)); assertTrue(WorkoutClassifier.activities.any { it.name==name }) } }
    @Test fun allSwiftClassificationsArePresent() { assertEquals(85,WorkoutClassifier.activities.size); assertEquals(85,WorkoutClassifier.activities.map { it.code }.distinct().size); assertEquals("australianFootball",WorkoutClassifier.activities.single { it.code==3 }.name) }
    @Test fun unknownExerciseUsesGeneralWorkout() { assertEquals(9999,AndroidWorkoutTypes.code(-1)); assertEquals("workout",WorkoutClassifier.label(-1)) }
    @Test fun singleHeartSampleCannotClaimCoverage() { val result=HealthMath.heartSummary(listOf(HeartSample(now,150.0,"watch")),now.hoursAfter(-1.0),now,60.0,"watch"); assertEquals(0.0,result.coverage,0.0) }
    @Test fun duplicateHeartSamplesCannotInflateCoverage() { val sample=HeartSample(now,150.0,"watch"); assertEquals(0.0,HealthMath.heartSummary(List(50) { sample },now.hoursAfter(-1.0),now,60.0,"watch").coverage,0.0) }
    @Test fun mixedHeartSourcesAreNotDoubleCounted() { val a=(0..60).map { HeartSample(now.minusSeconds(it*60L),150.0,"watch") }; val b=a.map { it.copy(bpm=220.0,source="phone") }; assertEquals(150.0,HealthMath.heartSummary(a+b,now.hoursAfter(-1.0),now,60.0,"watch").average!!,0.0) }
    @Test fun unusablePreferredSourceFallsBackToMeasuredSource() { val a=(0..60).map { HeartSample(now.minusSeconds(it*60L),150.0,"watch") }; val result=HealthMath.heartSummary(a+HeartSample(now,220.0,"phone"),now.hoursAfter(-1.0),now,60.0,"phone"); assertEquals(150.0,result.average!!,0.0); assertEquals(1.0,result.coverage,0.0) }
    @Test fun invalidAndOutOfWindowHeartSamplesAreIgnored() { val samples=listOf(HeartSample(now,Double.NaN,"a"),HeartSample(now,300.0,"a"),HeartSample(now.hoursAfter(1.0),150.0,"a")); assertEquals(HeartSummary(),HealthMath.heartSummary(samples,now.hoursAfter(-1.0),now,60.0,"a")) }
    @Test fun overlappingSleepSourcesAreUnioned() { val hours=HealthMath.sleepHours(listOf(TimeInterval(now.hoursAfter(-8.0),now),TimeInterval(now.hoursAfter(-7.0),now)),ZoneId.of("UTC")); assertEquals(8.0,hours.values.single(),0.0) }
    @Test fun touchingSleepIntervalsMergeWithoutInventingTime() { val merged=HealthMath.union(listOf(TimeInterval(now.hoursAfter(-8.0),now.hoursAfter(-4.0)),TimeInterval(now.hoursAfter(-4.0),now))); assertEquals(listOf(TimeInterval(now.hoursAfter(-8.0),now)),merged) }
    @Test fun settingsPersistProfileAndPinnedWindows() { val values=MemoryValues(); val a=Settings(values); a.updateProfile(AthleteProfile(age=35)); a.setManualWindow(SessionIntensity.moderate,30.0); val b=Settings(values); assertEquals(35,b.profile.age); assertEquals(30.0,b.manualWindows.moderate!!,0.0) }
    @Test fun setupPersistsAndSetsFeedbackEligibilityOnlyOnce() { val values=MemoryValues(); val settings=Settings(values); settings.completeSetup(now); settings.completeSetup(now.hoursAfter(2.0)); assertEquals(now,Settings(values).feedbackEligibleFrom); assertTrue(Settings(values).hasCompletedSetup) }
    @Test fun feedbackPersistsCalibrationAndSessionSuppression() { val values=MemoryValues(); val a=Settings(values); a.applyFeedback(ReadinessFeedback.entries.first(),"session"); val b=Settings(values); assertEquals(a.calibration,b.calibration,0.0); assertTrue("session" in b.answeredFeedback) }
    @Test fun revocationRemovesOnlyHealthDerivedProfileAnswers() { val a=Settings(MemoryValues()); a.updateProfile(AthleteProfile(age=35,weeklyVolume=WeeklyVolume.fiveOrSix,vo2Max=52.0,healthDerivedFields=setOf("weeklyVolume","vo2Max"))); a.clearHealthDerivedProfile(); assertEquals(35,a.profile.age); assertNull(a.profile.weeklyVolume); assertNull(a.profile.vo2Max) }
    @Test fun userSpecifiedTrainingVolumeSurvivesRevocation() { val a=Settings(MemoryValues()); a.updateProfile(AthleteProfile(weeklyVolume=WeeklyVolume.fiveOrSix)); a.clearHealthDerivedProfile(); assertEquals(WeeklyVolume.fiveOrSix,a.profile.weeklyVolume) }
    @Test fun passiveTrialOfferHonorsFourteenDayCooldown() { val a=Settings(MemoryValues()); a.completeSetup(now); assertFalse(a.passiveTrialOfferAllowed(now.daysAgo(-13))); assertTrue(a.passiveTrialOfferAllowed(now.daysAgo(-14))) }
    @Test fun readyMomentsAreDeduplicatedAcrossRestarts() { val values=MemoryValues(); val a=ReviewTracker(values); a.recordReadyMoment("same"); val b=ReviewTracker(values); b.recordReadyMoment("same"); assertEquals(1,b.readyMomentCount) }
    @Test fun reviewNeedsTwoReadyMomentsAndMatureUse() { val values=MemoryValues(); var time=now.toEpochMilli(); val tracker=ReviewTracker(values) { time }; repeat(3) { tracker.recordAppLaunch() }; tracker.recordReadyMoment("first"); time+=3*86_400_000L; assertFalse(tracker.shouldRequest(true)); tracker.recordReadyMoment("second"); assertTrue(tracker.shouldRequest(true)); tracker.markShown(); assertFalse(tracker.shouldRequest(true)) }
    @Test fun automationNeverAsksForRating() { val tracker=ReviewTracker(MemoryValues()); tracker.isAutomationRun=true; tracker.readyMomentCount=10; assertFalse(tracker.shouldRequest(true)) }
    @Test fun diagnosticsNeverContainHealthOrFreeText() { val values=MemoryValues(); val d=ConversionDiagnostics(values); d.recordAppOpen(); d.recordPitchView("recharge_onboarding"); d.recordConversion("yearly",true,"default"); assertFalse(d.subscriberAttributes.keys.any { it.contains("health",true)||it.contains("workout",true)||it.contains("heart",true) }); assertTrue(d.subscriberAttributes.isNotEmpty()) }
    @Test fun trialDisclosureIncludesRenewalAndCancellation() { val text=ConversionCopy.disclosure("7-day free trial","$3.99 / month",true); assertTrue(text.contains("7-day")); assertTrue(text.contains("Auto-renews")); assertTrue(text.contains("Google Play > Payments & subscriptions")) }
    @Test fun trialPeriodHandlesDayWeekMonthAndYear() { assertEquals("7-day free trial",ConversionCopy.trialLabel("P7D")); assertEquals("1-week free trial",ConversionCopy.trialLabel("P1W")); assertNull(ConversionCopy.trialLabel("P0D")); assertNull(ConversionCopy.trialLabel("garbage")) }
}
