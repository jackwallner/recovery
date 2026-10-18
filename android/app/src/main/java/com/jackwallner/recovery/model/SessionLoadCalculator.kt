package com.jackwallner.recovery.model

import kotlin.math.*

object SessionLoadCalculator {
    const val referenceEnergyAtFullReserve=15.6
    const val referenceBodyMassKilograms=75.0
    const val defaultMaxHeartRate=185.0
    const val defaultRestingHeartRate=60.0
    const val minimumHeartRateCoverage=0.5
    fun referenceEnergy(mass: Double?)=if(mass!=null&&mass.isFinite()&&mass>0)referenceEnergyAtFullReserve*(mass/referenceBodyMassKilograms).coerceIn(0.6,1.7) else referenceEnergyAtFullReserve
    fun load(session: SessionInput)=heartRateLoad(session)?:reportedEffortLoad(session)?:energyLoad(session)?:durationLoad(session)
    fun strengthLoad(session: SessionInput)=listOfNotNull(heartRateLoad(session),reportedEffortLoad(session),energyLoad(session),durationLoad(session)).maxBy{it.value}
    fun mixedLoad(session: SessionInput): SessionLoad {
        val hr=heartRateLoad(session);val effort=reportedEffortLoad(session)
        return if(hr!=null&&effort!=null)if(hr.value>=effort.value)hr else effort else load(session)
    }
    fun profiledLoad(session: SessionInput): SessionLoad {
        session.intensityOverride?.let{return SessionLoad(costedMinutes(session,it.assumedEffort/10)*it.assumedEffort*0.30,LoadSource.reportedEffort,session.heartRateCoverage)}
        return when(session.profile){WorkoutProfile.strength->strengthLoad(session);WorkoutProfile.mixed->mixedLoad(session);else->load(session)}
    }
    fun intensityFraction(session: SessionInput): Double? {
        val average=session.averageHeartRate?:return null
        if(session.heartRateCoverage<minimumHeartRateCoverage || !average.isFinite() || average<=0)return null
        val resting=session.restingHeartRate?:defaultRestingHeartRate;val maximum=session.maxHeartRate?:defaultMaxHeartRate
        if(!resting.isFinite() || !maximum.isFinite() || maximum<=resting)return null
        return ((average-resting)/(maximum-resting)).coerceIn(0.0,1.0)
    }
    fun trimpPerMinute(reserve: Double): Double {
        val r=reserve.finiteOr(0.0).coerceIn(0.0,1.0)
        return r*0.64*exp(1.92*r)*(1+8*max(r-0.85,0.0))
    }
    fun continuationWeight(reserve: Double)=((reserve.finiteOr(0.0)-0.35)/0.45).coerceIn(0.4,1.0)
    fun effectiveMinutes(minutes: Double,reserve: Double)=if(minutes>60)60+(minutes-60)*continuationWeight(reserve)else max(minutes,0.0)
    fun costedMinutes(session: SessionInput,reserve: Double)=if(session.profile==WorkoutProfile.strength)session.durationMinutes else effectiveMinutes(session.durationMinutes,reserve)
    fun heartRateLoad(session: SessionInput): SessionLoad? {
        val reserve=intensityFraction(session)?:return null
        if(session.durationMinutes<=0)return null
        return SessionLoad(distributionLoad(session)?:costedMinutes(session,reserve)*trimpPerMinute(reserve),LoadSource.heartRate,session.heartRateCoverage)
    }
    fun distributionLoad(session: SessionInput): Double? {
        val distribution=session.heartRateDistribution?:return null
        if(distribution.totalSeconds<=0 || session.durationMinutes<=0)return null
        val resting=session.restingHeartRate?:defaultRestingHeartRate;val maximum=session.maxHeartRate?:defaultMaxHeartRate
        if(!resting.isFinite() || !maximum.isFinite() || maximum<=resting)return null
        val covered=distribution.buckets.sumOf{(bpm,seconds)->val reserve=((bpm-resting)/(maximum-resting)).coerceIn(0.0,1.0);seconds/60*trimpPerMinute(reserve)*costedMinutes(session,reserve)/session.durationMinutes}
        return covered*(session.durationMinutes/(distribution.totalSeconds/60)).coerceIn(0.5,2.0)
    }
    fun reportedEffortLoad(session: SessionInput): SessionLoad? {
        val effort=session.reportedEffort?:return null
        if(session.durationMinutes<=0)return null
        return SessionLoad(costedMinutes(session,effort/10)*effort*0.30,LoadSource.reportedEffort,session.heartRateCoverage)
    }
    fun energyLoad(session: SessionInput): SessionLoad? {
        val energy=session.activeEnergyKilocalories?:return null
        if(!energy.isFinite() || energy<=0 || session.durationMinutes<=0)return null
        val reserve=(energy/session.durationMinutes/referenceEnergy(session.bodyMassKilograms)).coerceIn(0.0,1.0)
        return SessionLoad(costedMinutes(session,reserve)*trimpPerMinute(reserve),LoadSource.energy,session.heartRateCoverage)
    }
    fun durationLoad(session: SessionInput)=SessionLoad(costedMinutes(session,session.profile.assumedEffort/10)*session.profile.assumedEffort*0.30,LoadSource.duration,session.heartRateCoverage)
}
