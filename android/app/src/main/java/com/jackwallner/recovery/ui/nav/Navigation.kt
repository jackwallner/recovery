package com.jackwallner.recovery.ui.nav

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier

/** Every pushed destination in the app. */
enum class Route(val title: String) {
    Root(""), Settings("Settings"), Paywall("Recharge+"), Detail("Session"), Privacy("Privacy")
}

internal data class Entry(val id: Int, val route: Route)

/** One navigation stack, the Compose counterpart of a `NavigationStack`. */
@Stable
class Navigator {
    var detailId: String? by mutableStateOf(null)
    private var nextId = 1
    private val entries = mutableStateListOf(Entry(0, Route.Root))
    var lastWasPop by mutableStateOf(false)
        private set
    /** Bumps on every pop, so a screen can react to coming back into view. */
    var popCount by mutableIntStateOf(0)
        private set

    val depth: Int get() = entries.size
    val top: Route get() = entries.last().route
    internal val topEntry: Entry get() = entries.last()

    fun push(route: Route) {
        lastWasPop = false
        entries.add(Entry(nextId++, route))
    }

    fun pop(): Boolean {
        if (entries.size <= 1) return false
        lastWasPop = true
        release(entries.removeAt(entries.lastIndex).id)
        popCount++
        return true
    }

    fun popToRoot() {
        if (entries.size <= 1) return
        lastWasPop = true
        while (entries.size > 1) release(entries.removeAt(entries.lastIndex).id)
        popCount++
    }

    /** Objects that outlive a screen leaving composition while it sits under another. */
    internal val retained = mutableMapOf<Int, MutableMap<String, Any?>>()

    private fun release(id: Int) {
        retained.remove(id)?.values?.forEach { (it as? AutoCloseable)?.close() }
    }
}

private val LocalEntryId = staticCompositionLocalOf { -1 }

/**
 * Like `remember`, but survives the screen being covered by a pushed screen,
 * and is released when the screen itself is popped.
 */
@Suppress("UNCHECKED_CAST")
@Composable
fun <T> rememberRetained(key: String, init: () -> T): T {
    val navigator = LocalNavigator.current
    val id = LocalEntryId.current
    return remember(id, key) {
        val bucket = navigator.retained.getOrPut(id) { mutableMapOf() }
        if (bucket.containsKey(key)) bucket[key] as T else init().also { bucket[key] = it }
    }
}

val LocalNavigator = staticCompositionLocalOf<Navigator> { error("No navigator") }

/**
 * Renders the top of a stack with a push/pop slide and keeps every screen
 * below it alive, so coming back restores its scroll position and state.
 */
@Composable
fun NavStack(navigator: Navigator, enabled: Boolean = true, content: @Composable (Route) -> Unit) {
    val holder = rememberSaveableStateHolder()
    BackHandler(enabled = enabled && navigator.depth > 1) { navigator.pop() }
    AnimatedContent(
        targetState = navigator.topEntry,
        transitionSpec = {
            val duration = 320
            if (navigator.lastWasPop) {
                (slideInHorizontally(tween(duration)) { -it / 3 } + fadeIn(tween(duration))) togetherWith
                    slideOutHorizontally(tween(duration)) { it }
            } else {
                slideInHorizontally(tween(duration)) { it } togetherWith
                    (slideOutHorizontally(tween(duration)) { -it / 3 } + fadeOut(tween(duration)))
            }
        },
        modifier = Modifier.fillMaxSize(),
        label = "nav",
    ) { entry ->
        holder.SaveableStateProvider(entry.id) {
            CompositionLocalProvider(LocalNavigator provides navigator, LocalEntryId provides entry.id) {
                Box(Modifier.fillMaxSize()) { content(entry.route) }
            }
        }
    }
}

/** A screen's retained state with a coroutine scope that ends when the screen is popped. */
abstract class ScreenModel : AutoCloseable {
    val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.Main.immediate)

    override fun close() {
        scope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
    }
}
