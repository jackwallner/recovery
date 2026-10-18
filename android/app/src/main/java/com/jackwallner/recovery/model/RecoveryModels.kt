package com.jackwallner.recovery.model

import java.time.Duration
import java.time.Instant
import kotlin.math.*

const val recoveryModelVersion = 17
fun Double.roundAway(): Int = (sign(this) * floor(abs(this) + 0.5)).toInt()
fun Double.finiteOr(fallback: Double) = if (isFinite()) this else fallback
fun Double?.finite() = this?.takeIf { it.isFinite() }
fun Instant.hoursAfter(hours: Double): Instant = plusMillis((hours * 3_600_000).toLong())
fun Instant.hoursSince(other: Instant): Double = Duration.between(other,this).toMillis() / 3_600_000.0
fun Instant.daysAgo(days: Int): Instant = minusSeconds(days * 86400L)

enum class RecoveryTier(val label: String) { standard("Standard"), personalized("Recharge+") }
data class RecoveryPersonalization(val tier: RecoveryTier, val factor: Double) {
    companion object {
        val standard = RecoveryPersonalization(RecoveryTier.standard,1.0)
        fun personalized(factor: Double) = RecoveryPersonalization(RecoveryTier.personalized,PersonalRecoveryModel.clamp(factor))
    }
}
enum class WorkoutProfile(val label: String,val windowMultiplier: Double,val assumedEffort: Double,val standardTypicalLoad: Double) {
    endurance("Endurance",1.0,5.0,70.0), strength("Strength",1.15,5.0,86.0), mixed("Mixed",1.30,6.0,94.0), easy("Easy",0.0,2.0,16.0);
    val costMultiplier get() = if(this==easy)0.30 else windowMultiplier
    val wantsEffortInput get() = this==strength || this==mixed
}
enum class SessionIntensity(val label: String,val assumedEffort: Double) {
    light("Light",3.0),moderate("Moderate",6.0),hard("Hard",8.5);
    fun promoting(profile: WorkoutProfile): WorkoutProfile = when {
        this==light && profile==WorkoutProfile.endurance -> WorkoutProfile.easy
        this!=light && profile==WorkoutProfile.easy -> WorkoutProfile.endurance
        else -> profile
    }
}
data class ManualRecoveryWindows(var light: Double?=null,var moderate: Double?=null,var hard: Double?=null) {
    init { light=safe(light);moderate=safe(moderate);hard=safe(hard) }
    fun hours(intensity: SessionIntensity) = when(intensity){SessionIntensity.light->light;SessionIntensity.moderate->moderate;SessionIntensity.hard->hard}
    fun set(hours: Double?,intensity: SessionIntensity) { when(intensity){SessionIntensity.light->light=safe(hours);SessionIntensity.moderate->moderate=safe(hours);SessionIntensity.hard->hard=safe(hours)} }
    val isEmpty get() = light==null && moderate==null && hard==null
    companion object { fun safe(value: Double?) = value.finite()?.coerceIn(6.0,96.0) }
}
enum class LoadSource(val label: String) { heartRate("heart rate"),reportedEffort("your effort rating"),energy("duration and energy"),duration("duration") }
enum class LoadCategory(val label: String,val shortLabel: String,val intensity: SessionIntensity) {
    easy("Light for you","Light",SessionIntensity.light),typical("Moderate for you","Moderate",SessionIntensity.moderate),hard("Hard for you","Hard",SessionIntensity.hard),unusuallyHard("Very hard for you","Very hard",SessionIntensity.hard);
    fun label(tier: RecoveryTier) = if(tier==RecoveryTier.personalized)label else shortLabel+" session"
}
data class SessionLoad(var value: Double,val source: LoadSource,var heartRateCoverage: Double=0.0) {
    init { value=value.finiteOr(0.0).coerceAtLeast(0.0);heartRateCoverage=heartRateCoverage.finiteOr(0.0).coerceIn(0.0,1.0) }
}
data class HeartRateDistribution(var lowestBPM: Double,var seconds: List<Double>) {
    init {lowestBPM=lowestBPM.finiteOr(0.0);seconds=seconds.map{it.finiteOr(0.0).coerceAtLeast(0.0)}}
    val totalSeconds get()=seconds.sum()
    val buckets get()=seconds.mapIndexedNotNull {index,value->if(value>0)(lowestBPM+(index+0.5)*2) to value else null}
    companion object {
        fun fromSamples(bpm: List<Double>,secondsEach: Double): HeartRateDistribution? {
            val usable=bpm.filter{it.isFinite() && it in 30.0..240.0}
            if(usable.isEmpty() || !secondsEach.isFinite() || secondsEach<=0)return null
            val low=floor(usable.min()/2)*2
            val buckets=MutableList(((usable.max()-low)/2).toInt()+1){0.0}
            usable.forEach{val index=((it-low)/2).toInt().coerceAtMost(buckets.lastIndex);buckets[index]+=secondsEach}
            return HeartRateDistribution(low,buckets)
        }
    }
}
data class SessionInput(
    val id: String,val profile: WorkoutProfile,val startDate: Instant,val endDate: Instant,
    var durationMinutes: Double=Duration.between(startDate,endDate).toMillis()/60000.0,
    var averageHeartRate: Double?=null,var restingHeartRate: Double?=null,var maxHeartRate: Double?=null,
    var heartRateCoverage: Double=0.0,val heartRateDistribution: HeartRateDistribution?=null,
    var activeEnergyKilocalories: Double?=null,var reportedEffort: Double?=null,
    val intensityOverride: SessionIntensity?=null,var bodyMassKilograms: Double?=null,val activityLabel: String="workout"
) {
    init {
        durationMinutes=durationMinutes.finiteOr(0.0).coerceAtLeast(0.0)
        averageHeartRate=averageHeartRate.finite();restingHeartRate=restingHeartRate.finite();maxHeartRate=maxHeartRate.finite()
        heartRateCoverage=heartRateCoverage.finiteOr(0.0).coerceIn(0.0,1.0)
        activeEnergyKilocalories=activeEnergyKilocalories.finite();reportedEffort=reportedEffort.finite()?.coerceIn(1.0,10.0)
        bodyMassKilograms=bodyMassKilograms.finite()?.takeIf{it in 30.0..250.0}
    }
}
data class Night(val date: Instant,val sleepHours: Double?=null,val heartRateVariability: Double?=null,val restingHeartRate: Double?=null,val respiratoryRate: Double?=null) {
    val hasSignal get()=sleepHours!=null || heartRateVariability!=null || restingHeartRate!=null || respiratoryRate!=null
}
data class RecoveryContext(
    val sleepHours: Double?=null,val heartRateVariability: Double?=null,val heartRateVariabilityBaseline: Double?=null,
    val restingHeartRate: Double?=null,val restingHeartRateBaseline: Double?=null,
    val respiratoryRate: Double?=null,val respiratoryRateBaseline: Double?=null,var followingNights: List<Night> = emptyList()
) {
    init {followingNights=followingNights.filter{it.hasSignal}.sortedBy{it.date}}
    val nightBefore get()=Night(Instant.MIN,sleepHours,heartRateVariability,restingHeartRate,respiratoryRate)
    val isEmpty get()=!nightBefore.hasSignal && followingNights.isEmpty()
}
enum class RecoveryPhase(val label: String) {noRecentWorkout("No recent workout"),ready("Ready"),readySoon("Ready soon"),recovering("Recovering")}
enum class RecoveryConfidence(val label: String,val shortLabel: String) {buildingBaseline("Building baseline","Building"),low("Low confidence","Low"),medium("Medium confidence","Medium"),high("High confidence","High")}
data class RecoveryEstimate(
    val sessionID: String,val profile: WorkoutProfile,val activityLabel: String,val calculatedAt: Instant,val sessionEnd: Instant,val readyAt: Instant,
    var hours: Double,var windowLowHours: Double,var windowHighHours: Double,val load: SessionLoad,var relativeLoad: Double,
    val category: LoadCategory,val confidence: RecoveryConfidence,val reasons: List<String>,val modelVersion: Int=recoveryModelVersion,
    val tier: RecoveryTier=RecoveryTier.standard,var personalFactor: Double=1.0,var standardHours: Double=hours/personalFactor,
    var carriedHours: Double=0.0,var recoveryCostHours: Double=hours
) {
    init {
        hours=hours.finiteOr(0.0).coerceAtLeast(0.0);windowLowHours=windowLowHours.finiteOr(0.0).coerceAtLeast(0.0);windowHighHours=windowHighHours.finiteOr(0.0).coerceAtLeast(0.0)
        relativeLoad=relativeLoad.finiteOr(0.0).coerceAtLeast(0.0);personalFactor=personalFactor.takeIf{it.isFinite()&&it>0}?:1.0
        standardHours=standardHours.finiteOr(hours/personalFactor).coerceAtLeast(0.0);carriedHours=carriedHours.finiteOr(0.0).coerceAtLeast(0.0)
        recoveryCostHours=recoveryCostHours.finiteOr(hours).coerceIn(0.0,96.0)
    }
    val producesCountdown get()=hours>0
    val totalHours get()=if(producesCountdown)min(hours+max(carriedHours,0.0),96.0) else 0.0
    val isStacked get()=producesCountdown&&carriedHours>0.05
    fun remainingSeconds(now: Instant)=Duration.between(now,readyAt).toMillis().coerceAtLeast(0)/1000.0
    fun phase(now: Instant)=when { !producesCountdown || readyAt<=now -> RecoveryPhase.ready;remainingSeconds(now)<=7200 -> RecoveryPhase.readySoon;else->RecoveryPhase.recovering }
}
enum class ReadinessFeedback(val label: String,val calibrationNudge: Double) {feltReady("Felt ready",0.95),okayNotFresh("Okay but not fresh",1.0),notReady("Not ready",1.05)}
object RecoveryCalibration {
    const val minimum=0.80;const val maximum=1.25;const val neutral=1.0
    fun apply(feedback: ReadinessFeedback,factor: Double)=(factor.finiteOr(neutral)*feedback.calibrationNudge).coerceIn(minimum,maximum)
}
data class PersonalizedPreview(val label: String,val standardHours: Double,val personalizedHours: Double,val isExample: Boolean) {
    val isVisiblyDifferent get()=abs(personalizedHours-standardHours)>=0.5
    companion object {fun reference(factor: Double)=PersonalizedPreview("A hard 60-minute session",RecoveryCalculator.referenceHardSessionHours,RecoveryCalculator.referenceHardSessionHours*factor,true)}
}
