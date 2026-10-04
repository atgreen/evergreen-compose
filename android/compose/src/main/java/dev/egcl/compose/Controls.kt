/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.*
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
internal fun ControlIcon(n: Node) {
    if (!n.props.has("icon") && n.type != "icon") { Text(n.text("text")); return }
    val vector = when (n.text("icon", "info")) {
        "add" -> Icons.Default.Add
        "close" -> Icons.Default.Close
        "menu" -> Icons.Default.Menu
        "search" -> Icons.Default.Search
        "home" -> Icons.Default.Home
        "favorite" -> Icons.Default.Favorite
        "settings" -> Icons.Default.Settings
        "check" -> Icons.Default.Check
        "delete" -> Icons.Default.Delete
        "edit" -> Icons.Default.Edit
        "back" -> Icons.AutoMirrored.Filled.ArrowBack
        "more" -> Icons.Default.MoreVert
        "person" -> Icons.Default.Person
        "star" -> Icons.Default.Star
        "next" -> Icons.AutoMirrored.Filled.KeyboardArrowRight
        "down" -> Icons.Default.KeyboardArrowDown
        "info" -> Icons.Default.Info
        else -> {
            if (n.type == "nav-item") { Text(n.text("icon")); return }
            error("Unknown Evergreen Compose icon: ${n.text("icon")}")
        }
    }
    Icon(vector, n.text("description").ifEmpty { null },
        tint = if (n.props.has("color")) colour(n.text("color")) else LocalContentColor.current)
}

