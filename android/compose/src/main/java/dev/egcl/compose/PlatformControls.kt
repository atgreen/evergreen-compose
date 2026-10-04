/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import android.Manifest
import android.app.Activity
import android.app.Fragment
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.camera2.Camera2Config
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.annotations.MarkerOptions
import java.io.File

/** Plain NativeActivity has no ActivityResultRegistry. A shared, headless Android
 * fragment receives platform results without an application-specific Activity. */
@Suppress("DEPRECATION")
class ResultFragment : Fragment() {
    private var next = 1
    private val results = mutableMapOf<Int, (Int, Intent?) -> Unit>()
    private val permissions = mutableMapOf<Int, (Boolean) -> Unit>()
    fun launch(intent: Intent, result: (Int, Intent?) -> Unit) {
        val code = next++
        results[code] = result
        try { startActivityForResult(intent, code) } catch (e: Exception) { results.remove(code); throw e }
    }
    fun cameraPermission(result: (Boolean) -> Unit) {
        val code = next++
        permissions[code] = result
        requestPermissions(arrayOf(Manifest.permission.CAMERA), code)
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        results.remove(requestCode)?.invoke(resultCode, data)
    }
    override fun onRequestPermissionsResult(requestCode: Int, names: Array<out String>, grants: IntArray) {
        permissions.remove(requestCode)?.invoke(grants.isNotEmpty() && grants.all { it == PackageManager.PERMISSION_GRANTED })
    }
    override fun onDestroy() { results.clear(); permissions.clear(); super.onDestroy() }
    companion object {
        fun of(activity: Activity): ResultFragment {
            val manager = activity.fragmentManager
            return manager.findFragmentByTag("eg-compose/results") as? ResultFragment ?: ResultFragment().also {
                manager.beginTransaction().add(it, "eg-compose/results").commit()
                manager.executePendingTransactions()
            }
        }
    }
}

@Composable
internal fun PlatformControl(n: Node, ack: Long, emit: Emit, m: Modifier) {
    when (n.type) {
        "photo-picker", "document-picker" -> {
            val activity = LocalContext.current as Activity
            var busy by remember { mutableStateOf(false) }
            var alive by remember { mutableStateOf(true) }
            val latestEmit by rememberUpdatedState(emit)
            DisposableEffect(Unit) { onDispose { alive = false } }
            Button({
                try {
                    val intent = if (n.type == "photo-picker") ActivityResultContracts.PickVisualMedia().createIntent(activity,
                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    else Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(n.text("mime", "*/*"))
                    busy = true
                    ResultFragment.of(activity).launch(intent) { result, data ->
                        if (alive) {
                            busy = false
                            val uri = data?.data
                            if (result == Activity.RESULT_OK && uri != null) {
                                // A grant may be transient (photo picker/provider dependent).
                                try { activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                                catch (_: SecurityException) { }
                                latestEmit(n.id, "result", uri.toString())
                            } else latestEmit(n.id, "dismiss", "")
                        }
                    }
                } catch (e: Exception) { busy = false; latestEmit(n.id, "error", e.message ?: "Picker unavailable") }
            }, m, enabled = n.flag("enabled", true) && !busy) {
                Text(n.text("text", if (n.type == "photo-picker") "Choose photo" else "Choose document"))
            }
        }
        "web-view" -> WebContent(n, emit, m)
        "media-player" -> Media(n, emit, m)
        "map" -> MapContent(n, emit, m)
        "camera" -> Camera(n, emit, m)
        else -> error("Unknown Evergreen Compose component: ${n.type}")
    }
}

@Composable
private fun WebContent(n: Node, emit: Emit, m: Modifier) {
    val context = LocalContext.current
    val latest by rememberUpdatedState(emit)
    val view = remember { WebView(context).apply {
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) { latest(n.id, "load", url ?: "") }
            override fun onReceivedError(view: WebView?, request: android.webkit.WebResourceRequest?, error: android.webkit.WebResourceError?) {
                if (request?.isForMainFrame == true) latest(n.id, "error", error?.description?.toString() ?: "Page failed")
            }
        }
    } }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(view, owner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE) view.onPause()
            if (event == Lifecycle.Event.ON_RESUME) view.onResume()
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer); view.stopLoading(); view.destroy() }
    }
    LaunchedEffect(n.text("url"), n.text("html"), n.flag("javascript")) {
        view.settings.javaScriptEnabled = n.flag("javascript")
        if (n.props.has("html")) view.loadDataWithBaseURL(null, n.text("html"), "text/html", "UTF-8", null)
        else if (Uri.parse(n.text("url")).scheme in listOf("https", "http")) view.loadUrl(n.text("url"))
        else latest(n.id, "error", "WebView URL must use HTTPS or HTTP")
    }
    AndroidView({ view }, m.heightIn(min = 180.dp))
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@Composable
private fun Media(n: Node, emit: Emit, m: Modifier) {
    val context = LocalContext.current
    val latest by rememberUpdatedState(emit)
    val player = remember { ExoPlayer.Builder(context).build() }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(player, owner) {
        val listener = object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) { latest(n.id, "error", error.message ?: "Playback failed") }
            override fun onPlaybackStateChanged(state: Int) { if (state == Player.STATE_READY) latest(n.id, "load", "ready") }
        }
        player.addListener(listener)
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_PAUSE) player.pause() }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer); player.removeListener(listener); player.release() }
    }
    LaunchedEffect(n.text("source")) {
        if (n.text("source").isNotEmpty()) { player.setMediaItem(MediaItem.fromUri(n.text("source"))); player.prepare() }
    }
    LaunchedEffect(n.flag("playing"), n.flag("loop")) { player.playWhenReady = n.flag("playing"); player.repeatMode = if (n.flag("loop")) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF }
    AndroidView({ PlayerView(it).apply { this.player = player } }, m.heightIn(min = 180.dp), update = {
        it.useController = n.flag("controls", true)
    })
}

