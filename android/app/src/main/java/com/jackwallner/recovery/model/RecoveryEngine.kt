package com.jackwallner.recovery.model

import java.time.Instant
import java.time.ZoneId

data class WorkoutRecord(
    val id: String,val activityCode: Int,val start: Instant,val end: Instant,val minutes: Double,
    val energy: Double?=null,val averageHR: Double?=null,val peakHR: Double?=null,val coverage: Double=0.0,
    val distribution: HeartRateDistribution?=null,val source: String="",val reportedEffort: Double?=null,val intensityOverride: SessionIntensity?=null
) {
    fun profile(ambiguous: WorkoutProfile)=WorkoutClassifier.profile(activityCode,ambiguous).let{intensityOverride?.promoting(it)?:it}
    fun input(options: ModelOptions,resting: Double?)=SessionInput(id,profile(options.ambiguousProfile),start,end,minutes,averageHR,resting,options.maxHeartRate?:options.profile.effectiveMaxHeartRate,coverage,distribution,energy,reportedEffort,intensityOverride,options.profile.bodyMassKilograms,WorkoutClassifier.label(activityCode))
}
data class DailyContext(val date: Instant,val sleep: Double?=null,val resting: Double?=null,val hrv: Double?=null,val respiratory: Double?=null,val recovery: Double?=null)
data class ModelOptions(
    val profile: AthleteProfile=AthleteProfile(),val isPro: Boolean=false,val ambiguousProfile: WorkoutProfile=WorkoutProfile.mixed,
    val maxHeartRate: Double?=null,val calibration: Double=1.0,val useContextSignals: Boolean=true,val manualWindows: ManualRecoveryWindows=ManualRecoveryWindows(),
    val answeredFeedback: Set<String> = emptySet(),val declinedEffort: Set<String> = emptySet(),val feedbackEligibleFrom: Instant?=null
)
data class ScoredRecovery(
    val estimates: List<RecoveryEstimate> = emptyList(),val standard: List<RecoveryEstimate> = emptyList(),val personalized: List<RecoveryEstimate> = emptyList(),
    val personalAnalysis: PersonalAnalysis=PersonalAnalysis(),val preview: PersonalizedPreview=PersonalizedPreview.reference(1.0),
    val observedPattern: ObservedRecoveryPattern=ObservedRecoveryPattern(),val awaitingEffort: WorkoutRecord?=null,val awaitingFeedback: RecoveryEstimate?=null,
    val duplicateIDs: Set<String> = emptySet()
) {
    fun loadBalance(now: Instant): Pair<Double,Double> = estimates.filter{it.sessionEnd<=now}.let{recent->recent.filter{it.sessionEnd>=now.daysAgo(7)}.sumOf{it.load.value} to recent.filter{it.sessionEnd>=now.daysAgo(28)}.sumOf{it.load.value}/4}
}
object RecoveryEngine {
    fun score(workouts: List<WorkoutRecord>,days: List<DailyContext>,options: ModelOptions,previous: List<RecoveryEstimate> = emptyList(),unfreezeAll: Boolean=false,now: Instant=Instant.now(),zone: ZoneId=ZoneId.systemDefault()): ScoredRecovery {
        val raw=workouts.map{it.input(options,null)}
        val duplicateIDs=DuplicateWorkouts.duplicateIDs(raw)
        val ordered=workouts.filter{it.id !in duplicateIDs}.sortedWith(compareBy({it.end},{it.start},{it.id}))
        val contexts=days.filter{it.date>=now.daysAgo(30)&&it.date<=now}
        val byDay=contexts.groupBy{it.date.atZone(zone).toLocalDate()}.mapValues{it.value.first()}
        val restingBase=PersonalRecoveryModel.median(contexts.mapNotNull{it.resting}.filter{it>0})
        val hrvBase=PersonalRecoveryModel.median(contexts.mapNotNull{it.hrv}.filter{it>0})
        val respiratoryBase=PersonalRecoveryModel.median(contexts.mapNotNull{it.respiratory}.filter{it>0})
        val inputs=ordered.map{record->val resting=days.filter{it.date<=record.end&&it.date>=record.end.daysAgo(30)&&it.resting!=null&&it.resting>0}.maxByOrNull{it.date}?.resting;record.input(options,resting)}
        val loads=inputs.map{SessionLoadCalculator.profiledLoad(it).value}
        val pattern=ObservedRecoveryPattern.analyse(inputs.mapIndexed{index,s->ObservedSession(s.id,s.profile,s.startDate,s.endDate,loads[index])},now)
        val standard=mutableListOf<RecoveryEstimate>();var standardReady: Instant?=null
        inputs.forEachIndexed{index,session->
            val baseline=RecoveryBaseline.standard(session.profile,options.profile.fitnessScale)
            val estimate=RecoveryCalculator.estimate(session,baseline,carriedHours=RecoveryCalculator.carriedHours(session,standardReady),observed=pattern.window(loads[index],baseline.referenceLoad),now=now)
            standard.add(estimate);if(estimate.producesCountdown)standardReady=estimate.readyAt
        }
        val analysis=PersonalRecoveryModel.analyse(options.profile,inputs.zip(standard).map{(s,e)->HistorySession(s.id,s.profile,s.endDate,e.load.value,e.totalHours,s.startDate,SessionLoadCalculator.intensityFraction(s))},contexts.map{DayPoint(it.date,it.resting,it.hrv,it.recovery)},now,zone)
        val history=mutableListOf<LoadHistory>();val personalized=mutableListOf<RecoveryEstimate>();val results=mutableListOf<RecoveryEstimate>()
        val previousByID=previous.associateBy{it.sessionID}
        var personalizedReady: Instant?=null;var preview: PersonalizedPreview?=null
        inputs.forEachIndexed{index,session->
            val reference=RecoveryBaseline.standard(session.profile,options.profile.fitnessScale).referenceLoad
            val context=if(options.useContextSignals)contextFor(session,byDay,restingBase,hrvBase,respiratoryBase,zone)else RecoveryContext()
            val estimate=RecoveryCalculator.estimate(session,RecoveryBaseline.build(history,session.profile,session.endDate,fitnessScale=options.profile.fitnessScale,zone=zone),context,options.calibration,RecoveryPersonalization.personalized(analysis.factor),standard[index].hours,RecoveryCalculator.carriedHours(session,personalizedReady),pattern.window(loads[index],reference),options.manualWindows.hours(pattern.band(loads[index],reference)),now)
            personalized.add(estimate);if(estimate.producesCountdown)personalizedReady=estimate.readyAt
            if(standard[index].producesCountdown||estimate.producesCountdown)preview=PersonalizedPreview("Your last "+session.activityLabel,standard[index].hours,estimate.hours,false)
            val selected=if(options.isPro)estimate else standard[index]
            val frozen=previousByID[session.id]?.takeIf{!unfreezeAll&&it.readyAt<=now&&it.modelVersion==recoveryModelVersion}
            results.add(frozen?:selected)
            history.add(LoadHistory(session.profile,selected.load.value,session.endDate))
        }
        val reference=PersonalizedPreview.reference(analysis.factor)
        val comparison=preview?.takeIf{it.isVisiblyDifferent}?:reference.takeIf{it.isVisiblyDifferent}?:preview?:reference
        val awaitingEffort=ordered.filterIndexed{index,record->val input=inputs[index];val source=SessionLoadCalculator.profiledLoad(input).source;record.reportedEffort==null&&record.intensityOverride==null&&input.profile.wantsEffortInput&&(source==LoadSource.energy||source==LoadSource.duration)&&now.hoursSince(record.end)<48&&record.id !in options.declinedEffort}.maxByOrNull{it.end}
        val feedback=if(options.isPro)RecoveryResolver.awaitingFeedback(results,options.answeredFeedback,options.feedbackEligibleFrom?:Instant.MAX,now)else null
        return ScoredRecovery(results.sortedByDescending{it.sessionEnd},standard,personalized,analysis,comparison,pattern,awaitingEffort,feedback,duplicateIDs)
    }
    private fun contextFor(session: SessionInput,byDay: Map<java.time.LocalDate,DailyContext>,resting: Double?,hrv: Double?,respiratory: Double?,zone: ZoneId): RecoveryContext {
        val day=session.endDate.atZone(zone).toLocalDate();val before=byDay[day]
        val following=(1L..4L).mapNotNull{offset->val date=day.plusDays(offset);val night=byDay[date]?:return@mapNotNull null;Night(date.atStartOfDay(zone).toInstant(),night.sleep,night.hrv,night.resting,night.respiratory)}
        return RecoveryContext(before?.sleep,before?.hrv,hrv,before?.resting,resting,before?.respiratory,respiratory,following)
    }
    fun derivedTrainingProfile(workouts: List<WorkoutRecord>,ambiguous: WorkoutProfile,now: Instant=Instant.now(),zone: ZoneId=ZoneId.systemDefault()): Pair<WeeklyVolume?,WorkoutProfile?> {
        val inputs=workouts.map{it.input(ModelOptions(ambiguousProfile=ambiguous),null)}
        val duplicates=DuplicateWorkouts.duplicateIDs(inputs)
        val cutoff=now.atZone(zone).toLocalDate().minusDays(28).atStartOfDay(zone).toInstant()
        val recent=workouts.filter{it.end>=cutoff&&it.profile(ambiguous)!=WorkoutProfile.easy&&it.id !in duplicates}
        if(recent.size<6)return null to null
        val dominant=recent.groupingBy{it.profile(ambiguous)}.eachCount().entries.sortedWith(compareByDescending<Map.Entry<WorkoutProfile,Int>>{it.value}.thenBy{it.key.name}).firstOrNull()?.key
        return WeeklyVolume.forSessionsPerWeek(recent.size/4.0) to dominant
    }
}
