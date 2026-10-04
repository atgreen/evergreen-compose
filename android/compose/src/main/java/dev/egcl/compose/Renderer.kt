/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import org.json.JSONObject

internal data class Node(val type: String, val id: String, val props: JSONObject, val children: List<Node>) {
    fun text(key: String, default: String = "") = props.optString(key, default)
    fun flag(key: String, default: Boolean = false) = props.optBoolean(key, default)
    fun number(key: String, default: Int = 0) = props.optInt(key, default)
    companion object {
        fun read(json: JSONObject): Node {
            val children = json.getJSONArray("children")
            return Node(json.getString("type"), json.getString("id"), json.getJSONObject("props"),
                List(children.length()) { read(children.getJSONObject(it)) })
        }
    }
}
internal data class Snapshot(val tree: Node, val ack: Long) {
    companion object {
        fun read(text: String): Snapshot {
            val json = JSONObject(text)
            require(json.getInt("protocol") == 1) { "Unsupported Evergreen Compose protocol" }
            return Snapshot(Node.read(json.getJSONObject("tree")), json.getLong("ack"))
        }
    }
}
internal typealias Emit = (String, String, String) -> Long

@Composable
internal fun colour(name: String): Color = when (name) {
    "primary" -> MaterialTheme.colorScheme.primary
    "on-primary" -> MaterialTheme.colorScheme.onPrimary
    "secondary" -> MaterialTheme.colorScheme.secondary
    "secondary-container" -> MaterialTheme.colorScheme.secondaryContainer
    "on-secondary-container" -> MaterialTheme.colorScheme.onSecondaryContainer
    "tertiary" -> MaterialTheme.colorScheme.tertiary
    "background" -> MaterialTheme.colorScheme.background
    "on-background" -> MaterialTheme.colorScheme.onBackground
    "outline" -> MaterialTheme.colorScheme.outline
    "surface" -> MaterialTheme.colorScheme.surface
    "surface-variant" -> MaterialTheme.colorScheme.surfaceVariant
    "on-surface" -> MaterialTheme.colorScheme.onSurface
    "muted" -> MaterialTheme.colorScheme.onSurfaceVariant
    "error" -> MaterialTheme.colorScheme.error
    "error-container" -> MaterialTheme.colorScheme.errorContainer
    "primary-container" -> MaterialTheme.colorScheme.primaryContainer
    "on-primary-container" -> MaterialTheme.colorScheme.onPrimaryContainer
    "", "none" -> Color.Unspecified
    else -> Color(android.graphics.Color.parseColor(name))
}

@Composable
private fun appColorScheme(n: Node): ColorScheme {
    val context = LocalContext.current
    val defaults = if (n.flag("dynamic-color") && android.os.Build.VERSION.SDK_INT >= 31) {
        if (n.flag("dark")) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    } else if (n.flag("dark")) darkColorScheme() else lightColorScheme()
    fun override(name: String, fallback: Color) =
        if (n.props.has(name)) Color(android.graphics.Color.parseColor(n.text(name))) else fallback
    return defaults.copy(
        primary = override("primary", defaults.primary), onPrimary = override("on-primary", defaults.onPrimary),
        primaryContainer = override("primary-container", defaults.primaryContainer),
        onPrimaryContainer = override("on-primary-container", defaults.onPrimaryContainer),
        secondary = override("secondary", defaults.secondary),
        secondaryContainer = override("secondary-container", defaults.secondaryContainer),
        onSecondaryContainer = override("on-secondary-container", defaults.onSecondaryContainer),
        surface = override("surface", defaults.surface), onSurface = override("on-surface", defaults.onSurface),
        surfaceVariant = override("surface-variant", defaults.surfaceVariant),
        onSurfaceVariant = override("on-surface-variant", defaults.onSurfaceVariant),
        background = override("background", defaults.background), onBackground = override("on-background", defaults.onBackground))
}

@Composable
private fun controlledListState(n: Node): LazyListState {
    val state = rememberLazyListState()
    val target = n.text("scroll-to")
    LaunchedEffect(target) {
        val index = n.children.indexOfFirst { it.id == target }
        if (target.isNotEmpty() && index >= 0) state.scrollToItem(index)
    }
    return state
}

