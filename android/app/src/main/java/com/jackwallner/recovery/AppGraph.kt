package com.jackwallner.recovery

import android.app.Application
import android.content.Context

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

import com.jackwallner.recovery.data.*
import com.jackwallner.recovery.model.ConversionDiagnostics
import com.jackwallner.recovery.model.ReviewTracker

class AppGraph(context: Context) {
    val scope=CoroutineScope(SupervisorJob()+Dispatchers.Main.immediate)
    val values=Preferences(context)
    val settings=Settings(values)
    val review=ReviewTracker(values)
    val diagnostics=ConversionDiagnostics(values)
    val store=StoreService(context,diagnostics)
    val health=HealthService(context,settings,review){store.current.isPro}
    val notifications=ReadyNotifications(context,settings)
    var initialTab=0
    val openToday=MutableStateFlow(0L)
    private var recordedOpen=false
    init {
        settings.onModelChange={scope.launch{health.rescore(true)}}
        health.onPublished={notifications.schedule(it)}
        health.onCleared={notifications.cancel();values.put("lastReadyNotification","")}
    }
    fun recordForegroundOpen(){if(recordedOpen)return;recordedOpen=true;review.recordAppLaunch();diagnostics.recordAppOpen()}
}
class RechargeApplication: Application() {
    lateinit var graph: AppGraph;private set
    override fun onCreate(){super.onCreate();graph=AppGraph(this);BackgroundRefresh.schedule(this)}
}
