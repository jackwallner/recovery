package com.jackwallner.recovery.data

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.time.Instant
import java.util.concurrent.TimeUnit

import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

import com.jackwallner.recovery.MainActivity
import com.jackwallner.recovery.R
import com.jackwallner.recovery.RechargeApplication
import com.jackwallner.recovery.model.RecoveryResolver

class ReadyNotifications(private val context: Context,private val settings: Settings) {
    private val alarm=context.getSystemService(AlarmManager::class.java)
    private fun pending()=PendingIntent.getBroadcast(context,4101,Intent(context,ReadyReceiver::class.java).setAction("com.jackwallner.recovery.COUNTDOWN_ENDED"),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun allowed()=Build.VERSION.SDK_INT<33||ContextCompat.checkSelfPermission(context,Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED
    fun schedule(state: HealthState) {
        val estimate=RecoveryResolver.active(state.scored.estimates)
        if(!settings.notifyOnReady||!allowed()){cancel();return}
        if(estimate==null){alarm.cancel(pending());return}
        context.getSystemService(NotificationManager::class.java).cancel(4101)
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,estimate.readyAt.toEpochMilli(),pending())
    }
    fun cancel(){alarm.cancel(pending());context.getSystemService(NotificationManager::class.java).cancel(4101)}
    fun deliver(state: HealthState) {
        if(!settings.notifyOnReady||!allowed())return
        val estimate=RecoveryResolver.current(state.scored.estimates)?:return
        val now=Instant.now()
        if(!estimate.producesCountdown||estimate.readyAt>now||estimate.readyAt<now.minusSeconds(86400))return
        val token=estimate.sessionID+":"+estimate.readyAt.toEpochMilli()
        if(settings.values.string("lastReadyNotification")==token)return
        val manager=context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("recharge-ready","Countdown complete",NotificationManager.IMPORTANCE_DEFAULT))
        val open=Intent(context,MainActivity::class.java).putExtra("route","today").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val action=PendingIntent.getActivity(context,4101,open,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify(4101,NotificationCompat.Builder(context,"recharge-ready").setSmallIcon(R.drawable.ic_stat).setContentTitle("Ready").setContentText("Your countdown from that "+estimate.activityLabel+" has finished.").setContentIntent(action).setAutoCancel(true).build())
        settings.values.put("lastReadyNotification",token)
    }
}
class ReadyReceiver: BroadcastReceiver() {
    override fun onReceive(context: Context,intent: Intent?) {
        val pending=goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val graph=(context.applicationContext as RechargeApplication).graph
                graph.health.refresh(background=true,cachedOnly=true)
                val state=graph.health.state.value
                if(state.granted.containsAll(graph.health.corePermissions))graph.notifications.deliver(state)
            } finally {pending.finish()}
        }
    }
}
class RefreshWorker(context: Context,parameters: WorkerParameters): CoroutineWorker(context,parameters) {
    override suspend fun doWork(): Result {
        val graph=(applicationContext as RechargeApplication).graph
        withContext(Dispatchers.Main){graph.store.start()}
        graph.health.refresh(background=true)
        return if(graph.health.state.value.lastImportFailed)Result.retry()else Result.success()
    }
}
object BackgroundRefresh {
    fun schedule(context: Context){WorkManager.getInstance(context).enqueueUniquePeriodicWork("recharge-health-refresh",ExistingPeriodicWorkPolicy.KEEP,PeriodicWorkRequestBuilder<RefreshWorker>(6,TimeUnit.HOURS).build())}
}
