package com.jackwallner.recovery.model

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.*

object CountdownFormat {
    fun remaining(seconds: Double,compact: Boolean=false): String {
        if(seconds<=0 || !seconds.isFinite())return "Ready"
        val total=ceil(seconds/60).toLong();val days=total/1440;val hours=total%1440/60;val minutes=total%60
        if(days>0)return days.toString()+"d"+if(hours>0)" "+hours+"h"else""
        if(compact&&hours>=2)return hours.toString()+"h"
        if(hours>0)return hours.toString()+"h"+if(minutes>0)" "+minutes+"m"else""
        return minutes.toString()+"m"
    }
    fun hours(hours: Double)=if(hours>0&&hours.isFinite())hours.roundAway().toString()+"h"else"0h"
    fun stackedNote(sessionHours: Double,carriedHours: Double)=hours(sessionHours)+" for this session, on top of "+hours(carriedHours)+" still to go"
    fun window(low: Double,high: Double)=if(low.roundAway()==high.roundAway())hours(high)else low.roundAway().toString()+" to "+high.roundAway()+"h"
    fun elapsed(date: Instant,now: Instant=Instant.now()): String {
        val seconds=now.hoursSince(date)*3600
        if(seconds<60)return "just now"
        if(seconds>=86400){val days=(seconds/86400).toInt();return if(days==1)"yesterday"else days.toString()+"d ago"}
        return remaining(seconds)+" ago"
    }
    fun clock(date: Instant,zone: ZoneId=ZoneId.systemDefault())=date.atZone(zone).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))
    fun readyAt(date: Instant,now: Instant=Instant.now(),zone: ZoneId=ZoneId.systemDefault()): String {
        val day=date.atZone(zone).toLocalDate();val today=now.atZone(zone).toLocalDate()
        val prefix=when(day){today->"today";today.plusDays(1)->"tomorrow";else->date.atZone(zone).format(DateTimeFormatter.ofPattern("EEE"))}
        return prefix+" at "+clock(date,zone)
    }
    fun clockWithDay(date: Instant,now: Instant,zone: ZoneId=ZoneId.systemDefault())=if(date.atZone(zone).toLocalDate()==now.atZone(zone).toLocalDate())clock(date,zone)else date.atZone(zone).format(DateTimeFormatter.ofPattern("EEE"))+" "+clock(date,zone)
    fun readySoftly(date: Instant,now: Instant=Instant.now(),zone: ZoneId=ZoneId.systemDefault()): String {
        val hour=date.atZone(zone).hour
        val part=when {hour<5->"overnight";hour<12->"morning";hour<17->"afternoon";hour<21->"evening";else->"late evening"}
        val day=date.atZone(zone).toLocalDate();val today=now.atZone(zone).toLocalDate()
        return when(day){today->"this "+part;today.plusDays(1)->"tomorrow "+part;else->date.atZone(zone).format(DateTimeFormatter.ofPattern("EEE"))+" "+part}
    }
    fun phaseDetail(phase: RecoveryPhase)=when(phase){RecoveryPhase.noRecentWorkout->"Finish a workout and Recharge will estimate a training-load window.";RecoveryPhase.ready->"Recovery estimate complete. No countdown is active.";RecoveryPhase.readySoon->"Less than two hours left on your current estimate.";RecoveryPhase.recovering->"Time left on the current training-load estimate."}
}
object RecoveryResolver {
    fun active(estimates: List<RecoveryEstimate>,now: Instant=Instant.now())=estimates.filter{it.producesCountdown&&it.readyAt>now}.maxByOrNull{it.readyAt}
    fun current(estimates: List<RecoveryEstimate>,now: Instant=Instant.now())=active(estimates,now)?:estimates.maxByOrNull{it.sessionEnd}
    fun isStale(sessionEnd: Instant,readyAt: Instant?,now: Instant)=now>maxOf(sessionEnd.plusSeconds(4*86400L),(readyAt?:sessionEnd).plusSeconds(86400))
    fun phase(estimates: List<RecoveryEstimate>,now: Instant=Instant.now()): RecoveryPhase {
        val current=current(estimates,now)?:return RecoveryPhase.noRecentWorkout
        return if(isStale(current.sessionEnd,current.readyAt,now))RecoveryPhase.noRecentWorkout else current.phase(now)
    }
    fun explanation(estimates: List<RecoveryEstimate>,now: Instant=Instant.now())=if(phase(estimates,now)==RecoveryPhase.noRecentWorkout)null else current(estimates,now)
    fun awaitingFeedback(estimates: List<RecoveryEstimate>,answered: Set<String>,eligibleFrom: Instant?=null,now: Instant=Instant.now())=estimates.filter{it.producesCountdown&&it.readyAt<=now&&it.sessionID !in answered&&now.hoursSince(it.readyAt)<48&&(eligibleFrom==null||it.readyAt>=eligibleFrom)}.maxByOrNull{it.readyAt}
}
object DuplicateWorkouts {
    fun duplicateIDs(sessions: List<SessionInput>): Set<String> {
        val ranked=sessions.sortedWith(compareByDescending<SessionInput>{it.heartRateCoverage}.thenByDescending{it.endDate.hoursSince(it.startDate).coerceAtLeast(0.0)}.thenBy{it.id})
        val kept=mutableListOf<SessionInput>();val duplicates=mutableSetOf<String>()
        ranked.forEach{session->if(kept.any{sameSession(it,session)})duplicates.add(session.id)else kept.add(session)}
        return duplicates
    }
    fun sameSession(a: SessionInput,b: SessionInput): Boolean {
        val overlap=minOf(a.endDate,b.endDate).hoursSince(maxOf(a.startDate,b.startDate))
        val longer=max(a.endDate.hoursSince(a.startDate).coerceAtLeast(0.0),b.endDate.hoursSince(b.startDate).coerceAtLeast(0.0))
        return overlap>0&&longer>0&&overlap/longer>=0.5
    }
}
enum class HealthDataState {
    current,stale;
    companion object {fun resolve(lastImportFailed: Boolean,lastSuccessfulImport: Instant?,now: Instant=Instant.now())=if(lastImportFailed&&(lastSuccessfulImport==null||now.hoursSince(lastSuccessfulImport)>6))stale else current}
}
data class RecoverySnapshot(val readyAt: Instant?=null,val sessionEnd: Instant?=null,val hours: Double=0.0) {
    fun phase(now: Instant): RecoveryPhase {
        val end=sessionEnd?:return RecoveryPhase.noRecentWorkout
        if(RecoveryResolver.isStale(end,readyAt,now))return RecoveryPhase.noRecentWorkout
        return when {readyAt==null||readyAt<=now->RecoveryPhase.ready;readyAt.hoursSince(now)<=2->RecoveryPhase.readySoon;else->RecoveryPhase.recovering}
    }
    fun progress(now: Instant): Double {
        if(sessionEnd==null||phase(now)==RecoveryPhase.noRecentWorkout)return 0.0
        if(hours<=0||readyAt==null)return 1.0
        return (1-max(readyAt.hoursSince(now),0.0)/hours).coerceIn(0.0,1.0)
    }
}
object CountdownTimeline {
    fun entryDates(snapshot: RecoverySnapshot,now: Instant,zone: ZoneId=ZoneId.systemDefault()): List<Instant> {
        val ready=snapshot.readyAt?.takeIf{it>now}?:return listOf(now)
        val dates=mutableListOf(now)
        if(ready.hoursSince(now)>2){var cursor=now.atZone(zone).withMinute(0).withSecond(0).withNano(0).plusHours(1).toInstant();while(cursor<ready.minusSeconds(7200)&&dates.size<106){dates.add(cursor);cursor=cursor.plusSeconds(3600)}}
        var cursor=maxOf(now,ready.minusSeconds(7200))
        while(cursor<ready&&dates.size<106){if(cursor>now)dates.add(cursor);cursor=cursor.plusSeconds(900)}
        dates.add(ready);dates.add(ready.plusSeconds(60))
        return dates.distinct().sorted()
    }
    fun refreshDate(snapshot: RecoverySnapshot,now: Instant)=snapshot.readyAt?.takeIf{it>now}?.let{minOf(it.plusSeconds(120),now.plusSeconds(14400))}?:now.plusSeconds(21600)
}