@Composable
internal fun Children(n: Node, ack: Long, emit: Emit) {
    n.children.forEach { key(it.id, it.type) { Render(it, ack, emit) } }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RenderControl(n: Node, ack: Long, emit: Emit, m: Modifier) {
    val enabled = n.flag("enabled", true)
    val click = { if (enabled) emit(n.id, "click", ""); Unit }
    when (n.type) {
        "text-button" -> TextButton(click, m, enabled = enabled) { Text(n.text("text")); Children(n, ack, emit) }
        "tonal-button" -> FilledTonalButton(click, m, enabled = enabled) { Text(n.text("text")); Children(n, ack, emit) }
        "icon-toggle-button" -> BooleanControl(n, ack, emit, m)
        "assist-chip" -> AssistChip(click, { Text(n.text("text")) }, m, enabled = enabled)
        "input-chip" -> InputChip(n.flag("selected"), click, { Text(n.text("text")) }, m, enabled = enabled,
            trailingIcon = if (n.flag("on-dismiss")) { { IconButton({ emit(n.id, "dismiss", "") }, enabled = enabled,
                modifier = Modifier.size(32.dp).testTag("${n.id}/remove")) { Icon(Icons.Default.Close, "Remove ${n.text("text")}") } } } else null)
        "tri-state-checkbox" -> TriStateCheckbox(when (n.text("state", "off")) {
            "on" -> ToggleableState.On; "mixed" -> ToggleableState.Indeterminate
            "off" -> ToggleableState.Off; else -> error("Checkbox state must be on, off or mixed")
        }, click, m, enabled)
        "radio-button" -> RadioButton(n.flag("selected"), click, m, enabled)
        "slider", "range-slider" -> NumericSlider(n, ack, emit, m)
        "icon" -> Box(m) { ControlIcon(n) }
        "image" -> AssetImage(n, emit, m)
        "badge" -> BadgedBox(badge = { Badge { Text(n.text("text")) } }, modifier = m) { Children(n, ack, emit) }
        "linear-progress" -> if (n.props.has("value")) LinearProgressIndicator(n.number("value").coerceIn(0, 100) / 100f, m) else LinearProgressIndicator(m)
        "circular-progress" -> if (n.props.has("value")) CircularProgressIndicator(n.number("value").coerceIn(0, 100) / 100f, m) else CircularProgressIndicator(m)
        "list-item" -> ListItem(headlineContent = { Text(n.text("text")) }, modifier = m,
            supportingContent = if (n.props.has("supporting")) { { Text(n.text("supporting")) } } else null,
            overlineContent = if (n.props.has("overline")) { { Text(n.text("overline")) } } else null,
            leadingContent = if (n.props.has("icon")) { { ControlIcon(n) } } else null,
            trailingContent = if (n.children.isNotEmpty()) { { Children(n, ack, emit) } } else null)
        "tooltip" -> TooltipBox(positionProvider = TooltipDefaults.rememberPlainTooltipPositionProvider(),
            tooltip = { PlainTooltip { Text(n.text("text")) } }, state = rememberTooltipState(), modifier = m) { Children(n, ack, emit) }
        "snackbar" -> Snackbar(m,
            action = if (n.flag("on-action")) { { TextButton({ emit(n.id, "action", "") }, enabled = enabled) { Text(n.text("action-label", "Undo")) } } } else null,
            dismissAction = if (n.flag("on-dismiss")) { { IconButton({ emit(n.id, "dismiss", "") }) { Icon(Icons.Default.Close, "Dismiss") } } } else null
        ) { Text(n.text("text")) }
        "alert-dialog" -> AlertDialog(onDismissRequest = { emit(n.id, "dismiss", "") }, modifier = m,
            title = { Text(n.text("title")) }, text = { Column { Text(n.text("text")); Children(n, ack, emit) } },
            confirmButton = { TextButton({ emit(n.id, "confirm", "") }, enabled = enabled) { Text(n.text("confirm-label", "OK")) } },
            dismissButton = if (n.flag("on-dismiss")) { { TextButton({ emit(n.id, "dismiss", "") }) { Text(n.text("dismiss-label", "Cancel")) } } } else null)
        "date-picker", "date-range-picker", "time-picker" -> Picker(n, ack, emit, m)
        "lazy-grid", "horizontal-pager", "vertical-pager", "tabs", "segmented-buttons",
        "navigation-rail", "navigation-drawer", "bottom-app-bar", "dropdown-menu" -> Collection(n, ack, emit, m)
        "tab", "segment", "drawer-item", "menu-item", "nav-item" -> error("${n.type} needs its matching parent control")
        else -> ExtendedControl(n, ack, emit, m)
    }
}

@Composable
internal fun BooleanControl(n: Node, ack: Long, emit: Emit, m: Modifier) {
    var checked by remember { mutableStateOf(n.flag("checked")) }
    var lastEdit by remember { mutableLongStateOf(0) }
    LaunchedEffect(n.flag("checked"), ack) { if (ack >= lastEdit) checked = n.flag("checked") }
    val change: (Boolean) -> Unit = { checked = it; lastEdit = emit(n.id, "change", it.toString()) }
    when (n.type) {
        "switch" -> Switch(checked, change, m, enabled = n.flag("enabled", true))
        "checkbox" -> Checkbox(checked, change, m, enabled = n.flag("enabled", true))
        else -> IconToggleButton(checked, change, m, enabled = n.flag("enabled", true)) { ControlIcon(n) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun Editor(n: Node, ack: Long, emit: Emit, modifier: Modifier) {
    var field by remember { mutableStateOf(TextFieldValue(n.text("value"))) }
    var lastEdit by remember { mutableLongStateOf(0) }
    LaunchedEffect(n.text("value"), ack) {
        val value = n.text("value")
        if (ack >= lastEdit && field.text != value) field = TextFieldValue(value, TextRange(value.length))
    }
    val edit: (TextFieldValue) -> Unit = { field = it; lastEdit = emit(n.id, "change", it.text) }
    val label: @Composable () -> Unit = { Text(n.text("label")) }
    val enabled = n.flag("enabled", true)
    if (n.type == "search-bar") {
        var active by remember { mutableStateOf(false) }
        val focus = androidx.compose.ui.platform.LocalFocusManager.current
        fun setActive(value: Boolean) {
            active = value && n.children.isNotEmpty()
            if (!value) focus.clearFocus()
        }
        DockedSearchBar(query = field.text, onQueryChange = { edit(TextFieldValue(it)) },
            onSearch = { emit(n.id, "submit", it); setActive(false) }, active = active,
            onActiveChange = ::setActive, modifier = modifier,
            enabled = enabled, placeholder = label, leadingIcon = { Icon(Icons.Default.Search, null) }
        ) { Children(n, ack, emit) }
    } else {
        val keyboard = KeyboardOptions(keyboardType = when (n.text("keyboard")) {
            "number" -> KeyboardType.Number; "email" -> KeyboardType.Email
            "phone" -> KeyboardType.Phone; "password" -> KeyboardType.Password
            else -> KeyboardType.Text
        }, imeAction = if (n.flag("on-submit")) ImeAction.Done else ImeAction.Default)
        val transform = if (n.flag("password")) PasswordVisualTransformation() else VisualTransformation.None
        val actions = KeyboardActions(onDone = { emit(n.id, "submit", field.text) })
        val supporting: (@Composable () -> Unit)? = if (n.props.has("supporting")) { { Text(n.text("supporting")) } } else null
        if (n.type == "filled-text-field") TextField(field, edit, modifier, enabled = enabled,
            readOnly = n.flag("read-only"), label = label, singleLine = n.flag("single-line", true),
            isError = n.flag("error"), supportingText = supporting, visualTransformation = transform,
            keyboardOptions = keyboard, keyboardActions = actions)
        else OutlinedTextField(field, edit, modifier, enabled = enabled,
            readOnly = n.flag("read-only"), label = label, singleLine = n.flag("single-line", true),
            isError = n.flag("error"), supportingText = supporting, visualTransformation = transform,
            keyboardOptions = keyboard, keyboardActions = actions)
    }
}

@Composable
private fun AssetImage(n: Node, emit: Emit, m: Modifier) {
    val context = LocalContext.current
    val asset = n.text("asset")
    val result by produceState<Result<android.graphics.Bitmap>?>(null, asset) {
        value = withContext(Dispatchers.IO) { runCatching {
            require(asset.isNotEmpty() && '/' !in asset && '\\' !in asset) { "Images use flat APK asset names" }
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.assets.open(asset).use { BitmapFactory.decodeStream(it, null, bounds) }
            require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Unsupported image: $asset" }
            val options = BitmapFactory.Options().apply {
                inSampleSize = 1
                while (bounds.outWidth / inSampleSize > 2048 || bounds.outHeight / inSampleSize > 2048) inSampleSize *= 2
            }
            requireNotNull(context.assets.open(asset).use { BitmapFactory.decodeStream(it, null, options) })
        } }
    }
    LaunchedEffect(result) { result?.exceptionOrNull()?.let { emit(n.id, "error", it.message ?: "Image unavailable") } }
    val bitmap = result?.getOrNull()
    if (bitmap != null) Image(bitmap.asImageBitmap(), n.text("description").ifEmpty { null }, m,
        contentScale = when (n.text("scale")) { "crop" -> ContentScale.Crop; "fill" -> ContentScale.FillBounds; else -> ContentScale.Fit })
    else Box(m) { if (result?.isFailure == true) Text("Image unavailable") }
}