@Composable
internal fun Node.modifier(base: Modifier = Modifier, emit: Emit): Modifier {
    var m = base.testTag(id)
    if (flag("fill")) m = m.fillMaxSize()
    if (flag("fill-width")) m = m.fillMaxWidth()
    if (props.has("width")) m = m.width(number("width").dp)
    if (props.has("height")) m = m.height(number("height").dp)
    if (props.has("radius")) m = m.clip(RoundedCornerShape(number("radius").dp))
    if (props.has("background")) m = m.background(colour(text("background")), RoundedCornerShape(number("radius").dp))
    if (flag("on-click") && type in listOf("column", "row", "box", "text", "card", "image", "list-item"))
        m = m.clickable(enabled = flag("enabled", true)) { emit(id, "click", "") }
    if (props.has("description")) m = m.semantics { contentDescription = text("description") }
    if (props.has("padding") || props.has("padding-horizontal") || props.has("padding-vertical"))
        m = m.padding(horizontal = number("padding-horizontal", number("padding")).dp,
            vertical = number("padding-vertical", number("padding")).dp)
    return m
}

@Composable
internal fun Render(node: Node, ack: Long, emit: Emit, base: Modifier = Modifier) {
    key(node.id, node.type) { RenderNode(node, ack, emit, base) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RenderNode(n: Node, ack: Long, emit: Emit, base: Modifier) {
    if (n.flag("on-back")) androidx.activity.compose.BackHandler(enabled = n.flag("back-enabled", true)) {
        emit(n.id, "back", "")
    }
    val m = n.modifier(base, emit)
    val enabled = n.flag("enabled", true)
    val click = { if (enabled) emit(n.id, "click", ""); Unit }
    val children: @Composable () -> Unit = { n.children.forEach { key(it.id, it.type) { Render(it, ack, emit) } } }
    when (n.type) {
        "theme" -> MaterialTheme(colorScheme = appColorScheme(n)) {
            Surface(modifier = m.fillMaxSize()) { children() }
        }
        "column" -> Column(m, verticalArrangement = Arrangement.spacedBy(n.number("spacing").dp),
            horizontalAlignment = when (n.text("horizontal-alignment")) {
                "center" -> Alignment.CenterHorizontally; "end" -> Alignment.End; else -> Alignment.Start
            }) {
            n.children.forEach { child -> key(child.id, child.type) {
                Render(child, ack, emit, if (child.number("weight") > 0)
                    Modifier.weight(child.number("weight").toFloat()) else Modifier)
            } }
        }
        "row" -> Row(m, horizontalArrangement = Arrangement.spacedBy(n.number("spacing").dp),
            verticalAlignment = Alignment.CenterVertically) {
            n.children.forEach { child -> key(child.id, child.type) {
                Render(child, ack, emit, if (child.number("weight") > 0)
                    Modifier.weight(child.number("weight").toFloat()) else Modifier)
            } }
        }
        "box" -> Box(m, contentAlignment = when (n.text("alignment")) {
            "center" -> Alignment.Center; "bottom-end" -> Alignment.BottomEnd
            "bottom-start" -> Alignment.BottomStart; "top-end" -> Alignment.TopEnd
            else -> Alignment.TopStart
        }) { children() }
        "canvas" -> VectorCanvas(n, m)
        "drawing-pad" -> DrawingPad(n, ack, emit, m)
        "text" -> Text(n.text("text"), m, color = colour(n.text("color")),
            fontWeight = when (n.text("font-weight")) {
                "bold" -> FontWeight.Bold; "medium" -> FontWeight.Medium; else -> null
            },
            textAlign = when (n.text("text-align")) {
                "center" -> TextAlign.Center; "end" -> TextAlign.End; else -> TextAlign.Start
            }, maxLines = n.number("max-lines", Int.MAX_VALUE).coerceAtLeast(1), overflow = TextOverflow.Ellipsis,
            fontSize = if (n.props.has("font-size")) n.number("font-size").sp else androidx.compose.ui.unit.TextUnit.Unspecified,
            style = when (n.text("style")) {
                "title" -> MaterialTheme.typography.titleLarge
                "headline" -> MaterialTheme.typography.headlineMedium
                "label" -> MaterialTheme.typography.labelMedium
                else -> MaterialTheme.typography.bodyLarge
            })
        "button" -> Button(click, m, enabled = enabled) { Text(n.text("text")); children() }
        "outlined-button" -> OutlinedButton(click, m, enabled = enabled) { Text(n.text("text")); children() }
        "icon-button" -> IconButton(click, m, enabled = enabled) { ControlIcon(n); children() }
        "fab" -> FloatingActionButton(click, m.semantics { if (!enabled) disabled() }) { Text(n.text("text", "+")); children() }
        "chip" -> FilterChip(n.flag("selected"), click, label = { Text(n.text("text")) }, modifier = m, enabled = enabled)
        "switch", "checkbox" -> BooleanControl(n, ack, emit, m)
        "text-field", "filled-text-field", "search-bar" -> Editor(n, ack, emit, m)
        "spacer" -> Spacer(m)
        "divider" -> if (n.flag("vertical")) VerticalDivider(m) else HorizontalDivider(m)
        "card" -> Card(m, shape = RoundedCornerShape(n.number("radius", 12).dp),
            colors = if (n.props.has("container-color")) CardDefaults.cardColors(containerColor = colour(n.text("container-color")))
                     else CardDefaults.cardColors()) { children() }
        "lazy-column" -> LazyColumn(m, state = controlledListState(n), reverseLayout = n.flag("reverse-layout"), verticalArrangement = Arrangement.spacedBy(n.number("spacing").dp),
            contentPadding = PaddingValues(n.number("content-padding").dp)) {
            items(n.children, key = { it.id }, contentType = { it.type }) { Render(it, ack, emit) }
        }
        "lazy-row" -> LazyRow(m, state = controlledListState(n), reverseLayout = n.flag("reverse-layout"), horizontalArrangement = Arrangement.spacedBy(n.number("spacing").dp),
            contentPadding = PaddingValues(n.number("content-padding").dp)) {
            items(n.children, key = { it.id }, contentType = { it.type }) { Render(it, ack, emit) }
        }
        "scaffold" -> Scaffold(m.imePadding(),
            topBar = { n.children.filter { it.text("slot") == "top" }.forEach { key(it.id, it.type) { Render(it, ack, emit) } } },
            bottomBar = { n.children.filter { it.text("slot") == "bottom" }.forEach { key(it.id, it.type) { Render(it, ack, emit) } } },
            floatingActionButton = { n.children.filter { it.text("slot") == "fab" }.forEach { key(it.id, it.type) { Render(it, ack, emit) } } }
        ) { insets ->
            Box(Modifier.padding(insets).consumeWindowInsets(insets)) {
                n.children.filter { it.text("slot") !in listOf("top", "bottom", "fab") }
                    .forEach { key(it.id, it.type) { Render(it, ack, emit) } }
            }
        }
        "top-bar" -> CenterAlignedTopAppBar(title = {
            val title = n.children.filter { it.text("slot") == "title" }
            if (title.isEmpty()) Text(n.text("text")) else title.forEach { Render(it, ack, emit) }
        }, modifier = m,
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                containerColor = colour(n.text("container-color", "surface")),
                titleContentColor = colour(n.text("color", "on-surface")),
                navigationIconContentColor = colour(n.text("color", "on-surface")),
                actionIconContentColor = colour(n.text("color", "on-surface"))),
            navigationIcon = { n.children.filter { it.text("slot") == "navigation" }.forEach { key(it.id, it.type) { Render(it, ack, emit) } } },
            actions = { n.children.filter { it.text("slot") !in listOf("navigation", "title") }.forEach { key(it.id, it.type) { Render(it, ack, emit) } } })
        "bottom-bar" -> NavigationBar(m) {
            n.children.forEach { child ->
                require(child.type == "nav-item") { "bottom-bar children must be nav-item" }
                key(child.id, child.type) { NavigationBarItem(child.flag("selected"), { emit(child.id, "click", "") },
                    icon = { if (child.props.has("icon")) ControlIcon(child) else Text("•") }, label = { Text(child.text("text")) },
                    modifier = Modifier.testTag(child.id), enabled = child.flag("enabled", true)) }
            }
        }
        "nav-item" -> error("nav-item must be inside bottom-bar")
        "dialog" -> Dialog(onDismissRequest = { emit(n.id, "dismiss", "") }) {
            Surface(m, shape = RoundedCornerShape(24.dp)) {
                Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { children() }
            }
        }
        "bottom-sheet" -> ModalBottomSheet(onDismissRequest = { emit(n.id, "dismiss", "") },
            modifier = m, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
            Column(Modifier.fillMaxWidth().padding(20.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) { children() }
        }
        "swipe" -> Swipe(n, ack, emit, m)
        else -> RenderControl(n, ack, emit, m)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Swipe(n: Node, ack: Long, emit: Emit, modifier: Modifier) {
    val latest by rememberUpdatedState(n)
    val state = rememberSwipeToDismissBoxState(confirmValueChange = { direction ->
        when (direction) {
            SwipeToDismissBoxValue.StartToEnd -> emit(latest.id, "right", "")
            SwipeToDismissBoxValue.EndToStart -> emit(latest.id, "left", "")
            else -> Unit
        }
        false // The Lisp action decides whether to remove, update or retain the row.
    })
    SwipeToDismissBox(state = state, modifier = modifier,
        enableDismissFromStartToEnd = n.flag("on-right"),
        enableDismissFromEndToStart = n.flag("on-left"),
        backgroundContent = {
            val right = state.dismissDirection == SwipeToDismissBoxValue.StartToEnd
            Box(Modifier.fillMaxSize().background(colour(if (right) "primary-container" else "error-container"),
                RoundedCornerShape(n.number("radius", 12).dp)).padding(20.dp),
                contentAlignment = if (right) Alignment.CenterStart else Alignment.CenterEnd) {
                Text(n.text(if (right) "right-label" else "left-label", if (right) "Complete" else "Delete"))
            }
        }) { n.children.forEach { key(it.id, it.type) { Render(it, ack, emit) } } }
}

/** Worker-side incremental model. Each publication resolves to an immutable tree;
 * dropping an intermediate UI frame therefore cannot lose a dependency update. */
internal class SnapshotDecoder {
    private data class Definition(val type: String, val props: JSONObject, val children: List<String>)
    private var definitions = emptyMap<String, Definition>()
    private var resolved = emptyMap<String, Node>()
    fun read(text: String): Snapshot {
        val json = JSONObject(text)
        require(json.getInt("protocol") == 1) { "Unsupported Evergreen Compose protocol" }
        if (json.has("tree")) return Snapshot.read(text) // Full snapshots for native callers/tests.
        val reset = json.getBoolean("reset")
        val next = if (reset) mutableMapOf() else definitions.toMutableMap()
        val updates = json.getJSONArray("nodes")
        for (i in 0 until updates.length()) {
            val value = updates.getJSONObject(i)
            val ids = value.getJSONArray("children")
            next[value.getString("id")] = Definition(value.getString("type"), value.getJSONObject("props"),
                List(ids.length()) { ids.getString(it) })
        }
        val live = mutableMapOf<String, Node>()
        val visiting = mutableSetOf<String>()
        fun resolve(id: String): Node {
            require(visiting.add(id)) { "Duplicate or cyclic Compose ID: $id" }
            val definition = requireNotNull(next[id]) { "Missing Compose node: $id" }
            val children = definition.children.map { resolve(it) }
            val old = if (reset) null else resolved[id]
            val node = if (old != null && definition === definitions[id] &&
                children.size == old.children.size && children.indices.all { children[it] === old.children[it] }) old
                else Node(definition.type, id, definition.props, children)
            live[id] = node
            return node
        }
        val root = resolve(json.getString("root"))
        definitions = next.filterKeys { it in live }
        resolved = live
        return Snapshot(root, json.getLong("ack"))
    }
}
