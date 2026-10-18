package com.jackwallner.recovery.model

import java.time.Instant
import kotlin.math.*

data class ObservedSession(val id: String="",val profile: WorkoutProfile,val startDate: Instant,val endDate: Instant,val load: Double)
data class BandPattern(val band: SessionIntensity,val medianGapHours: Double,val sampleCount: Int)
data class ObservedWindow(val hours: Double,val band: SessionIntensity,val sampleCount: Int,val isBandSpecific: Boolean)
data class ObservedRecoveryPattern(val bands: Map<SessionIntensity,BandPattern> = emptyMap(),val pooled: BandPattern?=null,val lightCeiling: Double=0.0,val moderateCeiling: Double=0.0,val sessionCount: Int=0) {
    val hasEvidence get()=pooled!=null
    fun band(load: Double,referenceLoad: Double): SessionIntensity {
        val measured=lightCeiling>0&&moderateCeiling>lightCeiling
        val low=if(measured)lightCeiling else referenceLoad*0.70
        val high=if(measured)moderateCeiling else referenceLoad*1.30
        return when {load<=low->SessionIntensity.light;load<=high->SessionIntensity.moderate;else->SessionIntensity.hard}
    }
    fun evidence(band: SessionIntensity)=bands[band]?.takeIf{it.sampleCount>=3}?:pooled?.takeIf{it.sampleCount>=3}
    fun isBandSpecific(band: SessionIntensity)=(bands[band]?.sampleCount?:0)>=3
    fun usualGapHours(band: SessionIntensity)=evidence(band)?.medianGapHours?.finiteOr(6.0)?.coerceIn(6.0,96.0)
    fun window(load: Double,referenceLoad: Double): ObservedWindow? {
        val band=band(load,referenceLoad);val evidence=evidence(band)?:return null
        return ObservedWindow(usualGapHours(band)!!,band,evidence.sampleCount,isBandSpecific(band))
    }
    companion object {
        const val minimumGaps=3
        const val windowDays=120
        fun analyse(sessions: List<ObservedSession>,now: Instant=Instant.now(),windowDays: Int=120): ObservedRecoveryPattern {
            val ordered=sessions.filter{it.profile!=WorkoutProfile.easy&&it.load>0&&it.endDate>=now.daysAgo(windowDays)&&it.endDate<=now}.sortedWith(compareBy({it.endDate},{it.startDate},{it.id}))
            if(ordered.size<2)return ObservedRecoveryPattern()
            val loads=ordered.map{it.load}.sorted()
            val light=RecoveryBaseline.percentile(1.0/3,loads);val moderate=RecoveryBaseline.percentile(2.0/3,loads);val median=RecoveryBaseline.percentile(0.5,loads)
            val grouped=mutableMapOf<SessionIntensity,MutableList<Double>>()
            ordered.forEachIndexed {index,session->
                val bar=min(session.load*0.85,median*0.70)
                var gap: Double?=null
                for(next in ordered.drop(index+1)) {
                    val hours=next.startDate.hoursSince(session.endDate)
                    if(!hours.isFinite()||hours>168)break
                    if(next.load<bar||hours<1)continue
                    gap=hours;break
                }
                if(gap!=null){val band=when{session.load<=light->SessionIntensity.light;session.load<=moderate->SessionIntensity.moderate;else->SessionIntensity.hard};grouped.getOrPut(band){mutableListOf()}.add(gap)}
            }
            val bands=grouped.mapValues{(band,gaps)->BandPattern(band,RecoveryBaseline.percentile(0.5,gaps.sorted()),gaps.size)}
            val all=grouped.values.flatten()
            val pooled=if(all.isEmpty())null else BandPattern(SessionIntensity.moderate,RecoveryBaseline.percentile(0.5,all.sorted()),all.size)
            return ObservedRecoveryPattern(bands,pooled,light,moderate,ordered.size)
        }
    }
}
