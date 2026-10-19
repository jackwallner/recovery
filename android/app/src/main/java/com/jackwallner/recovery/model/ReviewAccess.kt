package com.jackwallner.recovery.model

import java.security.MessageDigest

class ReviewAccess(private val values: Values, private val expectedDigest: String) {
    private val configured get() = expectedDigest.matches(Regex("[a-f0-9]{64}"))
    val isGranted get() = configured && values.string("reviewAccessDigest") == expectedDigest

    fun activate(code: String): Boolean {
        if (!configured || code.isBlank()) return false
        val digest = MessageDigest.getInstance("SHA-256").digest(code.trim().toByteArray())
            .joinToString("") { "%02x".format(it) }
        if (!MessageDigest.isEqual(digest.toByteArray(), expectedDigest.toByteArray())) return false
        values.put("reviewAccessDigest", digest)
        return true
    }
}