@Composable
private fun MapContent(n: Node, emit: Emit, m: Modifier) {
    val context = LocalContext.current
    val latest by rememberUpdatedState(n)
    val latestEmit by rememberUpdatedState(emit)
    val owner = LocalLifecycleOwner.current
    val view = remember { MapLibre.getInstance(context); MapView(context).apply { onCreate(null) } }
    var map by remember { mutableStateOf<MapLibreMap?>(null) }
    DisposableEffect(view, owner) {
        val observer = LifecycleEventObserver { _, event -> when (event) {
            Lifecycle.Event.ON_START -> view.onStart()
            Lifecycle.Event.ON_RESUME -> view.onResume()
            Lifecycle.Event.ON_PAUSE -> view.onPause()
            Lifecycle.Event.ON_STOP -> view.onStop()
            else -> Unit
        } }
        owner.lifecycle.addObserver(observer)
        if (owner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) view.onStart()
        if (owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) view.onResume()
        view.getMapAsync { map = it }
        val error = MapView.OnDidFailLoadingMapListener { message -> latestEmit(latest.id, "error", message) }
        view.addOnDidFailLoadingMapListener(error)
        onDispose { owner.lifecycle.removeObserver(observer); view.removeOnDidFailLoadingMapListener(error); view.onPause(); view.onStop(); view.onDestroy() }
    }
    LaunchedEffect(map, n.text("style")) {
        val style = n.text("style", "https://demotiles.maplibre.org/style.json")
        val builder = org.maplibre.android.maps.Style.Builder()
        if (style.trimStart().startsWith("{")) builder.fromJson(style) else builder.fromUri(style)
        map?.setStyle(builder) { latestEmit(latest.id, "load", "ready") }
    }
    LaunchedEffect(map, n.number("latitude"), n.number("longitude"), n.number("zoom", 2)) {
        map?.cameraPosition = CameraPosition.Builder().target(LatLng(n.number("latitude") / 1_000_000.0,
            n.number("longitude") / 1_000_000.0)).zoom(n.number("zoom", 2).toDouble()).build()
    }
    LaunchedEffect(map, n.children) {
        map?.let { target ->
            target.clear()
            val ids = mutableMapOf<Long, String>()
            n.children.forEach { child ->
                val marker = target.addMarker(MarkerOptions().position(LatLng(child.number("latitude") / 1_000_000.0,
                    child.number("longitude") / 1_000_000.0)).title(child.text("text")))
                ids[marker.id] = child.text("value", child.id)
            }
            target.setOnMarkerClickListener { marker -> ids[marker.id]?.let { latestEmit(latest.id, "select", it) }; false }
        }
    }
    AndroidView({ view }, m.heightIn(min = 200.dp))
}

