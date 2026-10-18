package com.jackwallner.recovery.data

import android.content.Context
import java.time.Instant

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject

import com.jackwallner.recovery.model.*

class Preferences(context: Context): Values {
    private val preferences=context.getSharedPreferences("recharge",Context.MODE_PRIVATE)
    override fun string(key: String)=preferences.getString(key,null)
    override fun put(key: String,value: String){preferences.edit().putString(key,value).apply()}
    override fun entries()=preferences.all.mapValues{it.value.toString()}
}
class Settings(val values: Values) {
    var onModelChange: ()->Unit={}
    var hasCompletedSetup by mutableStateOf(values.bool("hasCompletedSetup"));private set
    var hasDeferredHealthAccess by mutableStateOf(values.bool("hasDeferredHealthAccess"));private set
    var appearance by mutableStateOf(values.int("appearance").coerceIn(0,2));private set
    var profile by mutableStateOf(runCatching{CacheCodec.profile(JSONObject(values.string("athleteProfile")?:"{}"))}.getOrDefault(AthleteProfile()));private set
    var ambiguousProfile by mutableStateOf(runCatching{WorkoutProfile.valueOf(values.string("ambiguousProfile")?:"mixed")}.getOrDefault(WorkoutProfile.mixed));private set
    var maxHeartRate by mutableStateOf(values.string("maxHeartRate")?.toDoubleOrNull()?.takeIf{it in 120.0..230.0});private set
    var calibration by mutableStateOf(values.string("calibrationFactor")?.toDoubleOrNull()?.takeIf{it in 0.80..1.25}?:1.0);private set
    var useContextSignals by mutableStateOf(values.string("useContextSignals")?.toBooleanStrictOrNull()?:true);private set
    var notifyOnReady by mutableStateOf(values.string("notifyOnReady")?.toBooleanStrictOrNull()?:true);private set
    var manualWindows by mutableStateOf(runCatching{val r=JSONObject(values.string("manualWindows")?:"{}");ManualRecoveryWindows(r.number("light"),r.number("moderate"),r.number("hard"))}.getOrDefault(ManualRecoveryWindows()));private set
    var answeredFeedback by mutableStateOf(readSet("answeredFeedbackSessions"));private set
    var declinedEffort by mutableStateOf(readSet("declinedEffortSessions"));private set
    val feedbackEligibleFrom get()=values.long("feedbackEligibleFrom")?.let(Instant::ofEpochMilli)
    private fun readSet(key: String)=runCatching{val a=JSONArray(values.string(key)?:"[]");(0 until a.length()).map{a.getString(it)}.toSet()}.getOrDefault(emptySet())
    private fun writeSet(key: String,set: Set<String>)=values.put(key,JSONArray(set.toList()).toString())
    fun updateAppearance(value: Int){appearance=value.coerceIn(0,2);values.put("appearance",appearance.toString())}
    fun updateProfile(value: AthleteProfile,fromHealth: Boolean=false){if(value==profile)return;profile=value;values.put("athleteProfile",CacheCodec.profile(value).toString());if(!fromHealth)onModelChange()}
    fun updateAmbiguousProfile(value: WorkoutProfile){ambiguousProfile=value;values.put("ambiguousProfile",value.name);onModelChange()}
    fun updateMaxHeartRate(value: Double?){maxHeartRate=value?.takeIf{it.isFinite()&&it in 120.0..230.0};values.put("maxHeartRate",maxHeartRate?.toString()?:"");onModelChange()}
    fun resetCalibration(){calibration=1.0;values.put("calibrationFactor","1.0");onModelChange()}
    fun setContext(value: Boolean){useContextSignals=value;values.put("useContextSignals",value.toString());onModelChange()}
    fun setNotifications(value: Boolean){notifyOnReady=value;values.put("notifyOnReady",value.toString())}
    fun setManualWindow(intensity: SessionIntensity,hours: Double?){val copy=manualWindows.copy();copy.set(hours,intensity);manualWindows=copy;values.put("manualWindows",JSONObject().put("light",copy.light).put("moderate",copy.moderate).put("hard",copy.hard).toString());onModelChange()}
    fun applyFeedback(feedback: ReadinessFeedback,id: String){calibration=RecoveryCalibration.apply(feedback,calibration);values.put("calibrationFactor",calibration.toString());dismissFeedback(id);onModelChange()}
    fun dismissFeedback(id: String){answeredFeedback=answeredFeedback+id;writeSet("answeredFeedbackSessions",answeredFeedback)}
    fun declineEffort(id: String){declinedEffort=declinedEffort+id;writeSet("declinedEffortSessions",declinedEffort)}
    fun completeSetup(now: Instant=Instant.now()){hasCompletedSetup=true;values.put("hasCompletedSetup","true");values.put("hasAnsweredProfileQuestions","true");values.put("lastTrialOfferShownDate",now.toEpochMilli().toString());openFeedbackWindow(now);onModelChange()}
    fun openFeedbackWindow(now: Instant=Instant.now()){if(feedbackEligibleFrom==null)values.put("feedbackEligibleFrom",now.toEpochMilli().toString())}
    fun setDeferredHealth(value: Boolean){hasDeferredHealthAccess=value;values.put("hasDeferredHealthAccess",value.toString())}
    fun passiveTrialOfferAllowed(now: Instant=Instant.now())=values.long("lastTrialOfferShownDate")?.let{now.toEpochMilli()-it>=14*86_400_000L}?:true
    fun clearHealthDerivedProfile() {
        val p=profile;val derived=p.healthDerivedFields
        updateProfile(p.copy(weeklyVolume=if("weeklyVolume" in derived)null else p.weeklyVolume,primaryProfile=if("primaryProfile" in derived)null else p.primaryProfile,vo2Max=null,observedMaxHeartRate=null,bodyMassKilograms=null,healthDerivedFields=emptySet()),fromHealth=true)
        answeredFeedback=emptySet();declinedEffort=emptySet();writeSet("answeredFeedbackSessions",emptySet());writeSet("declinedEffortSessions",emptySet())
    }
    fun modelOptions(isPro: Boolean)=ModelOptions(profile,isPro,ambiguousProfile,maxHeartRate,calibration,useContextSignals,manualWindows,answeredFeedback,declinedEffort,feedbackEligibleFrom)
}
