package com.jackwallner.recovery.model

class ReviewTracker(private val values: Values,private val clock: ()->Long=System::currentTimeMillis) {
    var isAutomationRun=false
    private fun set(key: String,value: Any)=values.put("reviewPrompt."+key,value.toString())
    private fun string(key: String)=values.string("reviewPrompt."+key)
    var appLaunchCount: Int get()=values.int("reviewPrompt.appLaunchCount");set(value)=set("appLaunchCount",value.coerceAtLeast(0))
    var readyMomentCount: Int get()=values.int("reviewPrompt.readyMomentCount");set(value)=set("readyMomentCount",value.coerceAtLeast(0))
    var hasPendingReadyMoment: Boolean get()=values.bool("reviewPrompt.pendingReadyMoment");set(value)=set("pendingReadyMoment",value)
    var hasSeenEstimate: Boolean get()=values.bool("reviewPrompt.hasSeenEstimate");set(value)=set("hasSeenEstimate",value)
    val outcome get()=string("outcome").takeUnless{it.isNullOrBlank()}
    fun recordAppLaunch(){if(string("firstAppOpenDate")==null)set("firstAppOpenDate",clock());appLaunchCount++}
    fun recordReadyMoment(id: String) {
        val seen=string("seenReadySessions").orEmpty().split('|').filter{it.isNotEmpty()}.toMutableSet()
        if(!seen.add(id))return
        set("seenReadySessions",seen.takeLastSafe(200).joinToString("|"));readyMomentCount++;hasPendingReadyMoment=true
    }
    fun passivePromptAllowed(now: Long=clock()): Boolean {
        if(outcome!=null)return false
        val last=string("lastShownDate")?.toLongOrNull()?:return true
        val days=if(values.bool("reviewPrompt.softDefer"))30 else 120
        return now-last>=days*86_400_000L
    }
    fun eligibilityTrigger(hasCompletedSetup: Boolean,now: Long=clock()): String? {
        if(isAutomationRun||!hasCompletedSetup||!passivePromptAllowed(now))return null
        val first=string("firstAppOpenDate")?.toLongOrNull()?:return null
        val days=((now-first)/86_400_000).toInt()
        return when {readyMomentCount>=2&&appLaunchCount>=3&&days>=3->"readyMoment";hasSeenEstimate&&appLaunchCount>=6&&days>=7->"engagedUse";else->null}
    }
    fun shouldRequest(hasCompletedSetup: Boolean): Boolean {
        val trigger=eligibilityTrigger(hasCompletedSetup)
        return if(hasPendingReadyMoment)trigger=="readyMoment"else trigger=="engagedUse"
    }
    fun markShown(){set("lastShownDate",clock());set("softDefer",false);hasPendingReadyMoment=false}
    fun markSoftDeferred(){set("lastShownDate",clock());set("softDefer",true);hasPendingReadyMoment=false}
    fun markOpenedWriteReview(){set("outcome","openedWriteReview");markShown()}
    fun markFeedbackSubmitted(){set("outcome","submittedFeedback");markShown()}
    private fun Set<String>.takeLastSafe(count: Int)=toList().takeLast(count)
}
