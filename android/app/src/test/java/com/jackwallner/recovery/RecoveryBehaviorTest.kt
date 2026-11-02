package com.jackwallner.recovery

import java.time.Instant
import java.time.ZoneId

import org.junit.Assert.*
import org.junit.Test

import com.jackwallner.recovery.model.*

class RecoveryBehaviorTest {
    private val now=Instant.parse("2026-06-01T12:00:00Z")
    private fun workout(id: String="run",end: Instant=now.hoursAfter(-1.0),coverage: Double=0.98,code: Int=37)=WorkoutRecord(id,code,end.hoursAfter(-1.0),end,60.0,680.0,165.0,185.0,coverage)
    private fun score(workouts: List<WorkoutRecord>,options: ModelOptions=ModelOptions(),previous: List<RecoveryEstimate> = emptyList(),unfreeze: Boolean=false)=RecoveryEngine.score(workouts,emptyList(),options,previous,unfreeze,now,ZoneId.of("UTC"))
    @Test fun duplicateImportsAreScoredOnlyOnce() {val result=score(listOf(workout("good"),workout("poor",coverage=0.4)));assertEquals(setOf("poor"),result.duplicateIDs);assertEquals(1,result.estimates.size)}
    @Test fun equalQualityDuplicatesKeepStableID() {assertEquals(setOf("z"),score(listOf(workout("z"),workout("a"))).duplicateIDs)}
    @Test fun adjacentSessionsAreNotDuplicates() {assertTrue(score(listOf(workout("first",now.hoursAfter(-2.0)),workout("second"))).duplicateIDs.isEmpty())}
    @Test fun correctionPromotesAWalkIntoARealCountdown() {assertEquals(0.0,score(listOf(workout(code=52))).estimates.single().hours,0.0);assertTrue(score(listOf(workout(code=52).copy(intensityOverride=SessionIntensity.hard))).estimates.single().hours>=6)}
    @Test fun lightCorrectionDoesNotStartOrExtendACountdown() {assertEquals(0.0,score(listOf(workout().copy(intensityOverride=SessionIntensity.light))).estimates.single().totalHours,0.0)}
    @Test fun freeTierIgnoresPaidCorrectionsToRecoveryWindows() {val input=listOf(workout());val base=score(input);val altered=score(input,ModelOptions(calibration=1.25,manualWindows=ManualRecoveryWindows(90.0,90.0,90.0)));assertEquals(base.estimates.single().hours,altered.estimates.single().hours,0.0)}
    @Test fun subscriberCanReplaceTheModelWithPinnedHours() {val result=score(listOf(workout()),ModelOptions(isPro=true,manualWindows=ManualRecoveryWindows(30.0,30.0,30.0)));assertEquals(30.0,result.estimates.single().hours,0.0);assertEquals(30.0,result.estimates.single().recoveryCostHours,0.0)}
    @Test fun standardAndPersonalizedChainsStaySeparate() {val workouts=listOf(workout("first",now.hoursAfter(-8.0)),workout("second")).map{it.copy(averageHR=130.0)};val options=ModelOptions(profile=AthleteProfile(age=60,bounceBack=BounceBackHabit.threeOrMoreDays));val free=score(workouts,options);val paid=score(workouts,options.copy(isPro=true));assertEquals(free.standard,paid.standard);assertNotEquals(free.estimates.first().totalHours,paid.estimates.first().totalHours)}
    @Test fun hardDoubleCostsMoreWithoutAddingBothInFull() {val single=score(listOf(workout())).estimates.single();val double=score(listOf(workout("first",now.hoursAfter(-3.0)),workout("second"))).estimates.first();assertTrue(double.totalHours>single.hours);assertTrue(double.totalHours<single.hours*2);assertTrue(double.carriedHours>0)}
    @Test fun historicalFinishedEstimateIsFrozen() {val workout=workout(end=now.daysAgo(5));val original=score(listOf(workout)).estimates.single().copy(hours=7.0,readyAt=now.daysAgo(4));val next=score(listOf(workout),previous=listOf(original));assertEquals(original,next.estimates.single())}
    @Test fun explicitModelCorrectionThawsHistory() {val workout=workout(end=now.daysAgo(5));val original=score(listOf(workout)).estimates.single().copy(hours=7.0,readyAt=now.daysAgo(4));assertNotEquals(7.0,score(listOf(workout),previous=listOf(original),unfreeze=true).estimates.single().hours)}
    @Test fun changedModelVersionThawsHistory() {val workout=workout(end=now.daysAgo(5));val original=score(listOf(workout)).estimates.single().copy(hours=7.0,modelVersion=16,readyAt=now.daysAgo(4));assertEquals(17,score(listOf(workout),previous=listOf(original)).estimates.single().modelVersion)}
    @Test fun freeTierNeverAsksReadinessFeedback() {assertNull(score(listOf(workout(end=now.daysAgo(2)))).awaitingFeedback)}
    @Test fun importedHistoryBeforeSetupNeverAsksReadinessFeedback() {assertNull(score(listOf(workout(end=now.daysAgo(2))),ModelOptions(isPro=true,feedbackEligibleFrom=now)).awaitingFeedback)}
    @Test fun fallbackEffortQuestionRemainsFree() {val result=score(listOf(workout(code=50,coverage=0.1)));assertNotNull(result.awaitingEffort)}
    @Test fun skippedEffortQuestionDoesNotRepeat() {assertNull(score(listOf(workout(code=50,coverage=0.1)),ModelOptions(declinedEffort=setOf("run"))).awaitingEffort)}
    @Test fun completedEffortQuestionDoesNotRepeat() {assertNull(score(listOf(workout(code=50,coverage=0.1).copy(reportedEffort=9.0))).awaitingEffort)}
    @Test fun stalePhaseDoesNotNarrateAnOldWindow() {val estimates=score(listOf(workout(end=now.daysAgo(10)))).estimates;assertEquals(RecoveryPhase.noRecentWorkout,RecoveryResolver.phase(estimates,now));assertNull(RecoveryResolver.explanation(estimates,now));assertNotNull(RecoveryResolver.current(estimates,now))}
    @Test fun observedPeakNeverLowersThePredictedCeiling() {val p=AthleteProfile(age=35,observedMaxHeartRate=130.0);assertEquals(p.predictedMaxHeartRate,p.effectiveMaxHeartRate);assertFalse(p.usesObservedMaxHeartRate)}
    @Test fun higherObservedPeakReplacesTheFormula() {assertEquals(205.0,AthleteProfile(age=35,observedMaxHeartRate=205.0).effectiveMaxHeartRate!!,0.0)}
    @Test fun invalidSensorInputsRemainFinite() {val s=SessionInput("bad",WorkoutProfile.endurance,now,now,Double.NaN,Double.NaN,Double.POSITIVE_INFINITY,Double.NaN,Double.NaN,activeEnergyKilocalories=Double.POSITIVE_INFINITY,reportedEffort=Double.NaN);val e=RecoveryCalculator.estimate(s,RecoveryBaseline.standard(s.profile),calibration=Double.NaN,carriedHours=Double.POSITIVE_INFINITY,now=now);assertEquals(0.0,e.hours,0.0);assertTrue(e.load.value.isFinite())}
    @Test fun manualWindowsAreBoundedAndNonfiniteMeansUnset() {val windows=ManualRecoveryWindows(1.0,150.0,Double.NaN);assertEquals(6.0,windows.light!!,0.0);assertEquals(96.0,windows.moderate!!,0.0);assertNull(windows.hard)}
    @Test fun activeRecoveryStillCarriesTrainingCost() {val e=score(listOf(workout(code=52))).estimates.single();assertTrue(e.recoveryCostHours>0);assertFalse(e.producesCountdown)}
    @Test fun dataFailureBecomesStaleAfterSixHours() {assertEquals(HealthDataState.current,HealthDataState.resolve(true,now.hoursAfter(-5.0),now));assertEquals(HealthDataState.stale,HealthDataState.resolve(true,now.hoursAfter(-7.0),now));assertEquals(HealthDataState.stale,HealthDataState.resolve(true,null,now))}
    @Test fun countdownRoundsUpAtMinuteBoundaries() {assertEquals("1m",CountdownFormat.remaining(1.0));assertEquals("2m",CountdownFormat.remaining(61.0));assertEquals("1h 1m",CountdownFormat.remaining(3601.0));assertEquals("2h",CountdownFormat.remaining(7500.0,true));assertEquals("Ready",CountdownFormat.remaining(0.0))}
    @Test fun timelineIncludesReadyAndFollowup() {val ready=now.hoursAfter(96.0);val dates=CountdownTimeline.entryDates(RecoverySnapshot(ready,now,96.0),now);assertTrue(dates.size<=108);assertEquals(now,dates.first());assertTrue(ready in dates);assertEquals(ready.plusSeconds(60),dates.last());assertEquals(dates.distinct().sorted(),dates)}
    @Test fun emptyAndStaleSnapshotsDoNotDisplayProgress() {assertEquals(0.0,RecoverySnapshot().progress(now),0.0);assertEquals(0.0,RecoverySnapshot(now.daysAgo(9),now.daysAgo(10),24.0).progress(now),0.0)}
    @Test fun sixRecentSessionsCanDeriveTrainingVolume() {val workouts=(1..6).map{workout(it.toString(),now.daysAgo(it))};assertNotNull(RecoveryEngine.derivedTrainingProfile(workouts,WorkoutProfile.mixed,now).first)}
    @Test fun walksCannotInflateDerivedTrainingVolume() {val workouts=(1..10).map{workout(it.toString(),now.daysAgo(it),code=52)};assertNull(RecoveryEngine.derivedTrainingProfile(workouts,WorkoutProfile.mixed,now).first)}
    @Test fun readyAlertIsDueForTheCountdownThatJustRanOut() {val estimates=score(listOf(workout("run",now.hoursAfter(-50.0)))).estimates;assertEquals("run",RecoveryResolver.alertDue(estimates,now)?.sessionID)}
    @Test fun readyAlertSurvivesAWalkLoggedDuringTheCountdown() {
        val estimates=score(listOf(workout("run",now.hoursAfter(-50.0)),workout("walk",now.hoursAfter(-20.0),code=52))).estimates
        assertEquals("walk",RecoveryResolver.current(estimates,now)?.sessionID)
        assertEquals("run",RecoveryResolver.alertDue(estimates,now)?.sessionID)
    }
    @Test fun readyAlertWaitsWhileALaterCountdownIsRunning() {assertNull(RecoveryResolver.alertDue(score(listOf(workout("first",now.hoursAfter(-50.0)),workout("second",now.hoursAfter(-1.0)))).estimates,now))}
    @Test fun readyAlertIsNotRaisedForACountdownThatEndedMoreThanADayAgo() {assertNull(RecoveryResolver.alertDue(score(listOf(workout("run",now.hoursAfter(-80.0)))).estimates,now))}
    @Test fun readyAlertIsNotRaisedBeforeTheCountdownRunsOut() {assertNull(RecoveryResolver.alertDue(score(listOf(workout("run",now.hoursAfter(-10.0)))).estimates,now))}
}
