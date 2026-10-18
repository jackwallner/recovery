package com.jackwallner.recovery.model

import kotlin.math.*

enum class TrainingExperience(val label: String,val recoveryFactor: Double,val fitnessFactor: Double) {
    underOneYear("Less than a year",1.08,0.85),oneToThreeYears("1 to 3 years",1.0,1.0),threeToTenYears("3 to 10 years",0.96,1.10),tenYearsPlus("10 years or more",0.94,1.18)
}
enum class BounceBackHabit(val label: String,val recoveryFactor: Double) {nextDay("Usually the next day",0.86),aboutTwoDays("About two days",1.0),threeOrMoreDays("Three days or more",1.16),notSure("I honestly don't know",1.0)}
enum class WeeklyVolume(val label: String,val fitnessFactor: Double) {
    oneOrTwo("1 to 2",0.78),threeOrFour("3 to 4",1.0),fiveOrSix("5 to 6",1.20),sevenPlus("7 or more",1.40);
    companion object {fun forSessionsPerWeek(sessions: Double)=when {sessions<2.5->oneOrTwo;sessions<4.5->threeOrFour;sessions<6.5->fiveOrSix;else->sevenPlus}}
}
enum class AthleteSex {unspecified,female,male}
data class AthleteProfile(
    val age: Int?=null,val sex: AthleteSex=AthleteSex.unspecified,val experience: TrainingExperience?=null,
    val bounceBack: BounceBackHabit?=null,val weeklyVolume: WeeklyVolume?=null,val primaryProfile: WorkoutProfile?=null,
    var vo2Max: Double?=null,var observedMaxHeartRate: Double?=null,var bodyMassKilograms: Double?=null,val healthDerivedFields: Set<String> = emptySet()
) {
    init {vo2Max=vo2Max.finite()?.takeIf{it in 10.0..90.0};observedMaxHeartRate=observedMaxHeartRate.finite()?.takeIf{it in 120.0..230.0};bodyMassKilograms=bodyMassKilograms.finite()?.takeIf{it in 30.0..250.0}}
    val predictedMaxHeartRate get()=age?.takeIf{it in 13..100}?.let{(if(sex==AthleteSex.female)206-0.88*it else 208-0.7*it).roundAway().toDouble()}
    val effectiveMaxHeartRate get()=listOfNotNull(observedMaxHeartRate,predictedMaxHeartRate).maxOrNull()
    val usesObservedMaxHeartRate get()=observedMaxHeartRate?.let{predictedMaxHeartRate==null || it>=predictedMaxHeartRate!!}?:false
    val vo2Factor get()=vo2Max?.takeIf{it.isFinite()&&it in 10.0..90.0}?.let{sqrt(it/45).coerceIn(0.78,1.40)}
    val fitnessScale get()=geometricMean(listOfNotNull(weeklyVolume?.fitnessFactor,experience?.fitnessFactor,vo2Factor))?:1.0
    val ageFactor get()=age?.takeIf{it in 13..100}?.let{(1+(it-30)*0.005).coerceIn(0.95,1.18)}?:1.0
    val prior get()=geometricMean(listOfNotNull(if(age!=null)ageFactor else null,experience?.recoveryFactor,bounceBack?.recoveryFactor))
    val isUsable get()=prior!=null
    val gaps get()=buildList{if(age==null)add("age");if(experience==null)add("experience");if(weeklyVolume==null)add("weeklyVolume");if(bounceBack==null)add("bounceBack")}
    companion object {
        val ageBands=listOf("Under 25" to 21,"25 to 34" to 30,"35 to 44" to 40,"45 to 54" to 50,"55 or over" to 60)
        fun ageBandMidpoint(age: Int)=when {age<25->21;age<35->30;age<45->40;age<55->50;else->60}
    }
}
fun geometricMean(values: List<Double>): Double? = if(values.isEmpty())null else exp(values.sumOf{ln(it)}/values.size)
