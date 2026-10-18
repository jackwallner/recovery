package com.jackwallner.recovery.ui.theme

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

import com.jackwallner.recovery.model.RecoveryPhase

object Palette {
    val recovering=Color(0xFFFF9E33);val recoveringSecondary=Color(0xFFFF7347)
    val ready=Color(0xFF3DC770);val readySecondary=Color(0xFF29B394)
    val readySoon=Color(0xFFC7C23D);val idle=Color(0xFF7A8599);val pro=Color(0xFF5C70EB)
    fun phase(phase: RecoveryPhase)=when(phase){RecoveryPhase.recovering->recovering;RecoveryPhase.readySoon->readySoon;RecoveryPhase.ready->ready;else->idle}
}
@Composable fun RechargeTheme(dark: Boolean,content: @Composable ()->Unit) {
    val colors=if(dark)darkColorScheme(primary=Palette.recovering,onPrimary=Color.Black,secondary=Palette.pro,secondaryContainer=Color(0xFF29325C),onSecondaryContainer=Color(0xFFDDE2FF),background=Color.Black,surface=Color.Black,surfaceContainer=Color(0xFF1C1C1E),surfaceVariant=Color(0xFF1C1C1E),onSurfaceVariant=Color(0xFFADAEB5))
        else lightColorScheme(primary=Color(0xFFA94F00),onPrimary=Color.White,secondary=Palette.pro,secondaryContainer=Color(0xFFE4E7FF),onSecondaryContainer=Color(0xFF27326D),background=Color.White,surface=Color.White,surfaceContainer=Color(0xFFF2F2F7),surfaceVariant=Color(0xFFF2F2F7),onSurfaceVariant=Color(0xFF64646C))
    MaterialTheme(colorScheme=colors,content=content)
}
@Composable fun Page(content: @Composable ColumnScope.()->Unit) {Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal=20.dp,vertical=16.dp),verticalArrangement=Arrangement.spacedBy(16.dp)){content();Spacer(Modifier.height(8.dp))}}
@Composable fun CardBlock(modifier: Modifier=Modifier,onClick: (() ->Unit)?=null,content: @Composable ColumnScope.()->Unit) {
    val shape=RoundedCornerShape(20.dp)
    Surface(modifier.fillMaxWidth().clip(shape).then(if(onClick!=null)Modifier.clickable(onClick=onClick)else Modifier),shape=shape,color=MaterialTheme.colorScheme.surfaceContainer) {Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(10.dp),content=content)}
}
@Composable fun Title(text: String){Text(text,fontWeight=FontWeight.Bold,fontSize=20.sp)}
@Composable fun Small(text: String){Text(text,color=MaterialTheme.colorScheme.onSurfaceVariant,fontSize=13.sp)}
@Composable fun Metric(label: String,value: String,color: Color=MaterialTheme.colorScheme.onSurface){Column{Text(value,fontSize=30.sp,fontWeight=FontWeight.Bold,color=color);Small(label)}}
@Composable fun ActionRow(title: String,value: String="",onClick: ()->Unit){Row(Modifier.fillMaxWidth().heightIn(min=52.dp).clickable(onClick=onClick),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)){Text(title,Modifier.weight(1f));if(value.isNotEmpty())Small(value);Text("›",fontSize=26.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}}
@Composable fun ToggleRow(title: String,checked: Boolean,onChange: (Boolean)->Unit){Row(Modifier.fillMaxWidth().heightIn(min=52.dp),verticalAlignment=Alignment.CenterVertically){Text(title,Modifier.weight(1f));Switch(checked,onCheckedChange=onChange)}}
@Composable fun DetailRow(label: String,value: String){Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)){Text(label,Modifier.weight(1f),fontSize=14.sp,color=MaterialTheme.colorScheme.onSurfaceVariant);Text(value,fontSize=14.sp,fontWeight=FontWeight.SemiBold)}}
@Composable fun CountdownRing(phase: RecoveryPhase,progress: Double,modifier: Modifier=Modifier,content: @Composable BoxScope.()->Unit) {
    val track=MaterialTheme.colorScheme.outlineVariant
    Box(modifier,contentAlignment=Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val line=size.minDimension*0.085f;val inset=line/2
            drawCircle(track,radius=(size.minDimension-line)/2,style=Stroke(line))
            val colors=when(phase){RecoveryPhase.recovering->listOf(Palette.recovering,Palette.recoveringSecondary);RecoveryPhase.ready->listOf(Palette.ready,Palette.readySecondary);else->listOf(Palette.phase(phase),Palette.phase(phase))}
            drawArc(Brush.linearGradient(colors),-90f,(progress.coerceIn(0.0,1.0)*360).toFloat(),false,topLeft=Offset(inset,inset),size=Size(size.width-line,size.height-line),style=Stroke(line,cap=StrokeCap.Round))
        }
        content()
    }
}
fun Double.fmt(decimals: Int=0)=String.format(Locale.US,"%."+decimals+"f",this)
fun Instant.dayLabel(pattern: String="MMM d, yyyy")=atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern(pattern))
