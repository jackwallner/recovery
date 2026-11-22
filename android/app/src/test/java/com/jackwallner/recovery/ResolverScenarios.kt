package com.jackwallner.recovery

import java.time.Instant

import com.jackwallner.recovery.model.*

/** Sessions and estimates for the iOS StateMachineRegressionTests ports, built the way the iOS fixtures build them. */
internal object ResolverScenarios {
    val now: Instant=Instant.parse("2026-06-01T12:00:00Z")
    fun run(id: String,endingHoursAgo: Double,minutes: Double=60.0,reserve: Double=0.78,profile: WorkoutProfile=WorkoutProfile.endurance): SessionInput {
        val resting=55.0;val max=185.0;val end=now.hoursAfter(-endingHoursAgo)
        return SessionInput(id,profile,end.hoursAfter(-minutes/60),end,minutes,resting+reserve*(max-resting),resting,max,1.0,activityLabel="run")
    }
    fun estimate(session: SessionInput,after: RecoveryEstimate?=null)=RecoveryCalculator.estimate(session,RecoveryBaseline.standard(WorkoutProfile.endurance),carriedHours=RecoveryCalculator.carriedHours(session,after?.readyAt),now=now)
    /** B stacks on A; A's own window ended an hour ago and B's is still running. */
    fun stackedPair(): Pair<RecoveryEstimate,RecoveryEstimate> {
        val firstHours=estimate(run("A",0.0)).hours
        val first=estimate(run("A",firstHours+1))
        return first to estimate(run("B",3.0),first)
    }
}
