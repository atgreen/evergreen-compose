/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import android.app.Activity
import android.app.Application
import android.content.Context
import android.graphics.PixelFormat
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import androidx.activity.OnBackPressedDispatcher
import androidx.activity.OnBackPressedDispatcherOwner
import androidx.activity.setViewTreeOnBackPressedDispatcherOwner
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.platform.ComposeView
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner

/** Shared controller: every UI operation is asynchronous on Android's main thread. */
class ComposeHost(context: Context) : LifecycleOwner, SavedStateRegistryOwner,
    ViewModelStoreOwner, OnBackPressedDispatcherOwner, Application.ActivityLifecycleCallbacks {
    private val activity = context as Activity
    private val services = AppServices(context)
    fun readState(): String? = services.readState()
    fun writeState(text: String) = services.writeState(text)
    fun request(id: Int, url: String, kind: String) = services.request(id, url, kind)
    fun pollService(): String? = services.poll()
    fun openUrl(url: String) {
        val uri = android.net.Uri.parse(url)
        require(uri.scheme in listOf("https", "http"))
        main.post {
            try { activity.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, uri)) }
            catch (e: android.content.ActivityNotFoundException) { android.util.Log.w("EvergreenCompose", "No browser", e) }
        }
    }
    private val main = Handler(Looper.getMainLooper())
    override val lifecycle = LifecycleRegistry(this)
    override val onBackPressedDispatcher = OnBackPressedDispatcher { activity.onBackPressed() }
    override val viewModelStore = ViewModelStore()
    private val saved = SavedStateRegistryController.create(this)
    override val savedStateRegistry: SavedStateRegistry get() = saved.savedStateRegistry
    private var view: ComposeView? = null
    private val content = mutableStateOf<Snapshot?>(null)
    private val events = java.util.ArrayDeque<String>()
    private var sequence = 0L
    private var pending: Snapshot? = null
    private val decoder = SnapshotDecoder()
    private var scheduled = false
    @Volatile private var closed = false
    @Volatile private var failure: String? = null
    private fun post(action: () -> Unit) {
        main.post { if (!closed) try { action() } catch (e: Exception) {
            failure = e.toString(); android.util.Log.e("EvergreenCompose", "UI failure", e)
        } }
    }
    fun publish(text: String) {
        synchronized(this) {
            if (closed) return
            pending = decoder.read(text) // Worker-side parse/model update; no per-frame Lisp calls.
            if (scheduled) return
            scheduled = true
        }
        post {
            synchronized(this) { content.value = pending; pending = null; scheduled = false }
            // NativeActivity hides status bars for graphics demos. Normal apps
            // restore them and derive their appearance from the root theme.
            val dark = content.value?.tree?.flag("dark") ?: false
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            activity.window.statusBarColor = if (dark) 0xff1c1b1f.toInt() else 0xfffffbfe.toInt()
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                activity.window.insetsController?.show(WindowInsets.Type.statusBars())
                activity.window.insetsController?.setSystemBarsAppearance(
                    if (dark) 0 else WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS,
                    WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS)
            } else {
                activity.window.decorView.systemUiVisibility = if (dark) 0 else View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            }

            if (view == null) {
                saved.performAttach(); saved.performRestore(null)
                lifecycle.currentState = Lifecycle.State.RESUMED
                activity.application.registerActivityLifecycleCallbacks(this)
                val root = ComposeView(activity).apply {
                    // Clearing an editor's focus needs a neutral destination.
                    // Otherwise Android can refocus it and reopen search/IME.
                    isFocusableInTouchMode = true
                }
                root.setViewTreeLifecycleOwner(this)
                root.setViewTreeSavedStateRegistryOwner(this)
                root.setViewTreeViewModelStoreOwner(this)
                root.setViewTreeOnBackPressedDispatcherOwner(this)
                root.setContent {
                    Box(Modifier.fillMaxSize().onPreviewKeyEvent { event ->
                        val native = event.nativeKeyEvent
                        if (native.keyCode == android.view.KeyEvent.KEYCODE_BACK && onBackPressedDispatcher.hasEnabledCallbacks()) {
                            if (native.action == android.view.KeyEvent.ACTION_UP && !native.isCanceled)
                                onBackPressedDispatcher.onBackPressed()
                            true
                        } else false
                    }) {
                        MaterialTheme {
                            content.value?.let { snapshot -> Render(snapshot.tree, snapshot.ack, ::emit) }
                        }
                    }
                }
                val params = WindowManager.LayoutParams(-1, -1,
                    WindowManager.LayoutParams.TYPE_APPLICATION_PANEL,
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED, PixelFormat.OPAQUE)
                params.gravity = Gravity.TOP or Gravity.LEFT
                params.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
                activity.windowManager.addView(root, params)
                if (android.os.Build.VERSION.SDK_INT >= 33)
                    root.findOnBackInvokedDispatcher()?.let { onBackPressedDispatcher.setOnBackInvokedDispatcher(it) }
                view = root
                android.util.Log.i("EvergreenCompose", "mounted " + activity.packageName)
            }
        }
    }
    @Synchronized private fun emit(id: String, kind: String, value: String): Long {
        if (closed) return sequence
        sequence++
        fun quoted(s: String) = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
        events.addLast("($sequence ${quoted(id)} ${quoted(kind)} ${quoted(value)})")
        return sequence
    }
    fun getFailure(): String? = failure
    @Synchronized fun pollEvent(): String? = events.pollFirst()
    fun close() {
        synchronized(this) { closed = true; pending = null; events.clear() }
        services.close()
        main.post {
            activity.application.unregisterActivityLifecycleCallbacks(this)
            if (view != null) {
                lifecycle.currentState = Lifecycle.State.DESTROYED
                view!!.disposeComposition()
                if (view!!.isAttachedToWindow) activity.windowManager.removeView(view)
                view = null; viewModelStore.clear()
            }
        }
    }
    override fun onActivityResumed(a: Activity) { if (a === activity && view != null) lifecycle.currentState = Lifecycle.State.RESUMED }
    override fun onActivityPaused(a: Activity) { if (a === activity && view != null) lifecycle.currentState = Lifecycle.State.STARTED }
    override fun onActivityStopped(a: Activity) { if (a === activity && view != null) lifecycle.currentState = Lifecycle.State.CREATED }
    override fun onActivityDestroyed(a: Activity) { if (a === activity) close() }
    override fun onActivityCreated(a: Activity, state: Bundle?) {}
    override fun onActivityStarted(a: Activity) {}
    override fun onActivitySaveInstanceState(a: Activity, state: Bundle) {}
}
