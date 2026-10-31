package com.jackwallner.recovery

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime

import org.junit.Assert.*
import org.junit.Test

import com.jackwallner.recovery.model.*

/** Countdown timeline and baseline day buckets under an explicit America/Los_Angeles zone. 2026-11-01 is 25 hours long, 2027-03-14 is 23. */
class ClockBoundaryTest {
    private val la=ZoneId.of("America/Los_Angeles")
    private fun at(y: Int,mo: Int,d: Int,h: Int=0,mi: Int=0,s: Int=0)=LocalDateTime.of(y,mo,d,h,mi,s).atZone(la).toInstant()
    private fun snapshot(readyAt: Instant,end: Instant,hours: Double=12.0)=RecoverySnapshot(readyAt,end,hours)
    private fun hourly(dates: List<Instant>,now: Instant,readyAt: Instant)=dates.filter{it>now&&it<readyAt.minusSeconds(7200)&&it.atZone(la).minute==0}

    @Test fun timelineNeverStartsBeforeNowOnTheSecondHourOfFallBack() {
        val now=ZonedDateTime.of(2026,11,1,1,30,0,0,la).withLaterOffsetAtOverlap().toInstant()
        assertEquals(1,now.atZone(la).hour);assertEquals(-8*3600,now.atZone(la).offset.totalSeconds)
        val readyAt=now.plusSeconds(12*3600)
        val dates=CountdownTimeline.entryDates(snapshot(readyAt,now),now,la)
        assertEquals(now,dates.first());assertTrue(dates.all{it>=now})
        val first=hourly(dates,now,readyAt).first()
        assertEquals(now.plusSeconds(1800),first);assertEquals(2,first.atZone(la).hour)
    }

    @Test fun timelineHourlyEntriesAreWholeLocalHoursAcrossMidnightAndBothDSTChanges() {
        for(start in listOf(at(2026,7,21,23,40),at(2026,11,1,0,40),at(2027,3,14,1,20))){
            val readyAt=start.plusSeconds(30*3600)
            val dates=CountdownTimeline.entryDates(snapshot(readyAt,start,30.0),start,la)
            assertEquals(dates.sorted(),dates);assertEquals(dates.size,dates.toSet().size);assertTrue(dates.size<=106+2)
            assertTrue(readyAt in dates);assertTrue(readyAt.plusSeconds(60) in dates)
            val hours=hourly(dates,start,readyAt);assertTrue(hours.isNotEmpty())
            for(entry in hours){assertEquals(0,entry.atZone(la).minute);assertEquals(0,entry.atZone(la).second)}
            for((earlier,later) in hours.zipWithNext())assertEquals(3600,later.epochSecond-earlier.epochSecond)
        }
    }

    @Test fun baselineBucketsTrainingDaysByTheLocalMidnight() {
        fun history(vararg times: Instant)=times.map{LoadHistory(WorkoutProfile.endurance,100.0,it)}
        val now=at(2026,7,30,12)
        assertEquals(1,RecoveryBaseline.build(history(at(2026,7,20,16,59),at(2026,7,20,17,1)),WorkoutProfile.endurance,now,zone=la).dayCount)
        assertEquals(2,RecoveryBaseline.build(history(at(2026,7,20,23,59,59),at(2026,7,21,0,0,0)),WorkoutProfile.endurance,now,zone=la).dayCount)
    }

    @Test fun baselineWindowEdgeIsExactAcrossFallBack() {
        val now=at(2026,11,20,12);val edge=now.minusSeconds(42*86400L)
        assertEquals(1,RecoveryBaseline.build(listOf(LoadHistory(WorkoutProfile.endurance,100.0,edge)),WorkoutProfile.endurance,now,zone=la).dayCount)
        assertEquals(0,RecoveryBaseline.build(listOf(LoadHistory(WorkoutProfile.endurance,100.0,edge.minusSeconds(1))),WorkoutProfile.endurance,now,zone=la).dayCount)
    }
}
