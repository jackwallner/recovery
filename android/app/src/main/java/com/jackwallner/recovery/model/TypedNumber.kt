package com.jackwallner.recovery.model

/**
 * A number the user typed, read in whatever digits their keyboard produced.
 * `toDoubleOrNull` reads ASCII digits only, so a number pad set to Arabic-Indic or
 * Persian digits typed 185 as nothing and the field rejected it.
 */
object TypedNumber {
    /** ASCII input reads exactly as `toDoubleOrNull` reads it; a whole number in any other decimal digits reads by each digit's value. */
    fun value(text: String): Double? {
        val trimmed=text.trim()
        trimmed.toDoubleOrNull()?.let{return it}
        val points=trimmed.codePoints().toArray()
        if(points.isEmpty()||points.size>6)return null
        var value=0
        for(point in points){
            if(Character.getType(point)!=Character.DECIMAL_DIGIT_NUMBER.toInt())return null
            value=value*10+Character.digit(point,10)
        }
        return value.toDouble()
    }
}
