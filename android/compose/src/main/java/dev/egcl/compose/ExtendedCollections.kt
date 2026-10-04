/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.material3.*
import androidx.compose.material3.carousel.HorizontalMultiBrowseCarousel
import androidx.compose.material3.carousel.rememberCarouselState
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
internal fun ExtendedCollection(n: Node, ack: Long, emit: Emit, m: Modifier) {
    val enabled = n.flag("enabled", true)
    when (n.type) {
        "pull-to-refresh" -> {
            val refreshing = localValue(n.flag("refreshing"), ack)
            PullToRefreshBox(refreshing.value, {
                if (enabled && !refreshing.value) refreshing.edit(true, emit(n.id, "refresh", ""))
            }, m) { Children(n, ack, emit) }
        }
        "section-list" -> LazyColumn(m.heightIn(max = n.number("height", 320).dp)) {
            n.children.forEach { section ->
                stickyHeader(key = section.id) {
                    Surface(Modifier.fillMaxWidth().testTag(section.id)) {
                        Text(section.text("text"), Modifier.padding(12.dp), style = MaterialTheme.typography.titleMedium)
                    }
                }
                items(section.children, key = { it.id }) { Render(it, ack, emit) }
            }
        }
        "carousel" -> {
            val latest by rememberUpdatedState(n)
            val state = rememberCarouselState(initialItem = n.number("page").coerceIn(0, (n.children.size - 1).coerceAtLeast(0))) { latest.children.size }
            if (n.children.isNotEmpty()) HorizontalMultiBrowseCarousel(state, modifier = m.height(n.number("height", 180).dp),
                preferredItemWidth = n.number("item-width", 220).dp, itemSpacing = n.number("spacing", 8).dp) { index ->
                Box(Modifier.maskClip(MaterialTheme.shapes.large)) { Render(n.children[index], ack, emit) }
            }
        }
        "reorderable-list" -> Reorderable(n, ack, emit, m)
        "swipe-reveal" -> {
            val width = with(LocalDensity.current) { n.number("reveal-width", 120).dp.toPx() }
            var offset by remember { mutableFloatStateOf(0f) }
            val hasStart = n.children.any { it.text("slot") == "start" }
            val hasEnd = n.children.any { it.text("slot") == "end" }
            val min = if (hasEnd) -width else 0f
            val max = if (hasStart) width else 0f
            Box(m) {
                Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically) {
                    Row { if (offset > 0) n.children.filter { it.text("slot") == "start" }.forEach { Render(it, ack, emit) } }
                    Row { if (offset < 0) n.children.filter { it.text("slot") == "end" }.forEach { Render(it, ack, emit) } }
                }
                Box(Modifier.offset { IntOffset(offset.roundToInt(), 0) }.fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surface)
                    .semantics { customActions = listOfNotNull(
                        if (hasStart) CustomAccessibilityAction("Show start actions") { offset = max; true } else null,
                        if (hasEnd) CustomAccessibilityAction("Show end actions") { offset = min; true } else null,
                        CustomAccessibilityAction("Close actions") { offset = 0f; true }) }
                    .draggable(rememberDraggableState { offset = (offset + it).coerceIn(min, max) }, Orientation.Horizontal,
                        enabled = enabled, onDragStopped = {
                            offset = when { offset > width / 2 -> max; offset < -width / 2 -> min; else -> 0f }
                        })) {
                    n.children.filter { it.text("slot") !in listOf("start", "end") }.forEach { Render(it, ack, emit) }
                }
            }
        }
        else -> DataControl(n, ack, emit, m)
    }
}

@Composable
private fun Reorderable(n: Node, ack: Long, emit: Emit, m: Modifier) {
    val order = localValue(n.children.map { it.id }, ack)
    val grid = rememberLazyGridState()
    val scope = rememberCoroutineScope()
    val nodes = n.children.associateBy { it.id }
    val ids = order.value.filter { nodes.containsKey(it) }
    val enabled = n.flag("enabled", true)
    val latestIds by rememberUpdatedState(ids)
    val latestEmit by rememberUpdatedState(emit)
    val move: (Int, Int) -> Unit = { from, to ->
        if (enabled && from != to && from in latestIds.indices && to in latestIds.indices) {
            val changed = latestIds.toMutableList().apply { add(to, removeAt(from)) }
            order.edit(changed, latestEmit(n.id, "move", "$from,$to"))
        }
    }
    val latestMove by rememberUpdatedState(move)
    LazyVerticalGrid(GridCells.Fixed(n.number("columns", 1).coerceAtLeast(1)),
        m.heightIn(max = n.number("height", 320).dp), state = grid,
        verticalArrangement = Arrangement.spacedBy(n.number("spacing", 4).dp)) {
        items(ids, key = { it }) { id ->
            val index = ids.indexOf(id)
            Row(Modifier.fillMaxWidth().testTag("$id/row").semantics { customActions = listOf(
                CustomAccessibilityAction("Move earlier") { move(index, index - 1); index > 0 },
                CustomAccessibilityAction("Move later") { move(index, index + 1); index < ids.lastIndex }) }) {
                Text("⠿", Modifier.padding(12.dp).testTag("$id/drag").pointerInput(id, enabled) {
                    if (enabled) {
                        var pointer = Offset.Zero
                        detectDragGesturesAfterLongPress(onDragStart = {
                            val item = grid.layoutInfo.visibleItemsInfo.find { it.key == id }
                            if (item != null) pointer = Offset(item.offset.x + item.size.width / 2f, item.offset.y + item.size.height / 2f)
                        }, onDrag = { change, amount ->
                            change.consume(); pointer += amount
                            val item = grid.layoutInfo.visibleItemsInfo.find {
                                pointer.x >= it.offset.x && pointer.x < it.offset.x + it.size.width &&
                                pointer.y >= it.offset.y && pointer.y < it.offset.y + it.size.height
                            }
                            if (item != null) latestMove(latestIds.indexOf(id), item.index)
                            val bottom = grid.layoutInfo.viewportEndOffset
                            val scroll = when { pointer.y < 48 -> -16f; pointer.y > bottom - 48 -> 16f; else -> 0f }
                            if (scroll != 0f) scope.launch { grid.scrollBy(scroll) }
                        })
                    }
                })
                Box(Modifier.weight(1f)) { Render(nodes.getValue(id), ack, emit) }
            }
        }
    }
}
