package com.jackwallner.recovery.model

import org.json.JSONArray

data class ActivityCode(val code: Int,val name: String,val profile: WorkoutProfile,val label: String,val ambiguous: Boolean)
object WorkoutClassifier {
    val activities: List<ActivityCode> by lazy {
        val text=checkNotNull(javaClass.getResourceAsStream("/workout-classification.json")).bufferedReader().use{it.readText()}
        val rows=JSONArray(text)
        (0 until rows.length()).map{index->val r=rows.getJSONObject(index);ActivityCode(r.getInt("code"),r.getString("name"),WorkoutProfile.valueOf(r.getString("profile")),r.getString("label"),r.getBoolean("ambiguous"))}
    }
    fun profile(code: Int,ambiguousProfile: WorkoutProfile=WorkoutProfile.mixed,override: WorkoutProfile?=null): WorkoutProfile {
        override?.let{return it}
        val activity=activities.find{it.code==code}?:return WorkoutProfile.endurance
        return if(activity.ambiguous)ambiguousProfile else activity.profile
    }
    fun label(code: Int)=activities.find{it.code==code}?.label?:"workout"
    fun code(name: String)=activities.find{it.name==name}?.code?:9999
}
