package com.jackwallner.recovery

import java.time.Instant
import java.time.ZoneId
import java.util.TimeZone

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

import com.jackwallner.recovery.model.*

object SwiftFixtures {
    val root: JSONObject by lazy {
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        JSONObject(checkNotNull(javaClass.getResourceAsStream("/swift-parity.json")).bufferedReader().use{it.readText()})
    }
    fun cases(key: String)=root.getJSONArray(key).let{array->(0 until array.length()).map{val row=array.getJSONObject(it);arrayOf(row.optString("name",it.toString()),row)}}
}
fun JSONObject.number(key: String): Double?=if(isNull(key))null else getDouble(key)
fun JSONObject.text(key: String): String?=if(isNull(key))null else getString(key)
fun JSONArray.doubles()=(0 until length()).map{getDouble(it)}
fun JSONObject.instant(key: String)=Instant.ofEpochMilli((getDouble(key)*1000).toLong())
fun profile(r: JSONObject)=AthleteProfile(
    age=if(r.has("age"))r.getInt("age")else null,
    sex=AthleteSex.entries.getOrElse(r.optInt("sex")){AthleteSex.unspecified},
    experience=if(r.has("experience"))TrainingExperience.entries[r.getInt("experience")]else null,
    bounceBack=if(r.has("bounceBack"))BounceBackHabit.entries[r.getInt("bounceBack")]else null,
    weeklyVolume=if(r.has("weeklyVolume"))WeeklyVolume.entries[r.getInt("weeklyVolume")]else null,
    vo2Max=r.number("vo2Max"),observedMaxHeartRate=r.number("observedMaxHeartRate"),bodyMassKilograms=r.number("bodyMassKilograms"))

@RunWith(Parameterized::class)
class SwiftCalculationParityTest(private val name: String,private val row: JSONObject) {
    @Test fun matchesOriginalSwiftCalculation() {
        val s=row.getJSONObject("session")
        val distribution=s.optJSONObject("distribution")?.let{HeartRateDistribution(it.getDouble("lowest"),it.getJSONArray("seconds").doubles())}
        val session=SessionInput(s.getString("id"),WorkoutProfile.valueOf(s.getString("profile")),s.instant("start"),s.instant("end"),s.getDouble("minutes"),s.number("average"),s.number("resting"),s.number("maximum"),s.getDouble("coverage"),distribution,s.number("energy"),s.number("effort"),s.text("override")?.let(SessionIntensity::valueOf),s.number("mass"),s.getString("label"))
        val c=row.getJSONObject("context");val nights=c.getJSONArray("nights")
        val context=RecoveryContext(c.number("sleep"),c.number("hrv"),c.number("hrvBase"),c.number("resting"),c.number("restingBase"),c.number("respiratory"),c.number("respiratoryBase"),(0 until nights.length()).map{val n=nights.getJSONObject(it);Night(n.instant("date"),n.number("sleep"),n.number("hrv"),n.number("resting"),n.number("respiratory"))})
        val baseline=RecoveryBaseline(row.getJSONArray("loads").doubles(),session.profile,row.getJSONArray("daily").doubles(),row.getDouble("fitness"))
        val estimate=RecoveryCalculator.estimate(session,baseline,context,row.getDouble("calibration"),RecoveryPersonalization(RecoveryTier.valueOf(row.getString("tier")),row.getDouble("factor")),carriedHours=row.getDouble("carried"),manualHours=row.number("manual"),now=SwiftFixtures.root.instant("now"))
        val expected=row.getJSONObject("expected")
        mapOf("hours" to estimate.hours,"carried" to estimate.carriedHours,"cost" to estimate.recoveryCostHours,"total" to estimate.totalHours,"low" to estimate.windowLowHours,"high" to estimate.windowHighHours,"load" to estimate.load.value,"relative" to estimate.relativeLoad,"factor" to estimate.personalFactor,"standard" to estimate.standardHours).forEach{(key,actual)->assertEquals(name+" "+key,expected.getDouble(key),actual,1e-7)}
        assertEquals(expected.getDouble("ready"),estimate.readyAt.toEpochMilli()/1000.0,0.003)
        assertEquals(expected.getString("source"),estimate.load.source.name)
        assertEquals(expected.getString("confidence"),estimate.confidence.name)
        assertEquals(expected.getString("category"),estimate.category.name)
        val reasons=expected.getJSONArray("reasons").let{array->(0 until array.length()).map{array.getString(it)}}
        assertEquals(name,reasons,estimate.reasons)
        assertTrue(estimate.hours.isFinite()&&estimate.hours in 0.0..96.0)
        if(estimate.producesCountdown)assertTrue(estimate.hours>=6)
        for(reason in estimate.reasons)for(term in listOf("recovered","safe to train","injury","your body","cure","diagnos"))assertFalse(reason,reason.lowercase().contains(term))
    }
    companion object {@JvmStatic @Parameterized.Parameters(name="{index}: {0}")fun cases()=SwiftFixtures.cases("calculations")}
}

