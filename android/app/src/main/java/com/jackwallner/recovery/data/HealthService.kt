package com.jackwallner.recovery.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import kotlin.reflect.KClass

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.*
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

import com.jackwallner.recovery.BuildConfig
import com.jackwallner.recovery.model.*

data class ReceiptRow(val title: String,val value: String,val detail: String)
data class HealthState(
    val workouts: List<WorkoutRecord> = emptyList(),val days: List<DailyContext> = emptyList(),val scored: ScoredRecovery=ScoredRecovery(),
    val granted: Set<String> = emptySet(),val refreshing: Boolean=false,val status: String="Connect Health Connect",val error: String?=null,
    val updated: Instant?=null,val lastImportFailed: Boolean=false,val receipt: List<ReceiptRow> = emptyList()
) {
    val dataState get()=HealthDataState.resolve(lastImportFailed,updated)
}
class HealthService(private val context: Context,private val settings: Settings,private val review: ReviewTracker,private val isPro: ()->Boolean) {
    private val mutex=Mutex()
    private val cache=context.getFileStreamPath("recovery-cache.json")
    private val mutable=MutableStateFlow(HealthState())
    val state=mutable.asStateFlow()
    var onPublished: (HealthState)->Unit={}
    var onCleared: ()->Unit={}
    private var loaded=false
    private var automation=false
    val sdkStatus get()=HealthConnectClient.getSdkStatus(context)
    fun client()=HealthConnectClient.getOrCreate(context)
    val corePermissions get()=setOf(HealthPermission.getReadPermission(ExerciseSessionRecord::class))
    val signalTypes: List<KClass<out Record>> = listOf(HeartRateRecord::class,RestingHeartRateRecord::class,HeartRateVariabilityRmssdRecord::class,SleepSessionRecord::class,RespiratoryRateRecord::class,ActiveCaloriesBurnedRecord::class,Vo2MaxRecord::class,WeightRecord::class)
    fun availableFeature(feature: Int)=sdkStatus==HealthConnectClient.SDK_AVAILABLE&&client().features.getFeatureStatus(feature)==HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
    fun permissions(background: Boolean=false): Set<String> = buildSet {
        addAll(corePermissions);signalTypes.forEach{add(HealthPermission.getReadPermission(it))}
        if(availableFeature(HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY))add(HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY)
        if(background&&availableFeature(HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND))add(HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND)
    }
    fun settingsIntent()=if(sdkStatus==HealthConnectClient.SDK_AVAILABLE)Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)else Intent(Intent.ACTION_VIEW,Uri.parse("market://details?id=com.google.android.apps.healthdata"))
    private suspend fun <T: Record> read(type: KClass<T>,start: Instant,end: Instant,granted: Set<String>): List<T> {
        if(HealthPermission.getReadPermission(type) !in granted)return emptyList()
        val records=mutableListOf<T>();var token: String?=null
        do {val response=client().readRecords(ReadRecordsRequest(type,TimeRangeFilter.between(start,end),pageSize=1000,pageToken=token));records.addAll(response.records);token=response.pageToken}while(token!=null)
        return records
    }
    suspend fun refresh(background: Boolean=false,cachedOnly: Boolean=false): Unit=mutex.withLock {
        if(automation)return@withLock
        if(sdkStatus!=HealthConnectClient.SDK_AVAILABLE){clear("Health Connect needs to be installed or updated");return@withLock}
        mutable.value=mutable.value.copy(refreshing=true,error=null)
        try {
            val granted=client().permissionController.getGrantedPermissions()
            if(!granted.containsAll(corePermissions)){clear("Workout permission is not granted",granted);settings.setDeferredHealth(true);return@withLock}
            if(!loaded){restore(granted);loaded=true}
            sanitize(granted)
            if(cachedOnly || (background&&HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND !in granted)){mutable.value=mutable.value.copy(refreshing=false);onPublished(mutable.value);return@withLock}
            val now=Instant.now();val zone=ZoneId.systemDefault()
            val cutoff=now.atZone(zone).toLocalDate().minusDays(120).atStartOfDay(zone).toInstant()
            val first=settings.values.long("healthReadWindowStart")?.let(Instant::ofEpochSecond)?:now.daysAgo(29)
            val start=if(HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY in granted)cutoff else maxOf(first,cutoff)
            val sessions=read(ExerciseSessionRecord::class,start,now,granted)
            val heart=read(HeartRateRecord::class,start,now,granted).flatMap{r->r.samples.map{HeartSample(it.time,it.beatsPerMinute.toDouble(),r.metadata.dataOrigin.packageName)}}
            val resting=read(RestingHeartRateRecord::class,start,now,granted)
            val hrv=read(HeartRateVariabilityRmssdRecord::class,start,now,granted)
            val sleep=read(SleepSessionRecord::class,start,now,granted)
            val respiratory=read(RespiratoryRateRecord::class,start,now,granted)
            val vo2=read(Vo2MaxRecord::class,start,now,granted).maxByOrNull{it.time}?.vo2MillilitersPerMinuteKilogram
            val mass=read(WeightRecord::class,start,now,granted).maxByOrNull{it.time}?.weight?.inKilograms
            val old=mutable.value.workouts.associateBy{it.id}
            val workouts=mutableListOf<WorkoutRecord>()
            val energyAllowed=HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class) in granted
            for(record in sessions.filter{it.endTime<=now}) {
                val paused=HealthMath.union(record.segments.filter{it.segmentType==ExerciseSegment.EXERCISE_SEGMENT_TYPE_PAUSE}.map{TimeInterval(it.startTime,it.endTime)}).sumOf{it.end.hoursSince(it.start)*60}
                val minutes=(Duration.between(record.startTime,record.endTime).toMillis()/60000.0-paused).coerceAtLeast(0.0)
                if(minutes<1||minutes>1440)continue
                val summary=withContext(Dispatchers.Default){HealthMath.heartSummary(heart,record.startTime,record.endTime,minutes,record.metadata.dataOrigin.packageName)}
                val energy=if(energyAllowed)client().aggregate(AggregateRequest(setOf(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL),TimeRangeFilter.between(record.startTime,record.endTime)))[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories else null
                val previous=old[record.metadata.id]
                workouts.add(WorkoutRecord(record.metadata.id,AndroidWorkoutTypes.code(record.exerciseType),record.startTime,record.endTime,minutes,energy,summary.average,summary.peak,summary.coverage,summary.distribution,record.metadata.dataOrigin.packageName,previous?.reportedEffort,previous?.intensityOverride))
            }
            // Exercise the energy permission even when the shared store is empty.
            if(energyAllowed&&sessions.isEmpty())client().aggregate(AggregateRequest(setOf(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL),TimeRangeFilter.between(start,now)))
            val asleep=setOf(SleepSessionRecord.STAGE_TYPE_SLEEPING,SleepSessionRecord.STAGE_TYPE_LIGHT,SleepSessionRecord.STAGE_TYPE_DEEP,SleepSessionRecord.STAGE_TYPE_REM)
            val intervals=sleep.flatMap{record->if(record.stages.isEmpty())listOf(TimeInterval(record.startTime,record.endTime))else record.stages.filter{it.stage in asleep}.map{TimeInterval(it.startTime,it.endTime)}}
            val sleepHours=HealthMath.sleepHours(intervals,zone)
            val rhrByDay=resting.groupBy{it.time.atZone(zone).toLocalDate()}
            val hrvByDay=hrv.groupBy{it.time.atZone(zone).toLocalDate()}
            val respiratoryByDay=respiratory.groupBy{it.time.atZone(zone).toLocalDate()}
            val keys=rhrByDay.keys+hrvByDay.keys+respiratoryByDay.keys+sleepHours.keys
            val days=keys.map{day->DailyContext(day.atStartOfDay(zone).toInstant(),sleepHours[day],PersonalRecoveryModel.median(rhrByDay[day].orEmpty().map{it.beatsPerMinute.toDouble()}),PersonalRecoveryModel.median(hrvByDay[day].orEmpty().map{it.heartRateVariabilityMillis}),PersonalRecoveryModel.median(respiratoryByDay[day].orEmpty().map{it.rate}))}.sortedBy{it.date}
            mergeProfile(workouts,vo2,mass,granted,now)
            publish(workouts,days,granted,now,false)
            settings.values.put("healthReadWindowStart",first.epochSecond.toString());settings.setDeferredHealth(false)
        } catch(error: Exception) {
            if(error is CancellationException)throw error
            if(error is SecurityException)clear("Health permissions changed. Connect again to refresh.")
            else mutable.value=mutable.value.copy(refreshing=false,lastImportFailed=true,error="Couldn't read Health Connect. Check access and try again.")
        }
    }
    private fun mergeProfile(workouts: List<WorkoutRecord>,vo2: Double?,mass: Double?,granted: Set<String>,now: Instant) {
        val p=settings.profile;val tags=p.healthDerivedFields.toMutableSet()
        val derived=RecoveryEngine.derivedTrainingProfile(workouts,settings.ambiguousProfile,now)
        val volume=if(derived.first!=null&&(p.weeklyVolume==null||"weeklyVolume" in tags)){tags.add("weeklyVolume");derived.first}else p.weeklyVolume
        val primary=derived.second?.also{tags.add("primaryProfile")}?:p.primaryProfile
        val peaks=workouts.filter{it.coverage>=0.5&&it.end<=now}.mapNotNull{it.peakHR?.takeIf{peak->peak>0}}
        val observed=if(peaks.size>=4)RecoveryBaseline.percentile(0.90,peaks.sorted()).takeIf{it in 120.0..230.0}else null
        if(vo2!=null)tags.add("vo2Max");if(mass!=null)tags.add("bodyMass");if(observed!=null)tags.add("observedMaxHeartRate")
        settings.updateProfile(p.copy(weeklyVolume=volume,primaryProfile=primary,vo2Max=vo2,bodyMassKilograms=mass,observedMaxHeartRate=if(HealthPermission.getReadPermission(HeartRateRecord::class) in granted)maxOf(observed?:0.0,p.observedMaxHeartRate?:0.0).takeIf{it>0}else null,healthDerivedFields=tags),fromHealth=true)
    }
    private suspend fun publish(workouts: List<WorkoutRecord>,days: List<DailyContext>,granted: Set<String>,updated: Instant?,unfreeze: Boolean) {
        val scored=withContext(Dispatchers.Default){RecoveryEngine.score(workouts,days,settings.modelOptions(isPro()),mutable.value.scored.estimates,unfreeze)}
        val next=HealthState(workouts,days,scored,granted,false,if(workouts.isEmpty())"Connected, no workouts shared"else"Connected",updated=updated,receipt=receipt(workouts,days,scored))
        if(!automation)withContext(Dispatchers.IO){save(next)}
        mutable.value=next
        if(scored.estimates.isNotEmpty())review.hasSeenEstimate=true
        RecoveryResolver.current(scored.estimates)?.takeIf{it.producesCountdown&&it.readyAt<=Instant.now()}?.let{review.recordReadyMoment(it.sessionID)}
        onPublished(next)
    }
    suspend fun rescore(unfreezeAll: Boolean=false): Unit=mutex.withLock {val s=mutable.value;if(!automation&&!s.granted.containsAll(corePermissions))return@withLock;publish(s.workouts,s.days,s.granted,s.updated,unfreezeAll)}
    suspend fun clockTick(): Unit=mutex.withLock {
        val s=mutable.value;val now=Instant.now()
        val feedback=if(isPro())RecoveryResolver.awaitingFeedback(s.scored.estimates,settings.answeredFeedback,settings.feedbackEligibleFrom?:Instant.MAX,now)else null
        mutable.value=s.copy(scored=s.scored.copy(awaitingFeedback=feedback))
        RecoveryResolver.current(s.scored.estimates,now)?.takeIf{it.producesCountdown&&it.readyAt<=now}?.let{review.recordReadyMoment(it.sessionID)}
    }
    suspend fun recordEffort(id: String,effort: Double): Unit=mutex.withLock {val s=mutable.value;publish(s.workouts.map{if(it.id==id)it.copy(reportedEffort=effort.coerceIn(1.0,10.0))else it},s.days,s.granted,s.updated,true)}
    suspend fun overrideIntensity(id: String,intensity: SessionIntensity?): Unit=mutex.withLock {if(!isPro())return@withLock;val s=mutable.value;publish(s.workouts.map{if(it.id==id)it.copy(intensityOverride=intensity)else it},s.days,s.granted,s.updated,true)}
    private suspend fun sanitize(granted: Set<String>) {
        val s=mutable.value
        if(s.granted==granted)return
        fun has(type: KClass<out Record>)=HealthPermission.getReadPermission(type) in granted
        val workouts=s.workouts.map{it.copy(averageHR=if(has(HeartRateRecord::class))it.averageHR else null,peakHR=if(has(HeartRateRecord::class))it.peakHR else null,coverage=if(has(HeartRateRecord::class))it.coverage else 0.0,distribution=if(has(HeartRateRecord::class))it.distribution else null,energy=if(has(ActiveCaloriesBurnedRecord::class))it.energy else null)}
        val days=s.days.map{it.copy(sleep=if(has(SleepSessionRecord::class))it.sleep else null,resting=if(has(RestingHeartRateRecord::class))it.resting else null,hrv=if(has(HeartRateVariabilityRmssdRecord::class))it.hrv else null,respiratory=if(has(RespiratoryRateRecord::class))it.respiratory else null,recovery=null)}
        val p=settings.profile;settings.updateProfile(p.copy(vo2Max=if(has(Vo2MaxRecord::class))p.vo2Max else null,bodyMassKilograms=if(has(WeightRecord::class))p.bodyMassKilograms else null,observedMaxHeartRate=if(has(HeartRateRecord::class))p.observedMaxHeartRate else null),fromHealth=true)
        publish(workouts,days,granted,s.updated,true)
    }
    suspend fun deleteLocalData(): Unit=mutex.withLock {clear("Local health data deleted. Connect to import again.")}
    private suspend fun clear(status: String,granted: Set<String> = emptySet()) {
        withContext(Dispatchers.IO){cache.delete();java.io.File(cache.parentFile,"recovery-cache.tmp").delete()}
        loaded=false;settings.clearHealthDerivedProfile();settings.values.put("healthReadWindowStart","")
        mutable.value=HealthState(status=status,granted=granted);onCleared()
    }
    private fun save(s: HealthState) {
        val data=JSONObject().put("workouts",JSONArray(s.workouts.map(CacheCodec::workout))).put("days",JSONArray(s.days.map(CacheCodec::day))).put("estimates",JSONArray(s.scored.estimates.map(CacheCodec::estimate))).put("granted",JSONArray(s.granted.toList())).put("updated",s.updated?.toString())
        val temporary=java.io.File(cache.parentFile,"recovery-cache.tmp");temporary.writeText(data.toString());check(temporary.renameTo(cache)){"Could not save local health cache"}
    }
    private suspend fun restore(granted: Set<String>) {
        val saved=withContext(Dispatchers.IO){runCatching{if(!cache.exists())null else JSONObject(cache.readText())}.getOrNull()}?:return
        runCatching {
            val workouts=saved.getJSONArray("workouts").objects().map(CacheCodec::workout);val days=saved.getJSONArray("days").objects().map(CacheCodec::day)
            val estimates=saved.getJSONArray("estimates").objects().map(CacheCodec::estimate)
            mutable.value=HealthState(workouts,days,ScoredRecovery(estimates=estimates),saved.getJSONArray("granted").strings().toSet(),status="Previously read health data",updated=saved.optionalText("updated")?.let(Instant::parse))
        }.onFailure{withContext(Dispatchers.IO){cache.delete()}}
    }
    private fun receipt(workouts: List<WorkoutRecord>,days: List<DailyContext>,scored: ScoredRecovery): List<ReceiptRow> {
        val rows=mutableListOf<ReceiptRow>();val p=settings.profile
        if(workouts.isNotEmpty())rows.add(ReceiptRow("Workouts scored",scored.estimates.size.toString(),"Read from Health Connect. Duplicate recordings count once."))
        p.observedMaxHeartRate?.let{rows.add(ReceiptRow(if(p.usesObservedMaxHeartRate)"Your highest heart rate"else"Heart-rate ceiling",it.roundAway().toString()+" bpm","Measured from shared workout heart-rate samples."))}
        p.vo2Max?.let{rows.add(ReceiptRow("Cardio fitness (VO2 max)",it.roundAway().toString(),"Sets the training level your sessions are compared against."))}
        fun add(title: String,values: List<Double>,unit: String,detail: String){PersonalRecoveryModel.median(values.filter{it>0})?.let{rows.add(ReceiptRow(title,String.format(java.util.Locale.US,if(unit=="h")"%.1f%s"else"%.0f %s",it,unit),detail))}}
        add("Resting heart rate",days.mapNotNull{it.resting},"bpm","Watched night to night against your own baseline.")
        add("Heart rate variability (RMSSD)",days.mapNotNull{it.hrv},"ms","Compared with your own RMSSD baseline. This is a different measure from Apple Health SDNN.")
        add("Average sleep",days.mapNotNull{it.sleep},"h","A short night lengthens the estimate a little; a long one shortens it.")
        add("Overnight breathing rate",days.mapNotNull{it.respiratory},"/min","Adds an overnight signal alongside sleep, HRV and resting heart rate.")
        p.bodyMassKilograms?.let{rows.add(ReceiptRow("Body weight",String.format(java.util.Locale.US,"%.0f kg",it),"Corrects the calories-to-intensity estimate."))}
        val energy=workouts.count{(it.energy?:0.0)>0};if(energy>0)rows.add(ReceiptRow("Workout energy",energy.toString()+" sessions","Health Connect energy totals within the workout window, used when heart rate is missing."))
        return rows
    }
    fun seedForDebug(workouts: List<WorkoutRecord>,days: List<DailyContext>) {
        check(BuildConfig.DEBUG);automation=true;loaded=true
        val scored=RecoveryEngine.score(workouts,days,settings.modelOptions(isPro()))
        mutable.value=HealthState(workouts,days,scored,status="Local test data",updated=Instant.now(),receipt=receipt(workouts,days,scored))
    }
}
