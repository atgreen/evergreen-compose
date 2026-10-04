/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import android.graphics.Typeface
import android.text.Editable
import android.text.Spanned
import android.text.TextWatcher
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import android.widget.EditText
import android.widget.TextView
import androidx.core.text.HtmlCompat
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import coil.compose.SubcomposeAsyncImage
import coil.compose.SubcomposeAsyncImageContent
import coil.request.ImageRequest
import io.noties.markwon.Markwon

@Composable
internal fun ContentControl(n: Node, ack: Long, emit: Emit, m: Modifier) {
    when (n.type) {
        "async-image", "zoom-image" -> {
            val context = LocalContext.current
            val latestEmit by rememberUpdatedState(emit)
            val source = n.text("source", if (n.props.has("asset")) "file:///android_asset/${n.text("asset")}" else "")
            var scale by remember(source) { mutableFloatStateOf(1f) }
            var pan by remember(source) { mutableStateOf(Offset.Zero) }
            val transform = rememberTransformableState { zoom, move, _ ->
                scale = (scale * zoom).coerceIn(1f, n.number("max-zoom", 5).coerceAtLeast(1).toFloat())
                pan = if (scale == 1f) Offset.Zero else pan + move
            }
            Box(m.clipToBounds().then(if (n.type == "zoom-image") Modifier.transformable(transform, enabled = n.flag("enabled", true)) else Modifier)) {
                SubcomposeAsyncImage(model = ImageRequest.Builder(context).data(source).crossfade(true).build(),
                    contentDescription = n.text("description").ifEmpty { null },
                    modifier = Modifier.fillMaxSize().graphicsLayer { scaleX = scale; scaleY = scale; translationX = pan.x; translationY = pan.y },
                    contentScale = if (n.text("scale") == "crop") ContentScale.Crop else ContentScale.Fit,
                    loading = { Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() } },
                    error = { Text(n.text("error-text", "Image unavailable")) },
                    success = { SubcomposeAsyncImageContent() },
                    onSuccess = { latestEmit(n.id, "load", source) },
                    onError = { latestEmit(n.id, "error", it.result.throwable.message ?: "Image unavailable") })
            }
        }
        "markdown" -> {
            val context = LocalContext.current
            val markwon = remember(context) { Markwon.create(context) }
            val color = LocalContentColor.current.toArgb()
            AndroidView(factory = { TextView(it).apply { textSize = 16f; setTextIsSelectable(true) } }, modifier = m,
                update = { view -> view.setTextColor(color); if (view.tag != n.text("text")) { markwon.setMarkdown(view, n.text("text")); view.tag = n.text("text") } })
        }
        "rich-text-editor" -> RichEditor(n, ack, emit, m)
        else -> PlatformControl(n, ack, emit, m)
    }
}

@Composable
private fun RichEditor(n: Node, ack: Long, emit: Emit, m: Modifier) {
    val context = LocalContext.current
    val latestEmit by rememberUpdatedState(emit)
    val value = localValue(n.text("value"), ack)
    var updating by remember { mutableStateOf(false) }
    val editor = remember(context) { EditText(context).apply { gravity = android.view.Gravity.TOP; minLines = 4; textSize = 16f } }
    val color = LocalContentColor.current.toArgb()
    fun publish() {
        if (!updating) {
            val html = HtmlCompat.toHtml(editor.text, HtmlCompat.TO_HTML_PARAGRAPH_LINES_INDIVIDUAL)
            value.edit(html, latestEmit(n.id, "change", html))
        }
    }
    DisposableEffect(editor) {
        val watcher = object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) { publish() }
        }
        editor.addTextChangedListener(watcher)
        onDispose { editor.removeTextChangedListener(watcher) }
    }
    Column(m) {
        Row {
            listOf("Bold", "Italic", "Underline").forEach { name ->
                TextButton({
                    val start = minOf(editor.selectionStart, editor.selectionEnd).coerceAtLeast(0)
                    val end = maxOf(editor.selectionStart, editor.selectionEnd).coerceAtLeast(start)
                    if (end > start) {
                        val text = editor.text
                        if (name == "Underline") {
                            val spans = text.getSpans(start, end, UnderlineSpan::class.java)
                            if (spans.isEmpty()) text.setSpan(UnderlineSpan(), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                            else spans.forEach { text.removeSpan(it) }
                        } else {
                            val style = if (name == "Bold") Typeface.BOLD else Typeface.ITALIC
                            val spans = text.getSpans(start, end, StyleSpan::class.java).filter { it.style == style }
                            if (spans.isEmpty()) text.setSpan(StyleSpan(style), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                            else spans.forEach { text.removeSpan(it) }
                        }
                        publish()
                    }
                }, Modifier.testTag("${n.id}/${name.lowercase()}"), n.flag("enabled", true)) { Text(name) }
            }
        }
        AndroidView(factory = { editor }, modifier = Modifier.fillMaxWidth().testTag("${n.id}/input"), update = {
            it.setTextColor(color); it.isEnabled = n.flag("enabled", true)
            if (ack >= value.sequence && it.tag != value.value) {
                val parsed = HtmlCompat.fromHtml(value.value, HtmlCompat.FROM_HTML_MODE_COMPACT)
                if (HtmlCompat.toHtml(it.text, HtmlCompat.TO_HTML_PARAGRAPH_LINES_INDIVIDUAL) != value.value) {
                    updating = true
                    val cursor = it.selectionStart.coerceAtLeast(0)
                    it.setText(parsed); it.setSelection(cursor.coerceAtMost(it.length()))
                    updating = false
                }
                it.tag = value.value
            }
        })
    }
}
