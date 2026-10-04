/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.pager.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
internal fun Collection(n: Node, ack: Long, emit: Emit, m: Modifier) {
    when (n.type) {
        "lazy-grid" -> LazyVerticalGrid(columns = GridCells.Fixed(n.number("columns", 2).coerceAtLeast(1)),
            modifier = bounded(n, m), contentPadding = PaddingValues(n.number("content-padding").dp),
            verticalArrangement = Arrangement.spacedBy(n.number("spacing").dp),
            horizontalArrangement = Arrangement.spacedBy(n.number("spacing").dp)) {
            items(n.children, key = { it.id }, contentType = { it.type }) { Render(it, ack, emit) }
        }
        "horizontal-pager", "vertical-pager" -> Pages(n, ack, emit, bounded(n, m))
        "tabs" -> {
            require(n.children.all { it.type == "tab" }) { "tabs children must be tab" }
            if (n.children.isNotEmpty()) {
                val selected = n.children.indexOfFirst { it.flag("selected") }.coerceAtLeast(0)
                val tabs: @Composable () -> Unit = {
                    n.children.forEach { child -> key(child.id, child.type) {
                        Tab(child.flag("selected"), { emit(child.id, "click", "") }, Modifier.testTag(child.id),
                            enabled = child.flag("enabled", true), text = { Text(child.text("text")) })
                    } }
                }
                if (n.flag("scrollable", true)) ScrollableTabRow(selected, m, edgePadding = 0.dp, tabs = tabs)
                else TabRow(selected, m, tabs = tabs)
            }
        }
        "segmented-buttons" -> {
            require(n.children.all { it.type == "segment" }) { "segmented-buttons children must be segment" }
            if (n.flag("multiple")) MultiChoiceSegmentedButtonRow(m) {
                n.children.forEachIndexed { index, child -> key(child.id, child.type) {
                    SegmentedButton(child.flag("selected"), { emit(child.id, "click", "") },
                        SegmentedButtonDefaults.itemShape(index, n.children.size), Modifier.testTag(child.id),
                        enabled = child.flag("enabled", true)) { Text(child.text("text")) }
                } }
            } else SingleChoiceSegmentedButtonRow(m) {
                n.children.forEachIndexed { index, child -> key(child.id, child.type) {
                    SegmentedButton(child.flag("selected"), { emit(child.id, "click", "") },
                        SegmentedButtonDefaults.itemShape(index, n.children.size), Modifier.testTag(child.id),
                        enabled = child.flag("enabled", true)) { Text(child.text("text")) }
                } }
            }
        }
        "navigation-rail" -> NavigationRail(m) {
            n.children.forEach { child ->
                require(child.type == "nav-item") { "navigation-rail children must be nav-item" }
                key(child.id, child.type) { NavigationRailItem(child.flag("selected"), { emit(child.id, "click", "") },
                    icon = { if (child.props.has("icon")) ControlIcon(child) else Text("•") },
                    label = { Text(child.text("text")) }, modifier = Modifier.testTag(child.id), enabled = child.flag("enabled", true)) }
            }
        }
        "navigation-drawer" -> NavigationDrawer(n, ack, emit, m)
        "bottom-app-bar" -> BottomAppBar(m) { Children(n, ack, emit) }
        "dropdown-menu" -> Box(m) {
            n.children.filter { it.text("slot") == "anchor" }.forEach { key(it.id, it.type) { Render(it, ack, emit) } }
            DropdownMenu(n.flag("expanded", true), { emit(n.id, "dismiss", "") }, Modifier.testTag("${n.id}/popup")) {
                n.children.filter { it.text("slot") != "anchor" }.forEach { child ->
                    require(child.type == "menu-item") { "dropdown-menu children must be menu-item or have slot anchor" }
                    key(child.id, child.type) { DropdownMenuItem(text = { Text(child.text("text")) },
                        onClick = { emit(child.id, "click", "") }, modifier = Modifier.testTag(child.id),
                        enabled = child.flag("enabled", true),
                        leadingIcon = if (child.props.has("icon")) { { ControlIcon(child) } } else null) }
                }
            }
        }
    }
}

// Nested scrollable controls need a finite viewport in a scrolling gallery/list.
private fun bounded(n: Node, m: Modifier) = if (n.props.has("height") || n.flag("fill") || n.number("weight") > 0) m else m.height(240.dp)

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Pages(n: Node, ack: Long, emit: Emit, m: Modifier) {
    val latest by rememberUpdatedState(n)
    val state = rememberPagerState(initialPage = n.number("page").coerceIn(0, (n.children.size - 1).coerceAtLeast(0)),
        pageCount = { latest.children.size })
    var lastEdit by remember { mutableLongStateOf(0) }
    var reported by remember { mutableIntStateOf(state.currentPage) }
    LaunchedEffect(n.number("page"), n.children.size, ack) {
        if (ack >= lastEdit && !state.isScrollInProgress && n.children.isNotEmpty()) {
            val page = n.number("page").coerceIn(0, n.children.lastIndex)
            reported = page
            if (state.currentPage != page) state.scrollToPage(page)
        }
    }
    LaunchedEffect(state) {
        snapshotFlow { state.settledPage }.distinctUntilChanged().collect { page ->
            if (page != reported) {
                reported = page
                lastEdit = emit(latest.id, "change", page.toString())
            }
        }
    }
    val content: @Composable PagerScope.(Int) -> Unit = { index -> Render(n.children[index], ack, emit) }
    if (n.type == "horizontal-pager") HorizontalPager(state, m, pageSpacing = n.number("spacing").dp,
        userScrollEnabled = n.flag("enabled", true), key = { n.children[it].id }, pageContent = content)
    else VerticalPager(state, m, pageSpacing = n.number("spacing").dp,
        userScrollEnabled = n.flag("enabled", true), key = { n.children[it].id }, pageContent = content)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NavigationDrawer(n: Node, ack: Long, emit: Emit, m: Modifier) {
    val latest by rememberUpdatedState(n)
    var lastDismiss by remember { mutableLongStateOf(0) }
    val state = rememberDrawerState(if (n.flag("open")) DrawerValue.Open else DrawerValue.Closed,
        confirmStateChange = {
            if (it == DrawerValue.Closed && latest.flag("open")) lastDismiss = emit(latest.id, "dismiss", "")
            true
        })
    LaunchedEffect(n.flag("open"), ack) {
        if (ack >= lastDismiss) { if (n.flag("open")) state.open() else state.close() }
    }
    ModalNavigationDrawer(drawerState = state, modifier = m, gesturesEnabled = n.flag("enabled", true), drawerContent = {
        ModalDrawerSheet {
            n.children.filter { it.type == "drawer-item" || it.text("slot") == "drawer" }.forEach { child -> key(child.id, child.type) {
                if (child.type == "drawer-item") NavigationDrawerItem(label = { Text(child.text("text")) },
                    selected = child.flag("selected"), onClick = { if (child.flag("enabled", true)) emit(child.id, "click", "") },
                    modifier = Modifier.testTag(child.id).semantics { if (!child.flag("enabled", true)) disabled() },
                    icon = if (child.props.has("icon")) { { ControlIcon(child) } } else null)
                else Render(child, ack, emit)
            } }
        }
    }) { n.children.filter { it.type != "drawer-item" && it.text("slot") != "drawer" }
        .forEach { key(it.id, it.type) { Render(it, ack, emit) } } }
}
