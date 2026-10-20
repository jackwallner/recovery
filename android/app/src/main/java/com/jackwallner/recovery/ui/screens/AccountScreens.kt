package com.jackwallner.recovery.ui.screens

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

import com.jackwallner.recovery.AppGraph
import com.jackwallner.recovery.data.*
import com.jackwallner.recovery.model.*
import com.jackwallner.recovery.ui.theme.*

fun openLink(context: Context,url: String)=runCatching{context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(url)));true}.getOrDefault(false)
private val features get()=AppContent.features

class PurchaseActions(private val graph: AppGraph,private val activity: Activity?,private val scope: CoroutineScope,private val success: ()->Unit) {
    var busy by mutableStateOf(false);private set
    var message by mutableStateOf<String?>(null);private set
    fun purchase(plan: PlanOption?) {
        if(busy||plan==null||activity==null)return
        scope.launch{busy=true;message=null;try{when(graph.store.purchase(activity,plan)){PurchaseOutcome.PURCHASED->success();PurchaseOutcome.PENDING->message="Purchase pending. Recharge+ unlocks when payment is confirmed.";PurchaseOutcome.CANCELLED->message=ConversionCopy.purchaseCancelledMessage(plan.trialLabel!=null)}}catch(error: Exception){message=error.message?:ConversionCopy.purchaseFailedMessage(plan.trialLabel!=null)}finally{busy=false}}
    }
    fun restore(){if(busy)return;scope.launch{busy=true;graph.store.restorePurchases();busy=false;if(graph.store.current.isPro)success()else message=graph.store.current.restoreError?:"No active Recharge+ purchase was found."}}
}
@Composable private fun rememberPurchaseActions(graph: AppGraph,success: ()->Unit): PurchaseActions {
    val context=LocalContext.current;val scope=rememberCoroutineScope();val latestSuccess by rememberUpdatedState(success)
    return remember(graph,context){PurchaseActions(graph,context as? Activity,scope){latestSuccess()}}
}
@Composable private fun LegalRow(actions: PurchaseActions) {
    val context=LocalContext.current
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceEvenly){TextButton(onClick=actions::restore,enabled=!actions.busy){Text("Restore")};TextButton(onClick={openLink(context,Legal.TERMS_URL)}){Text("Terms")};TextButton(onClick={openLink(context,Legal.PRIVACY_URL)}){Text("Privacy")}}
}
@Composable private fun OfferContent(graph: AppGraph,health: HealthState,allPlans: Boolean,selected: PlanOption?,select: (String)->Unit,actions: PurchaseActions) {
    val store by graph.store.state.collectAsState()
    Text("Recharge+",fontSize=32.sp,fontWeight=FontWeight.Bold,color=Palette.pro)
    Text("Personalized recovery from your history.",fontSize=19.sp)
    selected?.let{plan->Text(ConversionCopy.billedAmount(plan.priceLabel),fontSize=27.sp,fontWeight=FontWeight.Bold);Small(if(plan.recurring)ConversionCopy.billedNote(plan.trialLabel,plan.trialLabel!=null)else"One-time purchase · No subscription");Small(if(plan.recurring)ConversionCopy.disclosure(plan.trialLabel,plan.priceLabel,plan.trialLabel!=null)else plan.priceLabel+". No subscription, no renewal.")}
    ComparisonCard(health.scored.preview,false)
    ReceiptCard(health)
    CardBlock{features.forEach{(title,detail)->Text(title,fontWeight=FontWeight.SemiBold);Small(detail)}}
    if(store.isLoadingProducts)CircularProgressIndicator()
    else if(store.planOptions.isEmpty())CardBlock{Title("Couldn't load plans");Small("Your free countdown is still available.");TextButton(onClick={graph.scope.launch{graph.store.fetchProducts()}}){Text("Try again")}}
    else if(allPlans)store.planOptions.forEach{plan->CardBlock(onClick={if(!actions.busy)select(plan.id)}){Row(verticalAlignment=Alignment.CenterVertically){RadioButton(selected=plan.id==selected?.id,onClick={select(plan.id)},enabled=!actions.busy);Column{Text(plan.displayName,fontWeight=FontWeight.SemiBold);Text(ConversionCopy.billedAmount(plan.priceLabel),fontSize=22.sp,fontWeight=FontWeight.Bold);plan.trialLabel?.let{Small(it)}}}}}

    actions.message?.let{Text(it,color=MaterialTheme.colorScheme.error)}
    store.lastError?.let{Small(it)}
    Small("Countdown-complete notifications are included on every tier when you allow notifications.")
    Small(DISCLAIMER)
}
@Composable fun PaywallScreen(graph: AppGraph,health: HealthState,source: String="recharge_upgrade_tab",allPlans: Boolean=true,decline: (() ->Unit)?=null,onPurchased: ()->Unit={}) {
    val store by graph.store.state.collectAsState();var selectedID by rememberSaveable{mutableStateOf<String?>(null)}
    val selected=store.planOptions.find{it.id==selectedID}?:store.planOptions.find{it.displayName=="Yearly"}?:if(allPlans)store.planOptions.firstOrNull()else null
    val actions=rememberPurchaseActions(graph,onPurchased)
    LaunchedEffect(source){graph.store.trackPaywallImpression(source);graph.store.fetchProducts()}
    Column(Modifier.fillMaxSize().padding(horizontal=20.dp)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(vertical=16.dp),verticalArrangement=Arrangement.spacedBy(16.dp)){OfferContent(graph,health,allPlans,selected,{selectedID=it},actions)}
        decline?.let{TextButton(onClick=it,enabled=!actions.busy,modifier=Modifier.fillMaxWidth()){Text("Not now")}}
        selected?.let { Text(ConversionCopy.billedAmount(it.priceLabel), fontSize=22.sp, fontWeight=FontWeight.Bold) }
        Button(onClick={actions.purchase(selected)},enabled=selected!=null&&!actions.busy,modifier=Modifier.fillMaxWidth().heightIn(min=52.dp)){Text(if(actions.busy)"Please wait…"else ConversionCopy.ctaLabel)}
        LegalRow(actions)
    }
}
private data class QuestionOption(val label: String,val selected: Boolean,val action: ()->Unit)
@Composable fun QuestionOptions(settings: Settings,key: String,allowUnset: Boolean=false) {
    val p=settings.profile
    fun update(value: AthleteProfile)=settings.updateProfile(value.copy(healthDerivedFields=value.healthDerivedFields-key))
    val options=when(key){
        "age"->AthleteProfile.ageBands.map{(label,midpoint)->QuestionOption(label,p.age?.let(AthleteProfile::ageBandMidpoint)==midpoint){update(p.copy(age=midpoint))}}
        "experience"->TrainingExperience.entries.map{QuestionOption(it.label,p.experience==it){update(p.copy(experience=it))}}
        "weeklyVolume"->WeeklyVolume.entries.map{QuestionOption(it.label,p.weeklyVolume==it){update(p.copy(weeklyVolume=it))}}
        else->BounceBackHabit.entries.map{QuestionOption(it.label,p.bounceBack==it){update(p.copy(bounceBack=it))}}
    }
    if(allowUnset)TextButton(onClick={update(when(key){"age"->p.copy(age=null);"experience"->p.copy(experience=null);"weeklyVolume"->p.copy(weeklyVolume=null);else->p.copy(bounceBack=null)})}){Text("Not set")}
    options.forEachIndexed{index,option->Row(Modifier.fillMaxWidth().heightIn(min=48.dp).testTag("answer-"+key+"-"+index).clickable(onClick=option.action),verticalAlignment=Alignment.CenterVertically){RadioButton(selected=option.selected,onClick=null);Text(option.label)}}
}
private fun questionTitle(key: String)=AppContent.questionTitle(key)
private fun questionDetail(key: String)=AppContent.questionDetail(key)

