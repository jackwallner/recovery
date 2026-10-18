package com.jackwallner.recovery.data

import java.time.Instant

import org.json.JSONArray
import org.json.JSONObject

import com.jackwallner.recovery.model.*

fun JSONObject.number(key: String): Double?=if(isNull(key))null else optDouble(key).takeIf{it.isFinite()}
fun JSONObject.optionalText(key: String): String?=if(isNull(key))null else optString(key).takeIf{it.isNotEmpty()}
fun JSONObject.instant(key: String): Instant=Instant.parse(getString(key))
fun JSONArray.objects()=(0 until length()).map{getJSONObject(it)}
fun JSONArray.strings()=(0 until length()).map{getString(it)}
object CacheCodec {
    fun profile(p: AthleteProfile)=JSONObject().put("age",p.age).put("sex",p.sex.ordinal).put("experience",p.experience?.ordinal).put("bounceBack",p.bounceBack?.ordinal).put("weeklyVolume",p.weeklyVolume?.ordinal).put("primaryProfile",p.primaryProfile?.name).put("vo2Max",p.vo2Max).put("observedMaxHeartRate",p.observedMaxHeartRate).put("bodyMassKilograms",p.bodyMassKilograms).put("healthDerivedFields",JSONArray(p.healthDerivedFields.toList()))
    fun profile(r: JSONObject)=AthleteProfile(
        r.number("age")?.toInt(),AthleteSex.entries.getOrElse(r.optInt("sex")){AthleteSex.unspecified},
        r.number("experience")?.toInt()?.let{TrainingExperience.entries.getOrNull(it)},r.number("bounceBack")?.toInt()?.let{BounceBackHabit.entries.getOrNull(it)},r.number("weeklyVolume")?.toInt()?.let{WeeklyVolume.entries.getOrNull(it)},r.optionalText("primaryProfile")?.let{runCatching{WorkoutProfile.valueOf(it)}.getOrNull()},
        r.number("vo2Max"),r.number("observedMaxHeartRate"),r.number("bodyMassKilograms"),r.optJSONArray("healthDerivedFields")?.strings()?.toSet()?:emptySet())
    fun workout(w: WorkoutRecord)=JSONObject().put("id",w.id).put("activityCode",w.activityCode).put("start",w.start.toString()).put("end",w.end.toString()).put("minutes",w.minutes).put("energy",w.energy).put("averageHR",w.averageHR).put("peakHR",w.peakHR).put("coverage",w.coverage).put("source",w.source).put("reportedEffort",w.reportedEffort).put("intensityOverride",w.intensityOverride?.name).put("distribution",w.distribution?.let{JSONObject().put("lowest",it.lowestBPM).put("seconds",JSONArray(it.seconds))})
    fun workout(r: JSONObject)=WorkoutRecord(r.getString("id"),r.getInt("activityCode"),r.instant("start"),r.instant("end"),r.getDouble("minutes"),r.number("energy"),r.number("averageHR"),r.number("peakHR"),r.optDouble("coverage",0.0),r.optJSONObject("distribution")?.let{d->HeartRateDistribution(d.getDouble("lowest"),d.getJSONArray("seconds").let{a->(0 until a.length()).map{a.getDouble(it)}})},r.optString("source"),r.number("reportedEffort"),r.optionalText("intensityOverride")?.let(SessionIntensity::valueOf))
    fun day(d: DailyContext)=JSONObject().put("date",d.date.toString()).put("sleep",d.sleep).put("resting",d.resting).put("hrv",d.hrv).put("respiratory",d.respiratory).put("recovery",d.recovery)
    fun day(r: JSONObject)=DailyContext(r.instant("date"),r.number("sleep"),r.number("resting"),r.number("hrv"),r.number("respiratory"),r.number("recovery"))
    fun estimate(e: RecoveryEstimate)=JSONObject().put("sessionID",e.sessionID).put("profile",e.profile.name).put("activityLabel",e.activityLabel).put("calculatedAt",e.calculatedAt.toString()).put("sessionEnd",e.sessionEnd.toString()).put("readyAt",e.readyAt.toString()).put("hours",e.hours).put("low",e.windowLowHours).put("high",e.windowHighHours).put("load",e.load.value).put("source",e.load.source.name).put("coverage",e.load.heartRateCoverage).put("relativeLoad",e.relativeLoad).put("category",e.category.name).put("confidence",e.confidence.name).put("reasons",JSONArray(e.reasons)).put("modelVersion",e.modelVersion).put("tier",e.tier.name).put("personalFactor",e.personalFactor).put("standardHours",e.standardHours).put("carriedHours",e.carriedHours).put("recoveryCostHours",e.recoveryCostHours)
    fun estimate(r: JSONObject)=RecoveryEstimate(r.getString("sessionID"),WorkoutProfile.valueOf(r.getString("profile")),r.getString("activityLabel"),r.instant("calculatedAt"),r.instant("sessionEnd"),r.instant("readyAt"),r.getDouble("hours"),r.getDouble("low"),r.getDouble("high"),SessionLoad(r.getDouble("load"),LoadSource.valueOf(r.getString("source")),r.optDouble("coverage",0.0)),r.getDouble("relativeLoad"),LoadCategory.valueOf(r.getString("category")),RecoveryConfidence.valueOf(r.getString("confidence")),r.getJSONArray("reasons").strings(),r.optInt("modelVersion",17),r.optionalText("tier")?.let(RecoveryTier::valueOf)?:RecoveryTier.standard,r.optDouble("personalFactor",1.0),r.number("standardHours")?:r.getDouble("hours")/r.optDouble("personalFactor",1.0),r.optDouble("carriedHours",0.0),r.number("recoveryCostHours")?:r.getDouble("hours"))
}
