package com.jackwallner.recovery.model

import java.time.Instant
import java.time.ZoneId
import kotlin.math.*

data class LoadHistory(val profile: WorkoutProfile,val load: Double,val date: Instant)
class RecoveryBaseline(loads: List<Double>,val profile: WorkoutProfile,dailyLoads: List<Double>?=null,fitnessScale: Double=1.0) {
    val loads=loads.filter{it>0}.sorted()
    val dailyLoads=(dailyLoads?:loads).filter{it>0}.sorted()
    val fitnessScale=fitnessScale.coerceIn(0.70,1.45)
    val referenceLoad get()=profile.standardTypicalLoad*fitnessScale
    val sampleCount get()=loads.size
    val dayCount get()=dailyLoads.size
    val hasEnoughSamples get()=sampleCount>=8
    val hasEstablishedBaseline get()=dayCount>=8
    val typicalLoad: Double get() {
        if(dailyLoads.isEmpty())return referenceLoad
        val personal=geometricMean(dailyLoads)?:0.0
        if(personal<=0)return referenceLoad
        val weight=min(dayCount/8.0,1.0)
        val blended=if(weight<1)exp(weight*ln(personal)+(1-weight)*ln(referenceLoad))else personal
        if(!blended.isFinite() || referenceLoad<=0)return referenceLoad
        return blended.coerceIn(referenceLoad*0.75,referenceLoad*1.40)
    }
    val quietThreshold get()=if(!hasEnoughSamples)18.0 else percentile(0.25).coerceIn(18.0,30.0)
    fun percentile(fraction: Double)=percentile(fraction,loads)
    companion object {
        const val minimumSamples=8
        const val historyDays=42
        fun standard(profile: WorkoutProfile,fitnessScale: Double=1.0)=RecoveryBaseline(emptyList(),profile,fitnessScale=fitnessScale)
        fun percentile(fraction: Double,sorted: List<Double>): Double {
            if(sorted.isEmpty())return 0.0
            if(sorted.size==1)return sorted.first()
            val position=fraction.coerceIn(0.0,1.0)*(sorted.size-1)
            val lower=floor(position).toInt();val upper=min(lower+1,sorted.lastIndex)
            return sorted[lower]+(sorted[upper]-sorted[lower])*(position-lower)
        }
        fun build(history: List<LoadHistory>,profile: WorkoutProfile,now: Instant=Instant.now(),historyDays: Int=42,fitnessScale: Double=1.0,zone: ZoneId=ZoneId.systemDefault()): RecoveryBaseline {
            val recent=history.filter{it.date>=now.daysAgo(historyDays)&&it.profile!=WorkoutProfile.easy}
            val own=recent.filter{it.profile==profile}
            val entries=when{own.size>=8->own;recent.size>=8->recent;own.isEmpty()->recent;else->own}
            val days=entries.groupBy{it.date.atZone(zone).toLocalDate()}.values.map{day->day.sumOf{it.load}}
            return RecoveryBaseline(entries.map{it.load},profile,days,fitnessScale)
        }
    }
}