@Composable
private fun Camera(n: Node, emit: Emit, m: Modifier) {
    val activity = LocalContext.current as Activity
    val owner = LocalLifecycleOwner.current
    val latestEmit by rememberUpdatedState(emit)
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    var active by remember { mutableStateOf(n.flag("active")) }
    val requestedByApp by rememberUpdatedState(n.flag("active"))
    LaunchedEffect(n.flag("active")) { active = n.flag("active") }
    var capture by remember { mutableStateOf<ImageCapture?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    val previewView = remember { PreviewView(activity).apply { implementationMode = PreviewView.ImplementationMode.COMPATIBLE } }
    val executor = ContextCompat.getMainExecutor(activity)
    var alive by remember { mutableStateOf(true) }
    DisposableEffect(Unit) { onDispose { alive = false } }
    DisposableEffect(granted, active, n.text("lens"), owner) {
        var provider: ProcessCameraProvider? = null
        var preview: Preview? = null
        var image: ImageCapture? = null
        var disposed = false
        if (granted && active) {
            try { ProcessCameraProvider.configureInstance(Camera2Config.defaultConfig()) } catch (_: IllegalStateException) { }
            val future = ProcessCameraProvider.getInstance(activity)
            future.addListener({
                if (!disposed) try {
                    provider = future.get()
                    preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
                    image = ImageCapture.Builder().build()
                    provider!!.bindToLifecycle(owner, if (n.text("lens") == "front") CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA,
                        preview, image)
                    capture = image; failure = null
                } catch (e: Exception) { failure = e.message; latestEmit(n.id, "error", e.message ?: "Camera unavailable") }
            }, executor)
        }
        onDispose { disposed = true; capture = null; provider?.let { p -> preview?.let { p.unbind(it) }; image?.let { p.unbind(it) } } }
    }
    Column(m) {
        if (!active || !granted) Button({
            if (granted) active = true
            else {
                val requestSource = requestedByApp
                ResultFragment.of(activity).cameraPermission { allowed -> if (alive) {
                    granted = allowed
                    // A newer app command takes precedence over this button's request.
                    val intended = if (requestedByApp != requestSource) requestedByApp else true
                    active = allowed && intended
                    if (!allowed) latestEmit(n.id, "error", "Camera permission denied")
                } }
            }
        }, Modifier.testTag("${n.id}/start"), n.flag("enabled", true)) { Text("Start camera") }
        else {
            AndroidView({ previewView }, Modifier.fillMaxWidth().height(n.number("preview-height", 240).dp))
            Button({
                val file = File.createTempFile("capture-", ".jpg", activity.cacheDir)
                capture?.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(), executor,
                    object : ImageCapture.OnImageSavedCallback {
                        override fun onImageSaved(result: ImageCapture.OutputFileResults) { if (alive) latestEmit(n.id, "capture", Uri.fromFile(file).toString()) }
                        override fun onError(error: ImageCaptureException) { file.delete(); if (alive) latestEmit(n.id, "error", error.message ?: "Capture failed") }
                    })
            }, Modifier.testTag("${n.id}/capture"), capture != null && n.flag("enabled", true)) { Text("Take photo") }
            failure?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }
}