@Composable fun OnboardingScreen(graph: AppGraph,health: HealthState,connect: ((()->Unit)->Unit),finish: ()->Unit) {
    var index by rememberSaveable{mutableIntStateOf(0)}
    var resolved by rememberSaveable{mutableStateOf(false)}
    var questions by rememberSaveable{mutableStateOf(emptyList<String>())}
    var hasReceipt by rememberSaveable{mutableStateOf(false)}
    var requesting by remember{mutableStateOf(false)}
    val steps=if(!resolved)listOf("welcome","health")else listOf("welcome","health")+(if(hasReceipt)listOf("receipt")else emptyList())+questions+listOf("honesty","offer")
    val step=steps[index.coerceAtMost(steps.lastIndex)]
    val p=graph.settings.profile
    val answered=when(step){"age"->p.age!=null;"experience"->p.experience!=null;"weeklyVolume"->p.weeklyVolume!=null;"bounceBack"->p.bounceBack!=null;else->true}
    val store by graph.store.state.collectAsState();val annual=store.planOptions.find{it.displayName=="Yearly"}
    val actions=rememberPurchaseActions(graph,finish)
    LaunchedEffect(step){if(step=="offer"){graph.store.trackPaywallImpression("recharge_onboarding");graph.store.fetchProducts()}}
    Column(Modifier.fillMaxSize().systemBarsPadding().padding(horizontal=28.dp)) {
        Box(Modifier.weight(1f).fillMaxWidth(),contentAlignment=Alignment.Center) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(vertical=24.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(16.dp)) {
                when(step) {
                    "welcome"->{Text("Recovery time,\nfrom your workouts",fontSize=32.sp,lineHeight=38.sp,fontWeight=FontWeight.Bold,textAlign=TextAlign.Center);Text("Finish a qualifying workout and Recharge starts a training-load countdown. When it runs out, the estimate is complete. Recharge reads Health Connect and never writes to it.",textAlign=TextAlign.Center)}
                    "health"->{Title("Recharge reads\nHealth Connect");Text("Your workouts and heart rate build the estimate. Sleep, resting heart rate, HRV (RMSSD), breathing rate, cardio fitness and weight sharpen it. Nothing is written back, and health data stays on your device.",textAlign=TextAlign.Center);Small("A compatible fitness source must share records first. One-minute heart rate recovery is unavailable. Age is asked for below.");if(requesting)CircularProgressIndicator()}
                    "receipt"->{Title("Here's what Health gave us");ReceiptCard(health);Small(questions.size.toString()+" short questions left, for the things Health can't answer.")}
                    "honesty"->{Title("What the number actually means");Text("Recharge estimates a training-load recovery window from your recent workouts. It is not a measure of muscle repair, illness, injury risk, or whether you are fit to train, and it is not medical advice. Talk with a qualified health professional before making medical decisions.",textAlign=TextAlign.Center)}
                    "offer"->OfferContent(graph,health,false,annual,{},actions)
                    else->{Text(questionTitle(step),fontSize=26.sp,fontWeight=FontWeight.Bold,textAlign=TextAlign.Center);Small(questionDetail(step));QuestionOptions(graph.settings,step)}
                }
            }
        }
        Box(Modifier.fillMaxWidth().height(44.dp),contentAlignment=Alignment.Center){if(step=="offer")TextButton(onClick=finish,enabled=!actions.busy){Text("Get Started")}}
        Button(onClick={when(step){"health"->{requesting=true;connect{requesting=false;questions=graph.settings.profile.gaps;hasReceipt=graph.health.state.value.receipt.isNotEmpty();resolved=true;index++}};"offer"->actions.purchase(annual);else->index++}},enabled=!requesting&&!actions.busy&&(step!="offer"||annual!=null),modifier=Modifier.fillMaxWidth().height(52.dp).testTag("onboarding-primary")){Text(when{requesting||actions.busy->"Please wait…";step=="offer"->ConversionCopy.ctaLabel;step=="honesty"->"I understand";!answered->"Skip this one";else->"Continue"})}
        Box(Modifier.fillMaxWidth().height(52.dp)){if(step=="offer")LegalRow(actions)}
        LinearProgressIndicator(progress={((index+1).toFloat()/(if(resolved)steps.size else 9)).coerceIn(0f,1f)},modifier=Modifier.fillMaxWidth().height(4.dp),trackColor=MaterialTheme.colorScheme.surfaceContainerHighest)
        Spacer(Modifier.height(12.dp))
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable fun SettingsScreen(graph: AppGraph,health: HealthState,isPro: Boolean,connect: (Boolean)->Unit,upgrade: ()->Unit,privacy: ()->Unit) {
    val settings=graph.settings;val scope=rememberCoroutineScope();val context=LocalContext.current
    val store by graph.store.state.collectAsState()
    var reviewer by remember{mutableStateOf(false)}
    var editor by remember{mutableStateOf<String?>(null)};var delete by remember{mutableStateOf(false)};var message by remember{mutableStateOf<String?>(null)}
    val notificationPermission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){graph.notifications.schedule(graph.health.state.value)}
    Page {
        ComparisonCard(health.scored.preview,isPro,upgrade)
        CardBlock{Title("Health Connect");Text(health.status);health.error?.let{Small(it)};Button(onClick={connect(false)}){Text("Request access")};TextButton(onClick={scope.launch{graph.health.refresh()}}){Text("Refresh Health Connect")};TextButton(onClick={runCatching{context.startActivity(graph.health.settingsIntent())}}){Text("Open Health settings")};Small("Reads the last 120 days when history access is allowed. Without it, Health Connect limits earlier history. Individual read permissions can be changed in Health Connect.")}
        ReceiptCard(health)
        CardBlock{Title("Recharge time");DetailRow("Model",if(isPro)"Recharge+"else"Standard");if(health.scored.personalAnalysis.isPersonalised)DetailRow("30-day recovery rate",health.scored.personalAnalysis.percentDifference.toString()+"%");Small(if(isPro)"Every session is scored against your own 42-day baseline, then adjusted by your 30-day pattern."else"The free estimate scores each session at your training level. Recharge+ scores it against your own sessions, sleep and heart rate.");if(!isPro)TextButton(onClick=upgrade){Text("See Recharge+")}}
        CardBlock {
            Title("About you")
            ActionRow("Age",settings.profile.age?.toString()?:"Not set"){editor="age"}
            ActionRow("Training for",settings.profile.experience?.label?:"Not set"){editor="experience"}
            ActionRow("Sessions a week",settings.profile.weeklyVolume?.label?:"Not set"){editor="weeklyVolume"}
            ActionRow("Ready again after",settings.profile.bounceBack?.label?:"Not set"){editor="bounceBack"}
            Small("Age sets the heart-rate range. Sessions a week and training experience set your training level on both tiers. Ready again after shapes Recharge+ until your history can answer.")
        }
        CardBlock {
            Title("Model settings");ActionRow("Functional and hybrid training",settings.ambiguousProfile.label){editor="ambiguous"};ActionRow("Max heart rate",settings.maxHeartRate?.let{it.fmt()+" bpm"}?:"Automatic"){editor="maximum"}
            settings.profile.effectiveMaxHeartRate?.let{Small("Automatic ceiling: "+it.fmt()+" bpm, "+if(settings.profile.usesObservedMaxHeartRate)"from your workouts."else"from your age profile.")}
            DetailRow("Personal calibration",((settings.calibration-1)*100).fmt()+"%");if(settings.calibration!=1.0)TextButton(onClick=settings::resetCalibration){Text("Reset calibration")}
        }
        if(isPro) {
            CardBlock{Title("Body signals");ToggleRow("Use body signals",settings.useContextSignals,settings::setContext);Small("Sleep, resting heart rate, HRV (RMSSD) and breathing rate adjust the estimate against your own baseline. One-minute recovery is unavailable through Health Connect.")}
            CardBlock{Title("Your own recharge times");SessionIntensity.entries.forEach{intensity->ActionRow(intensity.label,settings.manualWindows.hours(intensity)?.let(CountdownFormat::hours)?:"Recharge decides"){editor="pin-"+intensity.name}};if(!settings.manualWindows.isEmpty)TextButton(onClick={SessionIntensity.entries.forEach{settings.setManualWindow(it,null)}}){Text("Clear all")};Small("Pin your preferred hours after a light, moderate or hard session. A pinned band replaces the model's figure.")}
        }
        CardBlock {
            Title("Notifications");ToggleRow("Notify me when countdown ends",settings.notifyOnReady){value->settings.setNotifications(value);if(value){if(Build.VERSION.SDK_INT>=33)notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS);graph.notifications.schedule(health)}else graph.notifications.cancel()}
            Small("The Ready alert is free. Android schedules it inexactly, so delivery can be delayed.")
            if(settings.notifyOnReady&&!graph.notifications.allowed()){Small("Notifications are not allowed in Android settings.");TextButton(onClick={context.startActivity(Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE,context.packageName))}){Text("Open notification settings")}}
            TextButton(onClick={connect(true)}){Text("Allow background Health Connect reads")};Small("Optional background access lets shared workouts and body signals refresh while Recharge is closed. Reads run periodically.")
        }
        CardBlock{ActionRow("Appearance",listOf("System","Light","Dark")[settings.appearance]){editor="appearance"}}
        CardBlock {
            Title("Account");TextButton(onClick={scope.launch{graph.store.restorePurchases()}}){Text("Restore purchases")}
            if(isPro)TextButton(onClick={openLink(context,"https://play.google.com/store/account/subscriptions?package=com.jackwallner.recovery")}){Text("Manage subscription")}
            store.restoreError?.let{Small(it)}
            ActionRow("Rate Recharge"){if(openLink(context,Legal.PLAY_LISTING_URL))graph.review.markOpenedWriteReview()else message="Couldn't open Google Play."}
            ActionRow("Send feedback"){val opened=runCatching{context.startActivity(Intent(Intent.ACTION_SENDTO,Uri.parse("mailto:jackwallner@gmail.com?subject=Recharge%20feedback")));true}.getOrDefault(false);if(opened)graph.review.markSoftDeferred()else message="No email app is installed. Email jackwallner@gmail.com."}
            ActionRow("Privacy policy",onClick=privacy);ActionRow("Terms"){openLink(context,Legal.TERMS_URL)}
        }
        CardBlock{Title("Your data");TextButton(onClick={delete=true}){Text("Delete local health data",color=MaterialTheme.colorScheme.error)};Small("Deletes Recharge's local health cache and derived estimates. Health Connect records and purchases are not affected.")}
        Small(DISCLAIMER);Text("Version "+com.jackwallner.recovery.BuildConfig.VERSION_NAME+" · Model v17",color=MaterialTheme.colorScheme.onSurfaceVariant,fontSize=13.sp,modifier=Modifier.combinedClickable(onClick={},onLongClick={reviewer=true}))
        Small("Wear OS and widgets are not included in this version.")
        message?.let{Text(it)}
    }
    if(reviewer)ReviewerCodeDialog(graph){reviewer=false}
    editor?.let{key->
        when {
            key=="maximum"->MaximumHeartRateDialog(settings.maxHeartRate,{settings.updateMaxHeartRate(it);editor=null},{editor=null})
            else->AlertDialog(onDismissRequest={editor=null},title={Text(when {key=="appearance"->"Appearance";key=="ambiguous"->"Functional and hybrid training";key.startsWith("pin-")->"Your own recharge time";else->questionTitle(key)})},text={Column(Modifier.heightIn(max=400.dp).verticalScroll(rememberScrollState())){
                when {
                    key=="appearance"->listOf("System","Light","Dark").forEachIndexed{index,label->TextButton(onClick={settings.updateAppearance(index);editor=null},Modifier.fillMaxWidth()){Text(label)}}
                    key=="ambiguous"->listOf(WorkoutProfile.mixed,WorkoutProfile.strength,WorkoutProfile.endurance).forEach{profile->TextButton(onClick={settings.updateAmbiguousProfile(profile);editor=null},Modifier.fillMaxWidth()){Text(profile.label)}}
                    key.startsWith("pin-")->{val intensity=SessionIntensity.valueOf(key.removePrefix("pin-"));TextButton(onClick={settings.setManualWindow(intensity,null);editor=null}){Text("Recharge decides")};((6..24 step 3)+(30..96 step 6)).forEach{hours->TextButton(onClick={settings.setManualWindow(intensity,hours.toDouble());editor=null},Modifier.fillMaxWidth()){Text(hours.toString()+"h")}}}
                    else->QuestionOptions(settings,key,true)
                }
            }},confirmButton={TextButton(onClick={editor=null}){Text("Done")}})
        }
    }
    if(delete)AlertDialog(onDismissRequest={delete=false},title={Text("Delete local health data?")},text={Text("Health Connect records and purchases are not affected.")},confirmButton={TextButton(onClick={scope.launch{graph.health.deleteLocalData()};delete=false}){Text("Delete")}},dismissButton={TextButton(onClick={delete=false}){Text("Cancel")}})
}
@Composable private fun MaximumHeartRateDialog(current: Double?,save: (Double?)->Unit,dismiss: ()->Unit) {
    var text by remember{mutableStateOf(current?.fmt()?:"")}
    val value=text.toDoubleOrNull();val valid=text.isBlank()||(value!=null&&value in 120.0..230.0)
    AlertDialog(onDismissRequest=dismiss,title={Text("Max heart rate")},text={Column{OutlinedTextField(text,{text=it},label={Text("Maximum heart rate")},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Number),singleLine=true,isError=!valid);Small("Enter 120 to 230 bpm, or leave blank for automatic.")}},confirmButton={TextButton(onClick={save(value)},enabled=valid){Text("Save")}},dismissButton={TextButton(onClick=dismiss){Text("Cancel")}})
}
const val PRIVACY_TEXT="Recharge reads workouts, heart rate, active energy, resting heart rate, HRV (RMSSD), sleep, breathing rate, VO2 max and weight from Health Connect with your permission. Health readings, effort answers and derived estimates stay on your device. We do not send health data to a server. Read access is optional per data type and can be revoked in Health Connect. Core workout revocation clears the local cache. Optional revocation removes the affected inputs and recalculates local estimates. Delete local health data clears the cache without deleting records from Health Connect. Removing app storage also deletes it. RevenueCat and Google Play process purchase information, anonymous app identifiers, app version information, and counts, dates and short labels about purchase screens. No health data or free text is included in purchase diagnostics. No ads or app account. Contact jackwallner@gmail.com."
@Composable fun PrivacyScreen(){Surface{Page{Title("Recharge Privacy Policy");Text(PRIVACY_TEXT);Small(DISCLAIMER)}}}

@Composable private fun ReviewerCodeDialog(graph: AppGraph,close: ()->Unit) {
    var code by remember{mutableStateOf("")}
    var failed by remember{mutableStateOf(false)}
    AlertDialog(onDismissRequest=close,title={Text("Reviewer access")},text={Column {
        Text("Enter the code provided in the Play review instructions.")
        OutlinedTextField(code,{code=it;failed=false},label={Text("Reviewer code")},singleLine=true,keyboardOptions=androidx.compose.foundation.text.KeyboardOptions(keyboardType=androidx.compose.ui.text.input.KeyboardType.Password,autoCorrectEnabled=false),visualTransformation=androidx.compose.ui.text.input.PasswordVisualTransformation())
        if(failed)Text("That code isn't valid.",color=MaterialTheme.colorScheme.error)
    }},confirmButton={TextButton(onClick={if(graph.store.activateReviewAccess(code))close()else failed=true}){Text("Unlock")}},dismissButton={TextButton(onClick=close){Text("Cancel")}})
}
