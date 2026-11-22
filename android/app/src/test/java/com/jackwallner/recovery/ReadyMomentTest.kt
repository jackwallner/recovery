package com.jackwallner.recovery

import java.time.Instant

import org.junit.Assert.*
import org.junit.Test

import com.jackwallner.recovery.model.*
import com.jackwallner.recovery.ResolverScenarios.estimate
import com.jackwallner.recovery.ResolverScenarios.now
import com.jackwallner.recovery.ResolverScenarios.run
import com.jackwallner.recovery.ResolverScenarios.stackedPair

/** Port of iOS StateMachineRegressionTests B3 and the 6773227 follow-up: which countdown counts as a Ready moment for the review ask. */
class ReadyMomentTest {
    @Test fun theOnboardingImportDoesNotCountAReadyMoment() {
        val old=estimate(run("old",30*24.0))
        assertTrue(old.producesCountdown);assertTrue(old.readyAt<=now)
        assertEquals("old",RecoveryResolver.current(listOf(old),now)?.sessionID)
        // During onboarding setup has not stamped the window yet.
        assertNull(RecoveryResolver.readyMoment(listOf(old),null,now))
        // Once setup finishes, a countdown that ran out before it is still not one the user watched.
        assertNull(RecoveryResolver.readyMoment(listOf(old),now,now.plusSeconds(60)))
    }

    @Test fun aCountdownThatRanOutAfterSetupStillCounts() {
        val setup=now.daysAgo(10);val session=estimate(run("recent",40.0))
        assertTrue(session.readyAt<=now);assertTrue(session.readyAt>setup)
        assertEquals("recent",RecoveryResolver.readyMoment(listOf(session),setup,now)?.sessionID)
        assertNull(RecoveryResolver.readyMoment(listOf(estimate(run("running",1.0))),setup,now))
    }

    @Test fun aHardSessionsReadyMomentCountsEvenWhenAnEasySessionEndedInsideItsCountdown() {
        val setup=now.daysAgo(10)
        val hard=estimate(run("hard",50.0));val walk=estimate(run("walk",20.0,30.0,0.30,WorkoutProfile.easy),hard)
        assertFalse(walk.producesCountdown);assertTrue(hard.readyAt<=now)
        assertEquals("walk",RecoveryResolver.current(listOf(hard,walk),now)?.sessionID)
        assertEquals("hard",RecoveryResolver.readyMoment(listOf(hard,walk),setup,now)?.sessionID)
    }
}
