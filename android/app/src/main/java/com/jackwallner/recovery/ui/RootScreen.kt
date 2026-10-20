package com.jackwallner.recovery.ui

import android.Manifest
import android.app.Activity
import android.os.Build
import java.time.Instant

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.core.view.WindowCompat
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import com.google.android.play.core.review.ReviewManagerFactory
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

import com.jackwallner.recovery.AppGraph
import com.jackwallner.recovery.model.*
import com.jackwallner.recovery.ui.nav.*
import com.jackwallner.recovery.ui.screens.*
import com.jackwallner.recovery.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun RootScreen(graph: AppGraph) {
    val settings=graph.settings;val context=LocalContext.current;val scope=rememberCoroutineScope()
    val dark=when(settings.appearance){1->false;2->true;else->isSystemInDarkTheme()}
    val store by graph.store.state.collectAsState();val health by graph.health.state.collectAsState();val openToday by graph.openToday.collectAsState()
    var now by remember{mutableStateOf(Instant.now())}
    var tab by rememberSaveable{mutableIntStateOf(graph.initialTab)}
    val navigators=remember{List(3){Navigator()}};val navigator=navigators[tab]
    var sheet by remember{mutableStateOf<String?>(null)}
    var afterPermission by remember{mutableStateOf<(() ->Unit)?>(null)}
    var requestingPermission by remember{mutableStateOf(false)}
    val permissionLauncher=rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) {
        scope.launch{graph.health.refresh();requestingPermission=false;val done=afterPermission;afterPermission=null;done?.invoke()}
    }
    val requestHealth: (Boolean,()->Unit)->Unit={background,done->
        if(!requestingPermission) {
            requestingPermission=true;afterPermission=done
            if(graph.health.sdkStatus==HealthConnectClient.SDK_AVAILABLE)runCatching{permissionLauncher.launch(graph.health.permissions(background))}.onFailure{requestingPermission=false;settings.setDeferredHealth(true);afterPermission=null;done()}
            else {runCatching{context.startActivity(graph.health.settingsIntent())};settings.setDeferredHealth(true);requestingPermission=false;afterPermission=null;done()}
        }
    }
    val notificationPermission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){graph.notifications.schedule(graph.health.state.value)}
    val finishSetup: ()->Unit={
        settings.completeSetup()
        if(settings.notifyOnReady&&!graph.values.bool("hasRequestedReadyNotifications")) {
            graph.values.put("hasRequestedReadyNotifications","true")
            if(Build.VERSION.SDK_INT>=33&&!graph.review.isAutomationRun)notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    SideEffect{(context as? Activity)?.window?.let{window->WindowCompat.getInsetsController(window,window.decorView).apply{isAppearanceLightStatusBars=!dark;isAppearanceLightNavigationBars=!dark}}}
    LaunchedEffect(Unit){while(true){delay(60_000);now=Instant.now();graph.health.clockTick()}}
    LaunchedEffect(openToday){if(openToday>0){sheet=null;tab=0;navigators[0].popToRoot()}}
    LaunchedEffect(store.isPro){graph.health.rescore();if(store.isPro){if(navigator.top==Route.Paywall)navigator.pop();if(sheet=="trial")sheet=null}}
    val clearToday=settings.hasCompletedSetup&&tab==0&&navigator.depth==1&&sheet==null
    LaunchedEffect(clearToday,health.scored.awaitingFeedback?.sessionID) {
        val pending=health.scored.awaitingFeedback
        if(clearToday&&pending!=null&&pending.sessionID !in settings.answeredFeedback&&!graph.review.isAutomationRun){delay(600);if(sheet==null&&tab==0&&navigator.depth==1)sheet="feedback"}
    }
    LaunchedEffect(clearToday,store.isResolved,store.planOptions.isNotEmpty(),health.scored.estimates.firstOrNull()?.readyAt) {
        if(!clearToday||graph.review.isAutomationRun)return@LaunchedEffect
        val seen=graph.values.string("lastWhatsNewVersionShown")
        if(seen==null)graph.values.put("lastWhatsNewVersionShown",AppContent.announcementVersion)
        else if(seen!=AppContent.announcementVersion){sheet="updates";graph.values.put("lastWhatsNewVersionShown",AppContent.announcementVersion);return@LaunchedEffect}
        delay(1200)
        if(sheet!=null||tab!=0||navigator.depth!=1)return@LaunchedEffect
        if(health.scored.awaitingFeedback?.sessionID?.let{it !in settings.answeredFeedback}==true)return@LaunchedEffect
        if(graph.review.shouldRequest(settings.hasCompletedSetup)) {
            val activity=context as? Activity
            if(activity!=null){val manager=ReviewManagerFactory.create(context);manager.requestReviewFlow().addOnSuccessListener{info->if(sheet==null&&tab==0&&navigator.depth==1){graph.review.markShown();manager.launchReviewFlow(activity,info)}}}
        } else if(!store.isPro&&store.isResolved&&store.planOptions.any{it.displayName=="Yearly"}&&settings.passiveTrialOfferAllowed()) {
            graph.values.put("lastTrialOfferShownDate",System.currentTimeMillis().toString());sheet="trial"
        }
    }
    val upgrade: ()->Unit={if(store.isPro){tab=2}else if(sheet==null)navigator.push(Route.Paywall)}
    val showDetail: (String)->Unit={id->navigator.detailId=id;navigator.push(Route.Detail)}
    BackHandler(enabled=navigator.depth==1&&tab!=0&&sheet==null){tab=0}
    RechargeTheme(dark) {
        Surface(Modifier.fillMaxSize().semantics{testTagsAsResourceId=true}) {
            if(!settings.hasCompletedSetup)OnboardingScreen(graph,health,{done->requestHealth(false,done)},finishSetup)
            else Scaffold(containerColor=MaterialTheme.colorScheme.background,topBar={
                if(tab!=0||navigator.depth>1)TopAppBar(title={Text(if(navigator.top==Route.Root)if(tab==1)"History"else if(store.isPro)"Recharge+"else"Upgrade"else if(navigator.top==Route.Detail)health.scored.estimates.find{it.sessionID==navigator.detailId}?.activityLabel?.replaceFirstChar{it.uppercase()}?:"Session"else navigator.top.title)},navigationIcon={if(navigator.depth>1)IconButton(onClick={navigator.pop()}){Icon(Icons.AutoMirrored.Filled.ArrowBack,"Back")}},colors=TopAppBarDefaults.topAppBarColors(containerColor=MaterialTheme.colorScheme.background))
            },bottomBar={
                NavigationBar(containerColor=MaterialTheme.colorScheme.background) {
                    listOf("Today","History",if(store.isPro)"Recharge+"else"Upgrade").forEachIndexed{index,label->NavigationBarItem(modifier=Modifier.testTag("tab-"+index),selected=tab==index,colors=NavigationBarItemDefaults.colors(selectedIconColor=MaterialTheme.colorScheme.primary,selectedTextColor=MaterialTheme.colorScheme.primary,indicatorColor=MaterialTheme.colorScheme.primary.copy(alpha=0.14f)),onClick={if(tab==index)navigator.popToRoot()else tab=index},icon={Icon(when(index){0->Icons.Default.Home;1->Icons.Default.List;else->Icons.Default.Star},null)},label={Text(label)})}
                }
            }){padding->Box(Modifier.padding(padding)) {
                NavStack(navigator){route->when(route){
                    Route.Root->when(tab){0->TodayScreen(graph,health,store.isPro,now,{navigator.push(Route.Settings)},showDetail,upgrade,{sheet="effort"},{requestHealth(false,{})});1->HistoryScreen(graph,health,showDetail){requestHealth(false,{})};else->if(store.isPro)PlusScreen(graph,health)else PaywallScreen(graph,health)}
                    Route.Settings->SettingsScreen(graph,health,store.isPro,{background->requestHealth(background,{})},upgrade,{navigator.push(Route.Privacy)})
                    Route.Paywall->PaywallScreen(graph,health,"recharge_locked_surface",onPurchased={navigator.pop()})
                    Route.Detail->SessionDetailScreen(graph,health,navigator.detailId,store.isPro,upgrade)
                    Route.Privacy->PrivacyScreen()
                }}
            }}
            if(sheet!=null) {
                val close: ()->Unit={if(sheet=="feedback")health.scored.awaitingFeedback?.let{settings.dismissFeedback(it.sessionID);scope.launch{graph.health.clockTick()}};sheet=null}
                ModalBottomSheet(onDismissRequest=close) {
                    when(sheet) {
                        "trial"->Box(Modifier.fillMaxHeight(0.85f)){PaywallScreen(graph,health,"recharge_passive_offer",false,{sheet=null},{sheet=null})}
                        "updates"->Box(Modifier.fillMaxHeight(0.85f)){Page{Title("What's new in Recharge");AppContent.updates.forEach{(title,detail)->Title(title);Small(detail)};Button(onClick={sheet=null},Modifier.fillMaxWidth()){Text("Continue")}}}
                        "effort"->Page {val workout=health.scored.awaitingEffort;Title("How hard was it?");if(workout!=null){Small("Your "+workout.minutes.fmt()+"-minute "+WorkoutClassifier.label(workout.activityCode)+" didn't have usable heart-rate data. Your rating counts whenever it reads harder than the other signals.");listOf("Easy" to 4.0,"Moderate" to 7.0,"Hard" to 9.0).forEach{(label,value)->Button(onClick={scope.launch{graph.health.recordEffort(workout.id,value)};sheet=null},Modifier.fillMaxWidth()){Text(label)}};TextButton(onClick={settings.declineEffort(workout.id);scope.launch{graph.health.rescore()};sheet=null}){Text("Skip")}}else TextButton(onClick={sheet=null}){Text("Close")}}
                        "feedback"->Page {val pending=health.scored.awaitingFeedback;Title("How did that feel?");Small("Your estimate ran out. Telling Recharge how it went tunes your own bands.");ReadinessFeedback.entries.forEach{feedback->Button(onClick={pending?.let{settings.applyFeedback(feedback,it.sessionID)};sheet=null},Modifier.fillMaxWidth()){Text(feedback.label)}};TextButton(onClick=close){Text("Not now")};Small("Stored on this device only.")}
                    }
                }
            }
        }
    }
}
