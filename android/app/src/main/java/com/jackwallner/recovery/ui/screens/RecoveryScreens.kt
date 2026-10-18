package com.jackwallner.recovery.ui.screens

import android.os.Build
import java.time.Instant
import java.time.ZoneId

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

import com.jackwallner.recovery.AppGraph
import com.jackwallner.recovery.data.HealthState
import com.jackwallner.recovery.data.Legal
import com.jackwallner.recovery.model.*
import com.jackwallner.recovery.ui.theme.*

const val DISCLAIMER="Recharge gives a cardiovascular training estimate from your Health Connect data. It is not medical advice and does not diagnose, treat, or prevent any condition. Talk with a qualified health professional before making medical decisions."
const val COMPARISON_CAPTION="Standard is the model at your training level. Recharge+ scores this session against your own baseline, sleep, and heart rate."

@Composable fun ComparisonCard(preview: PersonalizedPreview,isPro: Boolean,onClick: (() ->Unit)?=null) {
    CardBlock(onClick=onClick) {
        Text(if(isPro)"Your recharge time"else"Your own recharge time",fontWeight=FontWeight.SemiBold)
        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(20.dp)) {
            Metric("STANDARD",CountdownFormat.hours(preview.standardHours),MaterialTheme.colorScheme.onSurfaceVariant)
            Icon(Icons.Default.ArrowForward,null,tint=MaterialTheme.colorScheme.onSurfaceVariant)
            Column {
                if(isPro)Text(CountdownFormat.hours(preview.personalizedHours),fontSize=30.sp,fontWeight=FontWeight.Bold,color=Palette.pro)
                else Row(verticalAlignment=Alignment.CenterVertically) {
                    if(Build.VERSION.SDK_INT>=31)Text(CountdownFormat.hours(preview.personalizedHours),Modifier.blur(8.dp).clearAndSetSemantics{contentDescription="Hidden until you upgrade"},fontSize=30.sp,fontWeight=FontWeight.Bold,color=Palette.pro)
                    else Text("Hidden",fontSize=22.sp,color=Palette.pro)
                    Icon(Icons.Default.Lock,null,Modifier.size(15.dp),tint=Palette.pro)
                }
                Small("RECHARGE+")
            }
        }
        Small((if(preview.isExample)"A hard 60-minute session"else preview.label)+". "+COMPARISON_CAPTION)
    }
}
@Composable fun TodayScreen(graph: AppGraph,health: HealthState,isPro: Boolean,now: Instant,settings: ()->Unit,detail: (String)->Unit,upgrade: ()->Unit,effort: ()->Unit,connect: ()->Unit) {
    val explained=RecoveryResolver.explanation(health.scored.estimates,now)
    val phase=RecoveryResolver.phase(health.scored.estimates,now)
    Page {
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.Top) {
            Column(Modifier.weight(1f)){Text(now.dayLabel("EEEE, MMMM d"),fontSize=20.sp,fontWeight=FontWeight.Bold);Small(when{health.refreshing->"Checking Health Connect…";health.lastImportFailed->"Couldn't read Health Connect. Try again.";health.updated!=null->"Updated "+CountdownFormat.elapsed(health.updated,now);else->health.status})}
            IconButton(onClick=settings){Icon(Icons.Default.Settings,"Settings")}
        }
        if(graph.settings.hasDeferredHealthAccess||(health.workouts.isEmpty()&&health.updated==null))CardBlock {
            Title("Connect Health Connect");Text("Recharge needs workout access before it can start a countdown. Compatible fitness apps and wearables must share their records with Health Connect first.")
            Button(onClick=connect,Modifier.fillMaxWidth()){Text("Request access")}
        }
        Spacer(Modifier.height(4.dp))
        Column(Modifier.fillMaxWidth().clickable(enabled=explained!=null){explained?.let{detail(it.sessionID)}},horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(16.dp)) {
            BoxWithConstraints(Modifier.fillMaxWidth(),contentAlignment=Alignment.Center) {
                val diameter=minOf(maxWidth-32.dp,260.dp)
                val progress=explained?.let{RecoverySnapshot(if(it.producesCountdown)it.readyAt else null,it.sessionEnd,it.totalHours).progress(now)}?:0.0
                CountdownRing(phase,progress,Modifier.size(diameter)) {
                    Column(horizontalAlignment=Alignment.CenterHorizontally,modifier=Modifier.padding(32.dp)) {
                        when(phase) {
                            RecoveryPhase.noRecentWorkout->{Icon(Icons.Default.Info,null,Modifier.size(42.dp),tint=Palette.idle);Text("No recent workout",fontSize=16.sp,textAlign=TextAlign.Center)}
                            RecoveryPhase.ready->{Icon(Icons.Default.CheckCircle,null,Modifier.size(42.dp),tint=Palette.ready);Text("Ready",fontSize=36.sp,fontWeight=FontWeight.Bold)}
                            else->{Text(CountdownFormat.remaining(explained!!.remainingSeconds(now)),fontSize=39.sp,fontWeight=FontWeight.Bold,maxLines=1,style=TextStyle(fontFeatureSettings="tnum"));Small("left")}
                        }
                    }
                }
            }
            Text(when(phase){RecoveryPhase.noRecentWorkout->"Finish a workout and Recharge will estimate a window here.";RecoveryPhase.ready->"Recovery estimate complete.";else->"Estimate complete "+if(explained!!.confidence<=RecoveryConfidence.low)CountdownFormat.readySoftly(explained.readyAt,now)else CountdownFormat.readyAt(explained.readyAt,now)},Modifier.padding(horizontal=16.dp),fontWeight=FontWeight.SemiBold,textAlign=TextAlign.Center)
            explained?.let{e->Small(CountdownFormat.hours(e.recoveryCostHours)+" from your "+e.activityLabel+" "+CountdownFormat.elapsed(e.sessionEnd,now)+(if(e.isStacked)", on top of "+CountdownFormat.hours(e.carriedHours)+" already owed"else if(!e.producesCountdown)" · "+if(e.profile==WorkoutProfile.easy)"active recovery, so nothing to wait out"else"not enough to start a countdown"else""))}
        }
        Spacer(Modifier.height(8.dp))
        health.scored.awaitingEffort?.let{w->CardBlock(onClick=effort){Title("How hard was your "+WorkoutClassifier.label(w.activityCode)+"?");Small("Heart rate was patchy. Your rating counts whenever it reads harder than the sensors did.")}}
        ComparisonCard(health.scored.preview,isPro,upgrade)
        health.error?.let{Text(it,color=MaterialTheme.colorScheme.error)}
        TextButton(onClick={graph.scope.launch{graph.health.refresh()}}){Text("Refresh Health Connect")}
    }
}
@Composable fun HistoryScreen(graph: AppGraph,health: HealthState,detail: (String)->Unit,connect: ()->Unit) {
    if(health.scored.estimates.isEmpty()) {Page{Title(if(health.refreshing)"Reading your history"else"No estimates yet");Text(if(health.refreshing)"Recharge is scoring shared workouts from Health Connect."else"Nothing shared with Recharge to score yet. Finish a workout in a compatible fitness app and share it with Health Connect.");Button(onClick=connect){Text("Connect Health Connect")};TextButton(onClick={graph.scope.launch{graph.health.refresh()}}){Text("Try again")};health.error?.let{Text(it)}};return}
    val groups=health.scored.estimates.groupBy{it.sessionEnd.atZone(ZoneId.systemDefault()).toLocalDate()}.entries.sortedByDescending{it.key}
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(horizontal=16.dp,vertical=12.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
        groups.forEach{(day,estimates)->
            item(key="day-"+day){Row(Modifier.fillMaxWidth().padding(top=8.dp),horizontalArrangement=Arrangement.SpaceBetween){Small(estimates.first().sessionEnd.dayLabel("EEEE, MMM d"));if(estimates.size>1)Small(CountdownFormat.hours(estimates.sumOf{it.recoveryCostHours})+" total")}}
            items(estimates,key={it.sessionID}){e->CardBlock(onClick={detail(e.sessionID)}) {
                Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                    Column(Modifier.weight(1f)){Text(e.activityLabel.replaceFirstChar{it.uppercase()},fontWeight=FontWeight.SemiBold);Small((if(e.profile==WorkoutProfile.easy)"Active recovery"else e.category.shortLabel)+" · "+CountdownFormat.clock(e.sessionEnd))}
                    Column(horizontalAlignment=Alignment.End){Text(CountdownFormat.hours(e.recoveryCostHours),fontSize=22.sp,fontWeight=FontWeight.Bold);Small(if(e.isStacked)CountdownFormat.hours(e.totalHours)+" countdown"else if(e.producesCountdown)"countdown"else if(e.profile==WorkoutProfile.easy)"no countdown"else"under the threshold")}
                }
            }}
        }
    }
}
@Composable fun SessionDetailScreen(graph: AppGraph,health: HealthState,id: String?,isPro: Boolean,upgrade: ()->Unit) {
    val e=health.scored.estimates.find{it.sessionID==id}
    if(e==null){Page{Title("Session unavailable");Text("This session is no longer in the local health cache.")};return}
    val now=Instant.now();val expired=e.producesCountdown&&e.readyAt<=now
    Page {
        CardBlock {
            Text(CountdownFormat.hours(e.recoveryCostHours),fontSize=46.sp,fontWeight=FontWeight.Bold)
            Small(if(!e.producesCountdown)if(e.profile==WorkoutProfile.easy)"Active recovery. Counted toward your training load, and it never starts or extends a countdown."else"Counted toward your training load. Not enough on its own to start a countdown."else if(expired)"Countdown ran "+CountdownFormat.window(e.windowLowHours,e.windowHighHours)+"."else"Countdown runs "+CountdownFormat.window(e.windowLowHours,e.windowHighHours)+", ready "+CountdownFormat.readyAt(e.readyAt)+".")
            if(expired){Text("Ready",color=Palette.ready,fontWeight=FontWeight.Bold);Small("Your "+e.activityLabel+" set a "+CountdownFormat.hours(e.totalHours)+" countdown. It ran out "+CountdownFormat.elapsed(e.readyAt)+", so nothing is outstanding.")}
            if(e.isStacked)Small(CountdownFormat.stackedNote(e.hours,e.carriedHours))
            Small(e.profile.label+" · "+e.confidence.label)
        }
        CardBlock{Title("Why");e.reasons.forEach{Text("• "+it,fontSize=14.sp)}}
        CardBlock {
            Title("Numbers");DetailRow("Session load",e.load.value.fmt());DetailRow(if(e.tier==RecoveryTier.standard)"Compared to a typical session"else"Compared to your usual",e.relativeLoad.fmt(2)+"×");DetailRow("Load from",e.load.source.label)
            if(e.load.source==LoadSource.heartRate)DetailRow("Heart-rate coverage",(e.load.heartRateCoverage*100).fmt()+"%")
            DetailRow("Estimate",e.tier.label);if(e.tier==RecoveryTier.personalized)DetailRow("30-day recovery rate",((e.personalFactor-1)*100).fmt()+"%")
            DetailRow("Model version","v"+e.modelVersion)
            if(e.tier==RecoveryTier.personalized&&e.standardHours>0&&e.hours>0&&kotlin.math.abs(e.hours-e.standardHours)>=0.5){HorizontalDivider();DetailRow("Standard → Recharge+",CountdownFormat.hours(e.standardHours)+" → "+CountdownFormat.hours(e.hours));Small("The total difference includes your own baseline, the 30-day recovery rate and overnight context.")}
        }
        if(isPro) {
            val override=health.workouts.find{it.id==id}?.intensityOverride
            CardBlock{Title("How hard was it?");Small("Change it and the countdown is recalculated from your answer.");Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){SessionIntensity.entries.forEach{intensity->FilterChip(selected=(override?:e.category.intensity)==intensity,onClick={graph.scope.launch{graph.health.overrideIntensity(e.sessionID,intensity)}},label={Text(intensity.label)})}};if(override!=null)TextButton(onClick={graph.scope.launch{graph.health.overrideIntensity(e.sessionID,null)}}){Text("Use Recharge's")}}
            LoadCard(health)
        } else CardBlock(onClick=upgrade){Title("Correct this session");Small("Recharge+ lets you mark a session light, moderate or hard and have the countdown recalculated, pin your own hours to each intensity, and see your weekly load.")}
        Small(DISCLAIMER)
    }
}
@Composable fun LoadCard(health: HealthState){val (acute,chronic)=health.scored.loadBalance(Instant.now());CardBlock{Title("Training load");Row(horizontalArrangement=Arrangement.spacedBy(24.dp)){Metric("This week",acute.fmt());Metric("4-week average",chronic.fmt())};Small("Load is a proxy built from your own sessions, not a measurement.")}}
@Composable fun ReceiptCard(health: HealthState){if(health.receipt.isNotEmpty())CardBlock{Title("Read from Health Connect");Small("Everything below is going into your estimate.");health.receipt.forEach{row->DetailRow(row.title,row.value);Small(row.detail)}}}
@Composable fun PlusScreen(graph: AppGraph,health: HealthState) {
    val store by graph.store.state.collectAsState();val scope=rememberCoroutineScope();val context=androidx.compose.ui.platform.LocalContext.current
    Page {
        CardBlock{Title("Recharge+ active");Text("Your countdowns are measured, not looked up.")}
        ComparisonCard(health.scored.preview,true)
        val analysis=health.scored.personalAnalysis
        val lines=PersonalRecoveryModel.summary(analysis)
        if(lines.isNotEmpty())CardBlock{Title("What your last 30 days show");Text((if(analysis.percentDifference>0)"+"else"")+analysis.percentDifference+"%",color=Palette.pro,fontWeight=FontWeight.Bold);lines.forEach{Small(it)}}
        LoadCard(health);ReceiptCard(health)
        CardBlock{Title("Account");TextButton(onClick={scope.launch{graph.store.restorePurchases()}}){Text("Restore purchases")};TextButton(onClick={openLink(context,"https://play.google.com/store/account/subscriptions?package=com.jackwallner.recovery")}){Text("Manage subscription")};store.restoreError?.let{Small(it)}}
        Small(DISCLAIMER)
    }
}
