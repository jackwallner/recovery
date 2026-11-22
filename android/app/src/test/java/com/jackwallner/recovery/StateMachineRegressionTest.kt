package com.jackwallner.recovery

import java.time.Instant

import org.junit.Assert.*
import org.junit.Test

import com.jackwallner.recovery.model.*
import com.jackwallner.recovery.ResolverScenarios.estimate
import com.jackwallner.recovery.ResolverScenarios.now
import com.jackwallner.recovery.ResolverScenarios.run
import com.jackwallner.recovery.ResolverScenarios.stackedPair

/** Port of iOS StateMachineRegressionTests B1: the readiness question is asked only about a countdown the user saw end. */
class StateMachineRegressionTest {
    @Test fun readinessQuestionIsNotAskedWhileTheShownCountdownIsStillRunning() {
        val (first,second)=stackedPair();val estimates=listOf(first,second)
        assertTrue(first.readyAt<=now);assertTrue(second.carriedHours>0);assertTrue(second.readyAt.hoursSince(now)>2)
        assertEquals("B",RecoveryResolver.active(estimates,now)?.sessionID)
        assertNull(RecoveryResolver.awaitingFeedback(estimates,emptySet(),null,now))
    }

    @Test fun answeringTheStackedSessionDoesNotRaiseTheQuestionAboutTheOneUnderIt() {
        val hard=estimate(run("A",60.0));val moderate=estimate(run("B",46.0,45.0,0.62),hard);val estimates=listOf(hard,moderate)
        assertTrue(moderate.carriedHours>0);assertTrue(moderate.readyAt>hard.readyAt)
        assertNull(RecoveryResolver.awaitingFeedback(estimates,emptySet(),null,hard.readyAt.plusSeconds(60)))
        val afterB=moderate.readyAt.plusSeconds(60)
        assertTrue(afterB.hoursSince(hard.readyAt)<48)
        assertEquals("B",RecoveryResolver.awaitingFeedback(estimates,emptySet(),null,afterB)?.sessionID)
        assertNull(RecoveryResolver.awaitingFeedback(estimates,setOf("B"),null,afterB))
    }

    @Test fun aCountdownThatRanOutBeforeTheNextSessionIsStillAskedAbout() {
        val first=estimate(run("A",60.0))
        val later=estimate(run("B",now.hoursSince(first.readyAt)-1),first)
        assertEquals(0.0,later.carriedHours,0.0)
        val afterLater=later.readyAt.plusSeconds(60)
        assertEquals("B",RecoveryResolver.awaitingFeedback(listOf(first,later),emptySet(),null,afterLater)?.sessionID)
        assertEquals("A",RecoveryResolver.awaitingFeedback(listOf(first,later),setOf("B"),null,afterLater)?.sessionID)
        assertEquals("A",RecoveryResolver.awaitingFeedback(listOf(first),emptySet(),null,first.readyAt)?.sessionID)
    }
}
