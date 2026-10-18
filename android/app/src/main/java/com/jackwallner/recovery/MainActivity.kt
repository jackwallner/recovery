package com.jackwallner.recovery

import android.content.Intent
import android.os.Bundle

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

import com.jackwallner.recovery.ui.RootScreen
import com.jackwallner.recovery.ui.screens.PrivacyScreen
import com.jackwallner.recovery.ui.theme.RechargeTheme

class MainActivity: ComponentActivity() {
    private val graph get()=(application as RechargeApplication).graph
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState);enableEdgeToEdge();graph.recordForegroundOpen()
        DebugLaunchOptions.apply(this,graph,intent)
        if(intent.getStringExtra("route")=="today")graph.openToday.value=System.currentTimeMillis()
        setContent{RootScreen(graph)}
    }
    override fun onNewIntent(intent: Intent){super.onNewIntent(intent);setIntent(intent);if(intent.getStringExtra("route")=="today")graph.openToday.value=System.currentTimeMillis()}
    override fun onResume(){super.onResume();lifecycleScope.launch{graph.store.start()};lifecycleScope.launch{graph.health.refresh()}}
}
class PermissionsRationaleActivity: ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?){super.onCreate(savedInstanceState);setContent{RechargeTheme(false){PrivacyScreen()}}}
}