@RunWith(Parameterized::class)
class SwiftAthleteParityTest(private val name: String,private val row: JSONObject) {
    @Test fun matchesOriginalAthleteProfile() {
        val p=profile(row.getJSONObject("input"))
        assertEquals(name,row.getDouble("fitness"),p.fitnessScale,1e-9)
        for((key,actual) in listOf("prior" to p.prior,"predicted" to p.predictedMaxHeartRate))if(row.isNull(key))assertNull(actual)else assertEquals(row.getDouble(key),actual!!,1e-9)
        val gaps=row.getJSONArray("gaps").let{a->(0 until a.length()).map{a.getString(it)}}
        assertEquals(gaps,p.gaps)
    }
    companion object {@JvmStatic @Parameterized.Parameters(name="{index}: {0}")fun cases()=SwiftFixtures.cases("profiles")}
}

@RunWith(Parameterized::class)
class SwiftPersonalAnalysisParityTest(private val name: String,private val row: JSONObject) {
    @Test fun matchesOriginalThirtyDayAnalysis() {
        val s=row.getJSONArray("sessions");val d=row.getJSONArray("days")
        val sessions=(0 until s.length()).map{val r=s.getJSONObject(it);HistorySession(r.getString("id"),WorkoutProfile.valueOf(r.getString("profile")),r.instant("end"),r.getDouble("load"),r.getDouble("standard"),r.instant("start"),r.number("intensity"))}
        val days=(0 until d.length()).map{val r=d.getJSONObject(it);DayPoint(r.instant("date"),r.number("resting"),r.number("hrv"),r.number("recovery"))}
        val actual=PersonalRecoveryModel.analyse(profile(row.getJSONObject("profile")),sessions,days,SwiftFixtures.root.instant("now"),ZoneId.of("UTC"))
        val e=row.getJSONObject("expected")
        mapOf("factor" to actual.factor,"prior" to actual.prior,"rebound" to actual.reboundFactor,"tolerance" to actual.toleranceFactor,"kinetics" to actual.kineticsFactor,"medianRecovery" to actual.medianHeartRateRecovery,"weekly" to actual.weeklyLoad,"frequency" to actual.sessionsPerWeek,"weight" to actual.evidenceWeight).forEach{(key,value)->if(e.isNull(key))assertNull(name+key,value)else assertEquals(name+key,e.getDouble(key),value!!,1e-8)}
        mapOf("reboundSamples" to actual.reboundSamples,"toleranceSamples" to actual.toleranceSamples,"kineticsSamples" to actual.kineticsSamples,"count" to actual.qualifyingSessions).forEach{(key,value)->assertEquals(name+key,e.getInt(key),value)}
        assertEquals(e.getJSONArray("summary").let{a->(0 until a.length()).map{a.getString(it)}},PersonalRecoveryModel.summary(actual))
    }
    companion object {@JvmStatic @Parameterized.Parameters(name="{index}: {0}")fun cases()=SwiftFixtures.cases("analyses")}
}

@RunWith(Parameterized::class)
class SwiftObservedPatternParityTest(private val name: String,private val row: JSONObject) {
    @Test fun matchesOriginalComparableSessionPattern() {
        val s=row.getJSONArray("sessions")
        val sessions=(0 until s.length()).map{val r=s.getJSONObject(it);ObservedSession(r.getString("id"),WorkoutProfile.valueOf(r.getString("profile")),r.instant("start"),r.instant("end"),r.getDouble("load"))}
        val actual=ObservedRecoveryPattern.analyse(sessions,SwiftFixtures.root.instant("now"))
        assertEquals(name,row.getDouble("light"),actual.lightCeiling,1e-9);assertEquals(row.getDouble("moderate"),actual.moderateCeiling,1e-9);assertEquals(row.getInt("count"),actual.sessionCount)
        val gaps=row.getJSONArray("gaps")
        for(i in 0 until gaps.length()) {
            val g=gaps.getJSONObject(i);val band=SessionIntensity.valueOf(g.getString("band"))
            val hours=actual.usualGapHours(band)
            if(g.isNull("hours"))assertNull(hours)else assertEquals(g.getDouble("hours"),hours!!,1e-9)
            if(g.isNull("samples"))assertNull(actual.evidence(band))else assertEquals(g.getInt("samples"),actual.evidence(band)!!.sampleCount)
            assertEquals(g.getBoolean("specific"),actual.isBandSpecific(band))
        }
    }
    companion object {@JvmStatic @Parameterized.Parameters(name="{index}: {0}")fun cases()=SwiftFixtures.cases("patterns")}
}
