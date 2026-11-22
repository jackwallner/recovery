package com.jackwallner.recovery

import java.time.Instant
import java.time.ZoneId

import org.junit.Assert.*
import org.junit.Test

import com.jackwallner.recovery.model.*

/** iOS eec54ef stored the profile at import and had to reclassify on a setting change. Android keeps only the activity code and classifies on every score, so the setting reaches sessions already imported. */
class ReclassificationTest {
    private val now=Instant.parse("2026-06-01T12:00:00Z")
    private val functional=WorkoutRecord("functional",20,now.hoursAfter(-2.0),now.hoursAfter(-1.0),60.0,300.0,null,null,0.2)
    private fun hours(ambiguous: WorkoutProfile)=RecoveryEngine.score(listOf(functional),emptyList(),ModelOptions(ambiguousProfile=ambiguous),now=now,zone=ZoneId.of("UTC")).estimates.single().hours
    @Test fun changingTheFunctionalAndHybridSettingMovesAnAlreadyImportedSession() {
        assertEquals(WorkoutProfile.strength,functional.profile(WorkoutProfile.strength));assertEquals(WorkoutProfile.mixed,functional.profile(WorkoutProfile.mixed))
        assertNotEquals(hours(WorkoutProfile.mixed),hours(WorkoutProfile.strength),0.0)
    }
    @Test fun aPerSessionOverrideStillWinsOverTheSetting() {
        val pinned=functional.copy(intensityOverride=SessionIntensity.light)
        assertEquals(pinned.profile(WorkoutProfile.mixed),pinned.profile(WorkoutProfile.strength))
    }
}
