package com.jackwallner.recovery

import java.time.Instant

import org.junit.Assert.*
import org.junit.Test

import com.jackwallner.recovery.data.Settings
import com.jackwallner.recovery.model.Values

/** Ports of iOS 6ab56eb (deleted local data stays deleted) and 0c6d015 (reconnecting reopens the readiness window). */
class LocalDataDeletionTest {
    private class MemoryValues : Values {
        private val data=mutableMapOf<String,String>()
        override fun string(key: String)=data[key]
        override fun put(key: String,value: String){data[key]=value}
        override fun entries():Map<String,String> = data.toMap()
    }
    private val setup=Instant.parse("2026-06-01T12:00:00Z")
    private val later=setup.plusSeconds(10*86400)

    @Test fun healthReadsAreAllowedUntilTheUserDeletesLocalData() { assertTrue(Settings(MemoryValues()).mayReadHealth) }
    @Test fun deletedDataStaysDeletedAcrossRestarts() {
        val values=MemoryValues();val a=Settings(values);a.completeSetup(setup)
        a.markLocalDataDeleted()
        assertFalse(a.mayReadHealth);assertFalse(Settings(values).mayReadHealth)
    }
    @Test fun connectingAgainAllowsReadsAgain() {
        val values=MemoryValues();val a=Settings(values);a.completeSetup(setup);a.markLocalDataDeleted();a.reconnectHealth(later)
        assertTrue(a.mayReadHealth);assertTrue(Settings(values).mayReadHealth)
    }
    @Test fun deletingClosesTheReadinessWindowAndReconnectingReopensItFromNow() {
        val values=MemoryValues();val a=Settings(values);a.completeSetup(setup)
        assertEquals(setup,a.feedbackEligibleFrom)
        a.markLocalDataDeleted();assertNull(Settings(values).feedbackEligibleFrom)
        a.reconnectHealth(later);assertEquals(later,Settings(values).feedbackEligibleFrom)
    }
    @Test fun reconnectingBeforeSetupLeavesTheWindowToSetup() {
        val a=Settings(MemoryValues());a.reconnectHealth(later);assertNull(a.feedbackEligibleFrom)
    }
    @Test fun anOrdinaryReconnectKeepsTheWindowThatIsAlreadyOpen() {
        val a=Settings(MemoryValues());a.completeSetup(setup);a.reconnectHealth(later);assertEquals(setup,a.feedbackEligibleFrom)
    }
}
