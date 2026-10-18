package com.jackwallner.recovery.model

import java.time.Instant
import java.time.ZoneId
import kotlin.math.*

data class HistorySession(val id: String,val profile: WorkoutProfile,val endDate: Instant,val load: Double,val standardHours: Double,val startDate: Instant=endDate,val intensityFraction: Double?=null)
data class DayPoint(val date: Instant,val restingHeartRate: Double?=null,val heartRateVariability: Double?=null,val heartRateRecovery: Double?=null)
data class PersonalAnalysis(
    val factor: Double=1.0,val prior: Double?=null,val reboundFactor: Double?=null,val reboundSamples: Int=0,
    val toleranceFactor: Double?=null,val toleranceSamples: Int=0,val kineticsFactor: Double?=null,val kineticsSamples: Int=0,
    val medianHeartRateRecovery: Double?=null,val weeklyLoad: Double=0.0,val sessionsPerWeek: Double=0.0,val qualifyingSessions: Int=0,val evidenceWeight: Double=0.0
) {
    val isPersonalised get()=prior!=null||evidenceWeight>0
    val direction get()=when {factor<=0.97->"shorter";factor>=1.03->"longer";else->"similar"}
    val percentDifference get()=((factor-1)*100).roundAway()
}
object PersonalRecoveryModel {
    const val windowDays=30
    const val minimumFactor=0.72
    const val maximumFactor=1.32
    fun clamp(value: Double)=value.finiteOr(1.0).coerceIn(minimumFactor,maximumFactor)
    fun median(values: List<Double>): Double? {
        if(values.isEmpty())return null
        val sorted=values.sorted();val middle=sorted.size/2
        return if(sorted.size%2==0)(sorted[middle-1]+sorted[middle])/2 else sorted[middle]
    }
    fun analyse(profile: AthleteProfile,sessions: List<HistorySession>,days: List<DayPoint>,now: Instant=Instant.now(),zone: ZoneId=ZoneId.systemDefault()): PersonalAnalysis {
        val cutoff=now.daysAgo(30)
        val window=sessions.filter{it.endDate>=cutoff&&it.endDate<=now&&it.profile!=WorkoutProfile.easy}.sortedWith(compareBy({it.endDate},{it.startDate},{it.id}))
        val recent=days.filter{it.date>=cutoff&&it.date<=now}
        val weekly=window.sumOf{it.load}/(30.0/7);val frequency=window.size/(30.0/7)
        val rebound=reboundEvidence(window,recent,zone);val tolerance=toleranceEvidence(window);val kinetics=kineticsEvidence(recent)
        val weighted=listOfNotNull(rebound.first?.let{it to rebound.second.toDouble()},tolerance.first?.let{it to tolerance.second.toDouble()},kinetics.first?.let{it to kinetics.second.toDouble()})
        val prior=profile.prior;val total=weighted.sumOf{it.second}
        if(total<=0)return PersonalAnalysis(clamp(prior?:1.0),prior,reboundSamples=rebound.second,toleranceSamples=tolerance.second,kineticsSamples=kinetics.second,medianHeartRateRecovery=kinetics.third,weeklyLoad=weekly,sessionsPerWeek=frequency,qualifyingSessions=window.size)
        val evidence=exp(weighted.sumOf{ln(max(it.first,0.01))*it.second}/total)
        val weight=min(total/12,1.0)*0.70
        val blended=if(prior!=null)exp(ln(prior)*(1-weight)+ln(evidence)*weight)else evidence
        return PersonalAnalysis(clamp(blended),prior,rebound.first,rebound.second,tolerance.first,tolerance.second,kinetics.first,kinetics.second,kinetics.third,weekly,frequency,window.size,if(prior==null)1.0 else weight)
    }
    fun kineticsEvidence(days: List<DayPoint>): Triple<Double?,Int,Double?> {
        val values=days.mapNotNull{it.heartRateRecovery}.filter{it.isFinite()&&it>0}
        val middle=median(values)?:return Triple(null,values.size,null)
        if(values.size<3)return Triple(null,values.size,middle)
        return Triple((25/middle).pow(0.35).coerceIn(0.85,1.18),values.size,middle)
    }
    fun normalisationRatio(day1: Double,day2: Double)=if(day1>0.01)(day2/day1).coerceIn(0.0,1.0)else 0.0
    fun reboundEvidence(sessions: List<HistorySession>,days: List<DayPoint>,zone: ZoneId=ZoneId.systemDefault()): Pair<Double?,Int> {
        if(sessions.isEmpty()||days.isEmpty())return null to 0
        val byDay=days.groupBy{it.date.atZone(zone).toLocalDate()}.mapValues{it.value.first()}
        val resting=median(days.mapNotNull{it.restingHeartRate}.filter{it>0});val hrv=median(days.mapNotNull{it.heartRateVariability}.filter{it>0})
        if(resting==null&&hrv==null)return null to 0
        val threshold=median(sessions.map{it.load})?:0.0
        val ratios=sessions.filter{it.load>=threshold}.mapNotNull{session->
            val date=session.endDate.atZone(zone).toLocalDate()
            val first=byDay[date.plusDays(1)]?:return@mapNotNull null
            val second=byDay[date.plusDays(2)]?:return@mapNotNull null
            val values=buildList {
                if(resting!=null&&resting>0&&first.restingHeartRate!=null&&first.restingHeartRate>0&&second.restingHeartRate!=null&&second.restingHeartRate>0)add(normalisationRatio((first.restingHeartRate-resting)/resting,(second.restingHeartRate-resting)/resting))
                if(hrv!=null&&hrv>0&&first.heartRateVariability!=null&&first.heartRateVariability>0&&second.heartRateVariability!=null&&second.heartRateVariability>0)add(normalisationRatio((hrv-first.heartRateVariability)/hrv,(hrv-second.heartRateVariability)/hrv))
            }
            if(values.isEmpty())null else values.average()
        }
        return if(ratios.size<3)null to ratios.size else (0.85+0.45*ratios.average().coerceIn(0.0,1.0)) to ratios.size
    }
    fun toleranceEvidence(sessions: List<HistorySession>): Pair<Double?,Int> {
        if(sessions.size<2)return null to 0
        val reference=sessions.filter{(it.intensityFraction?:0.0)>0}.groupBy{it.profile}.mapValues{(_,list)->median(list.mapNotNull{it.intensityFraction})!!}
        val samples=sessions.zipWithNext().mapNotNull{(previous,next)->
            val intensity=next.intensityFraction?:return@mapNotNull null
            val usual=reference[next.profile]?:return@mapNotNull null
            if(previous.standardHours<=0||intensity<=0||usual<=0)return@mapNotNull null
            val fraction=next.startDate.hoursSince(previous.endDate)/previous.standardHours
            if(fraction<=0||fraction>=1)return@mapNotNull null
            val held=intensity/usual
            when {held>=0.95->0.85+0.15*fraction;held<0.85->1.10+0.10*(1-fraction);else->1.0}
        }
        return if(samples.size<3)null to samples.size else samples.average() to samples.size
    }
    fun summary(analysis: PersonalAnalysis): List<String> {
        if(!analysis.isPersonalised)return emptyList()
        val lines=mutableListOf(when(analysis.direction){"shorter"->"Your windows run about "+abs(analysis.percentDifference)+"% shorter than the standard estimate.";"longer"->"Your windows run about "+analysis.percentDifference+"% longer than the standard estimate.";else->"Your windows land close to the standard estimate."})
        if(analysis.reboundFactor!=null&&analysis.reboundSamples>=3)lines.add(if(analysis.reboundFactor<1)"Resting heart rate and HRV settle back quickly after your hard sessions ("+analysis.reboundSamples+" measured)." else "Resting heart rate and HRV take their time settling after your hard sessions ("+analysis.reboundSamples+" measured).")
        if(analysis.toleranceFactor!=null&&analysis.toleranceSamples>=3)lines.add(if(analysis.toleranceFactor<1)"You have held your usual intensity training inside the estimated window."else"Sessions you started inside the window came in below your usual intensity.")
        if(analysis.qualifyingSessions>0)lines.add("Based on "+analysis.qualifyingSessions+" sessions in the last 30 days, about "+String.format(java.util.Locale.US,"%.1f",analysis.sessionsPerWeek)+" a week.")
        return lines
    }
}
