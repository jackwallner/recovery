package com.jackwallner.recovery

import java.security.MessageDigest

import org.junit.Assert.*
import org.junit.Test

import com.jackwallner.recovery.model.ReviewAccess

class ReviewAccessTest {
    private class ReviewerValues : com.jackwallner.recovery.model.Values {
        private val data = mutableMapOf<String, String>()
        override fun string(key: String) = data[key]
        override fun put(key: String, value: String) { data[key] = value }
        override fun entries() = data.toMap()
    }

    private val fixture = "local-review-fixture"
    private val digest = MessageDigest.getInstance("SHA-256").digest(fixture.toByteArray()).joinToString("") { "%02x".format(it) }

    @Test fun unconfiguredAccessCannotUnlock() {
        assertFalse(ReviewAccess(ReviewerValues(), "").activate(fixture))
        assertFalse(ReviewAccess(ReviewerValues(), "invalid").isGranted)
    }

    @Test fun wrongOrBlankCodeDoesNotGrantAccess() {
        val access = ReviewAccess(ReviewerValues(), digest)
        assertFalse(access.activate("wrong"))
        assertFalse(access.activate(" "))
        assertFalse(access.isGranted)
    }

    @Test fun validCodePersistsOnlyDigestAcrossRecreation() {
        val values = ReviewerValues()
        assertTrue(ReviewAccess(values, digest).activate(" $fixture "))
        assertTrue(ReviewAccess(values, digest).isGranted)
        assertEquals(mapOf("reviewAccessDigest" to digest), values.entries())
    }

    @Test fun rotatingDigestInvalidatesExistingAccess() {
        val values = ReviewerValues()
        assertTrue(ReviewAccess(values, digest).activate(fixture))
        assertFalse(ReviewAccess(values, "0".repeat(64)).isGranted)
    }
}
