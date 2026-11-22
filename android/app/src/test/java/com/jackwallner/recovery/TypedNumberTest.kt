package com.jackwallner.recovery

import org.junit.Assert.*
import org.junit.Test

import com.jackwallner.recovery.model.TypedNumber

/** Port of iOS TypedNumberTests (the max heart rate field in local digits). */
class TypedNumberTest {
    /** What the field used to parse with, kept as the record of the bug: both spellings of 185 read as nothing. */
    @Test fun toDoubleOrNullReadsOnlyAsciiDigits() {
        assertNull("١٨٥".toDoubleOrNull())
        assertNull("۱۸۵".toDoubleOrNull())
    }
    @Test fun aMaxHeartRateTypedInArabicIndicOrPersianDigitsReadsAsItsValue() {
        assertEquals(185.0,TypedNumber.value("١٨٥")!!,0.0)
        assertEquals(185.0,TypedNumber.value("۱۸۵")!!,0.0)
        assertEquals(185.0,TypedNumber.value("१८५")!!,0.0)
    }
    @Test fun asciiInputReadsExactlyAsBefore() {
        for(text in listOf("185","185.5","0","","abc","18a","-5"))assertEquals(text,text.toDoubleOrNull(),TypedNumber.value(text))
    }
    @Test fun anythingThatIsNotAWholeNumberIsRejected() {
        assertNull(TypedNumber.value("١٨x"))
        assertNull(TypedNumber.value("١٨٥١٨٥١"))
    }
}
