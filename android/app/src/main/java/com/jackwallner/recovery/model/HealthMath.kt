package com.jackwallner.recovery.model

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

data class HeartSample(val time: Instant,val bpm: Double,val source: String)
data class HeartSummary(val average: Double?=null,val peak: Double?=null,val coverage: Double=0.0,val distribution: HeartRateDistribution?=null)
data class TimeInterval(val start: Instant,val end: Instant)
object HealthMath {
    fun heartSummary(samples: List<HeartSample>,start: Instant,end: Instant,minutes: Double,preferredSource: String): HeartSummary {
        if(minutes<=0)return HeartSummary()
        val sources=samples.filter{it.time>=start&&it.time<=end&&it.bpm.isFinite()&&it.bpm in 30.0..240.0}.groupBy{it.source}
        val summaries=sources.mapValues{(_,values)->
            val ordered=values.distinctBy{it.time to it.bpm}.sortedBy{it.time}
            val bpm=ordered.map{it.bpm}
            val gaps=ordered.zipWithNext().map{(a,b)->Duration.between(a.time,b.time).toMillis()/1000.0}.filter{it>0}
            // A lone sample cannot establish the source's sampling cadence.
            val interval=PersonalRecoveryModel.median(gaps)?.coerceIn(1.0,60.0)?:0.0
            HeartSummary(bpm.average(),RecoveryBaseline.percentile(0.98,bpm.sorted()),(bpm.size*interval/(minutes*60)).coerceIn(0.0,1.0),HeartRateDistribution.fromSamples(bpm,interval))
        }
        val preferred=summaries[preferredSource]
        if(preferred!=null&&preferred.coverage>=0.5)return preferred
        return summaries.entries.sortedWith(compareByDescending<Map.Entry<String,HeartSummary>>{it.value.coverage}.thenBy{it.key}).firstOrNull()?.value?:HeartSummary()
    }
    fun union(intervals: List<TimeInterval>): List<TimeInterval> {
        val merged=mutableListOf<TimeInterval>()
        intervals.filter{it.end>it.start}.sortedBy{it.start}.forEach{interval->
            val last=merged.lastOrNull()
            if(last!=null&&interval.start<=last.end)merged[merged.lastIndex]=TimeInterval(last.start,maxOf(last.end,interval.end))else merged.add(interval)
        }
        return merged
    }
    fun sleepHours(intervals: List<TimeInterval>,zone: ZoneId=ZoneId.systemDefault()): Map<LocalDate,Double> = union(intervals).groupBy{it.end.atZone(zone).toLocalDate()}.mapValues{(_,list)->list.sumOf{it.end.hoursSince(it.start)}}
}
