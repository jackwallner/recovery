package com.jackwallner.recovery.model

import java.time.Instant

interface Values {
    fun string(key: String): String?
    fun put(key: String, value: String)
    fun entries(): Map<String, String>
    fun int(key: String) = string(key)?.toIntOrNull() ?: 0
    fun long(key: String) = string(key)?.toLongOrNull()
    fun bool(key: String) = string(key) == "true"
}
class ConversionDiagnostics(private val values: Values, private val clock: () -> Long = System::currentTimeMillis) {
    private fun get(key: String) = values.string("conv.$key")
    private fun set(key: String, value: Any) = values.put("conv.$key", value.toString())
    private fun count(key: String) = get(key)?.toIntOrNull() ?: 0
    private fun age(stamp: String?) = maxOf(0, ((clock() - (stamp?.toLongOrNull() ?: clock())) / 86_400_000).toInt())
    fun recordAppOpen() {
        if (get("installedAt") == null) set("installedAt", clock())
        set("appOpens", count("appOpens") + 1)
    }
    fun recordPitchView(impressionId: String) {
        val surface = impressionId.removePrefix("recharge_")
        set("pitchViews.total", count("pitchViews.total") + 1)
        set("pitchViews.$surface", count("pitchViews.$surface") + 1)
        set("pitchLastSurface", surface)
        if (get("pitchFirstSeen") != null) return
        set("pitchFirstSeen", clock()); set("opensBeforeFirstPitch", count("appOpens"))
        if (get("installedAt") != null) set("daysToFirstPitch", age(get("installedAt")))
    }
    fun recordConversion(plan: String, startedTrial: Boolean, offeringId: String? = null) {
        if (get("convertedOn") != null) return
        set("convertedOn", get("pitchLastSurface") ?: "unknown"); set("convertedAt", clock())
        set("viewsAtConvert", count("pitchViews.total")); set("convertedPlan", plan); set("convertedWithTrial", startedTrial)
        offeringId?.let { set("convertedOffering", it) }
        if (get("pitchFirstSeen") != null) set("daysToConvert", age(get("pitchFirstSeen")))
    }
    val subscriberAttributes: Map<String, String> get() {
        if (count("pitchViews.total") == 0) return emptyMap()
        val attributes = mutableMapOf("pitch_views_total" to count("pitchViews.total").toString())
        values.entries().forEach { (key,value) ->
            if (key.startsWith("conv.pitchViews.") && key != "conv.pitchViews.total" && (value.toIntOrNull() ?: 0) > 0) attributes[("pitch_views_" + key.removePrefix("conv.pitchViews.")).take(40)] = value
        }
        get("pitchLastSurface")?.let { attributes["pitch_last"] = it }
        get("pitchFirstSeen")?.let { attributes["pitch_first_seen"] = Instant.ofEpochMilli(it.toLong()).toString(); attributes["days_since_first_pitch"] = age(it).toString() }
        get("daysToFirstPitch")?.let { attributes["days_since_install"] = it }
        get("opensBeforeFirstPitch")?.let { attributes["opens_before_first_pitch"] = it }
        if (get("convertedOn") != null) {
            attributes["converted_surface"] = get("convertedOn")!!
            attributes["converted_at"] = Instant.ofEpochMilli(get("convertedAt")!!.toLong()).toString()
            attributes["pitch_views_at_convert"] = count("viewsAtConvert").toString()
            attributes["days_to_convert"] = count("daysToConvert").toString()
            attributes["converted_plan"] = get("convertedPlan") ?: "unknown"
            attributes["converted_with_trial"] = get("convertedWithTrial") ?: "false"
            get("convertedOffering")?.let { attributes["converted_offering"] = it }
        }
        return attributes
    }
}
class ReviewSheetGuard {
    private val sheets = mutableSetOf<String>()
    val noSheetIsPresented get() = sheets.isEmpty()
    fun setSheet(id: String, isPresented: Boolean) { if (isPresented) sheets.add(id) else sheets.remove(id) }
}
object ConversionCopy {
    const val ctaLabel = "Continue with Recharge+"
    fun trialLabel(period: String): String? {
        val match=Regex("P([0-9]+)([DWMY])").matchEntire(period) ?: return null
        val count=match.groupValues[1].toIntOrNull()?.takeIf{it>0} ?: return null
        val unit=when(match.groupValues[2]){"D"->"day";"W"->"week";"M"->"month";else->"year"}
        return "$count-$unit free trial"
    }
    fun billedAmount(priceLabel: String) = priceLabel.replace(" / ", " per ")
    fun billedNote(trialLabel: String?, eligibleForTrial: Boolean) = if (eligibleForTrial && !trialLabel.isNullOrBlank()) "${trialLabel.lowercase()} included · Cancel anytime" else "Billed automatically · Cancel anytime"
    fun disclosure(trialLabel: String?, priceLabel: String, eligibleForTrial: Boolean): String {
        val lead = if (eligibleForTrial && !trialLabel.isNullOrBlank()) "$priceLabel after the ${trialLabel.lowercase()}." else "$priceLabel."
        return "$lead Auto-renews unless cancelled. Manage or cancel in Google Play > Payments & subscriptions."
    }
    fun purchaseCancelledMessage(eligibleForTrial: Boolean) = if (eligibleForTrial) "Trial wasn't started. Tap again to continue." else "Purchase wasn't completed. Tap again to continue."
    fun purchaseFailedMessage(eligibleForTrial: Boolean) = if (eligibleForTrial) "Couldn't start your trial. Please try again." else "Couldn't complete the purchase. Please try again."
}
