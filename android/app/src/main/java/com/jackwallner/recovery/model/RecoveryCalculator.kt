package com.jackwallner.recovery.model

import java.time.Instant
import java.util.Locale
import kotlin.math.*

object RecoveryCalculator {
    const val absoluteCountdownFloor=18.0
    const val minimumCountdownHours=6.0
    const val maximumHours=96.0
    const val overlapShare=0.5
    val curve=listOf(0.0 to 0.0,0.60 to 8.0,1.25 to 18.0,2.0 to 36.0,3.50 to 72.0,6.0 to 96.0)
    val referenceHardSessionHours get()=baseHours(1.6)
    fun baseHours(relative: Double): Double {
        val r=max(relative,0.0)
        if(r>=curve.last().first)return curve.last().second
        for((lower,upper) in curve.zipWithNext())if(r<upper.first)return lower.second+(upper.second-lower.second)*(r-lower.first)/(upper.first-lower.first)
        return curve.last().second
    }
    fun category(relative: Double)=when {relative<0.60->LoadCategory.easy;relative<1.25->LoadCategory.typical;relative<2->LoadCategory.hard;else->LoadCategory.unusuallyHard}
    fun carriedHours(session: SessionInput,previousReadyAt: Instant?)=previousReadyAt?.hoursSince(session.endDate)?.coerceAtLeast(0.0)?:0.0
    fun stackedContribution(residual: Double,sessionHours: Double): Double {
        if(!residual.isFinite()||!sessionHours.isFinite()||residual<=0||sessionHours<0)return 0.0
        return max(max(residual,sessionHours)+overlapShare*min(residual,sessionHours)-sessionHours,0.0)
    }
    fun estimate(
        session: SessionInput,baseline: RecoveryBaseline,context: RecoveryContext=RecoveryContext(),calibration: Double=1.0,
        personalization: RecoveryPersonalization=RecoveryPersonalization.standard,standardHours: Double?=null,carriedHours: Double=0.0,
        observed: ObservedWindow?=null,manualHours: Double?=null,now: Instant=Instant.now()
    ): RecoveryEstimate {
        val load=SessionLoadCalculator.profiledLoad(session)
        val relative=if(baseline.typicalLoad>0)load.value/baseline.typicalLoad else 0.0
        val category=category(relative)
        val qualifies=session.profile!=WorkoutProfile.easy&&load.value>=baseline.quietThreshold
        val residual=if(qualifies&&carriedHours.isFinite())max(carriedHours,0.0)else 0.0
        val personal=personalization.factor.finiteOr(1.0).coerceIn(0.72,1.32)
        val unadjusted=baseHours(relative)*calibration.finiteOr(1.0).coerceIn(0.80,1.25)*personal
        fun countdownEnd(cutoff: Instant): Instant {
            val adjusted=unadjusted*(1+contextAdjustment(context,cutoff))
            val hours=(adjusted*session.profile.windowMultiplier).coerceIn(6.0,96.0)
            return session.endDate.hoursAfter(min(hours+stackedContribution(residual,hours),96.0))
        }
        var cutoff=Instant.MIN
        var end=countdownEnd(cutoff)
        for(night in context.followingNights){if(night.date>=end)break;cutoff=night.date.plusSeconds(1);end=countdownEnd(cutoff)}
        val adjustment=contextAdjustment(context,cutoff)
        val scaled=unadjusted*(1+adjustment)
        var cost=(scaled*session.profile.costMultiplier).coerceIn(0.0,96.0)
        var hours=if(qualifies)(scaled*session.profile.windowMultiplier).coerceIn(6.0,96.0)else 0.0
        if(qualifies&&personalization.tier==RecoveryTier.personalized&&manualHours!=null&&manualHours.isFinite()&&manualHours>0){hours=manualHours.coerceIn(6.0,96.0);cost=hours}
        val carried=if(qualifies)min(stackedContribution(residual,hours),max(96-hours,0.0))else 0.0
        val total=if(qualifies)min(hours+carried,96.0)else 0.0
        val factor=if(qualifies)personalization.factor else 1.0
        return RecoveryEstimate(session.id,session.profile,session.activityLabel,now,session.endDate,session.endDate.hoursAfter(total),hours,total*0.85,min(total*1.15,96.0),load,relative,category,
            confidence(load,baseline,context,session.profile,personalization.tier),
            reasons(session,load,category,context,adjustment,qualifies,baseline,personalization,observed,if(qualifies&&personalization.tier==RecoveryTier.personalized)manualHours else null,cutoff),
            tier=personalization.tier,personalFactor=factor,standardHours=standardHours?:hours/factor,carriedHours=carried,recoveryCostHours=cost)
    }
    fun includedNights(context: RecoveryContext,before: Instant?)=if(before==null)context.followingNights else context.followingNights.filter{it.date<before}
    fun contextAdjustment(context: RecoveryContext,before: Instant?=null): Double {
        val readings=buildList {
            if(context.nightBefore.hasSignal)add(nightAdjustment(context.nightBefore,context) to 1.0)
            includedNights(context,before).forEach{add(nightAdjustment(it,context) to 2.0)}
        }
        val weight=readings.sumOf{it.second}
        return if(weight<=0)0.0 else (readings.sumOf{it.first*it.second}/weight).coerceIn(-0.15,0.20)
    }
    fun nightAdjustment(night: Night,context: RecoveryContext): Double {
        var delta=0.0
        night.sleepHours?.let{delta+=when {it<5->0.12;it<6->0.08;it>=7.5->-0.05;else->0.0}}
        val hrv=night.heartRateVariability;val hrvBase=context.heartRateVariabilityBaseline
        if(hrv!=null&&hrvBase!=null&&hrvBase>0)delta+=when {hrv/hrvBase<0.85->0.08;hrv/hrvBase>1.15->-0.05;else->0.0}
        val resting=night.restingHeartRate;val restingBase=context.restingHeartRateBaseline
        if(resting!=null&&restingBase!=null&&restingBase>0)delta+=when {resting>=restingBase+5->0.08;resting<=restingBase-2->-0.04;else->0.0}
        val rate=night.respiratoryRate;val rateBase=context.respiratoryRateBaseline
        if(rate!=null&&rateBase!=null&&rateBase>0)delta+=when {rate>=rateBase+1.5->0.04;rate<=rateBase-1->-0.02;else->0.0}
        return delta.coerceIn(-0.15,0.20)
    }
    fun confidence(load: SessionLoad,baseline: RecoveryBaseline,context: RecoveryContext,profile: WorkoutProfile,tier: RecoveryTier=RecoveryTier.personalized): RecoveryConfidence {
        if(tier==RecoveryTier.standard)return when(load.source){LoadSource.duration->RecoveryConfidence.low;LoadSource.energy->if(profile==WorkoutProfile.easy)RecoveryConfidence.medium else RecoveryConfidence.low;LoadSource.reportedEffort->RecoveryConfidence.medium;LoadSource.heartRate->if(load.heartRateCoverage<0.75)RecoveryConfidence.low else RecoveryConfidence.medium}
        if(!baseline.hasEstablishedBaseline)return RecoveryConfidence.buildingBaseline
        return when(load.source){LoadSource.duration->RecoveryConfidence.low;LoadSource.energy->if(profile==WorkoutProfile.easy)RecoveryConfidence.medium else RecoveryConfidence.low;LoadSource.reportedEffort->if(context.isEmpty)RecoveryConfidence.medium else RecoveryConfidence.high;LoadSource.heartRate->if(load.heartRateCoverage<0.75||context.isEmpty)RecoveryConfidence.medium else RecoveryConfidence.high}
    }
    fun reasons(session: SessionInput,load: SessionLoad,category: LoadCategory,context: RecoveryContext,adjustment: Double,qualifies: Boolean,baseline: RecoveryBaseline,personalization: RecoveryPersonalization,observed: ObservedWindow?,manualHours: Double?,nightsBefore: Instant?): List<String> {
        val minutes=session.durationMinutes.roundAway()
        if(session.profile==WorkoutProfile.easy)return listOf(if(session.intensityOverride==SessionIntensity.light)"You marked this session light, so it counts as active recovery." else minutes.toString()+"-minute "+session.activityLabel+" counts as active recovery.","Light enough to leave the countdown where it is.")
        val tier=personalization.tier;val label=category.label(tier)
        if(!qualifies)return listOf(label.lowercase()+": a "+minutes+"-minute "+session.activityLabel+" "+(if(tier==RecoveryTier.standard)"below the level that starts a countdown"else"below your usual session load")+".","Counted toward your training load, but no countdown started.")
        val reasons=mutableListOf(label+": "+minutes+"-minute "+session.activityLabel+".")
        reasons.add(session.intensityOverride?.let{"You marked this session "+it.label.lowercase()+", so that is what it was scored as."}?:"Load estimated from "+load.source.label+".")
        if(manualHours!=null&&manualHours.isFinite()&&manualHours>0){reasons.add("You pinned "+CountdownFormat.hours(manualHours)+" to this intensity, so the model's own figure is not used here.");return reasons}
        if(tier==RecoveryTier.standard)reasons.add("Standard estimate at your training level, scored against your heart-rate range.")
        else {
            if(!baseline.hasEstablishedBaseline)reasons.add("Still building your baseline from "+baseline.dayCount+" recent training "+(if(baseline.dayCount==1)"day"else"days")+".")
            val percent=((personalization.factor-1)*100).roundAway()
            if(percent<=-3)reasons.add("Your own 30-day pattern shortens this by about "+abs(percent)+"%.")
            if(percent>=3)reasons.add("Your own 30-day pattern lengthens this by about "+percent+"%.")
        }
        observed?.let {
            val times=it.sampleCount.toString()+" "+if(it.sampleCount==1)"time"else"times"
            reasons.add(if(it.isBandSpecific)"After a "+it.band.label.lowercase()+" session you have usually gone again after about "+CountdownFormat.hours(it.hours)+" ("+times+")."else"You have usually gone again after about "+CountdownFormat.hours(it.hours)+" between sessions ("+times+").")
        }
        val nights=includedNights(context,nightsBefore)
        val prefix=if(nights.isEmpty())null else if(nights.size==1)"since the session"else"over the "+nights.size+" nights since"
        if(adjustment>0.02||adjustment< -0.02)reasons.add(contextSummary(nights.lastOrNull()?:context.nightBefore,context,adjustment>0,prefix))
        return reasons.filter{it.isNotEmpty()}
    }
    fun contextSummary(night: Night,context: RecoveryContext,lengthened: Boolean,prefix: String?): String {
        val signals=mutableListOf<String>()
        night.sleepHours?.let{if(lengthened&&it<6)signals.add("short sleep ("+String.format(Locale.US,"%.1f",it)+"h)");if(!lengthened&&it>=7.5)signals.add("good sleep ("+String.format(Locale.US,"%.1f",it)+"h)")}
        val hrv=night.heartRateVariability;val hrvBase=context.heartRateVariabilityBaseline
        if(hrv!=null&&hrvBase!=null&&hrvBase>0){if(lengthened&&hrv/hrvBase<0.85)signals.add("HRV below your usual range");if(!lengthened&&hrv/hrvBase>1.15)signals.add("HRV above your usual range")}
        val resting=night.restingHeartRate;val restingBase=context.restingHeartRateBaseline
        if(resting!=null&&restingBase!=null&&restingBase>0){if(lengthened&&resting>=restingBase+5)signals.add("resting heart rate up "+(resting-restingBase).roundAway()+" bpm");if(!lengthened&&resting<=restingBase-2)signals.add("resting heart rate below your usual range")}
        val rate=night.respiratoryRate;val rateBase=context.respiratoryRateBaseline
        if(rate!=null&&rateBase!=null&&rateBase>0){if(lengthened&&rate>=rateBase+1.5)signals.add("breathing rate up overnight");if(!lengthened&&rate<=rateBase-1)signals.add("breathing rate below your usual range")}
        val lead=(if(lengthened)"Extended slightly"else"Shortened slightly")+(prefix?.let{" "+it}?:"")
        if(signals.isEmpty())return if(prefix==null)""else lead+": overnight readings against your usual range."
        val joined=when(signals.size){1->signals[0];2->signals.joinToString(" and ");else->signals.dropLast(1).joinToString(", ")+", and "+signals.last()}
        return lead+": "+joined+"."
    }
}
