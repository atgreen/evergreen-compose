/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneOffset

@Composable
internal fun DataControl(n: Node, ack: Long, emit: Emit, m: Modifier) {
    when (n.type) {
        "calendar" -> Calendar(n, ack, emit, m)
        "data-table" -> DataTable(n, emit, m)
        "chart" -> {
            val points = n.children
            val tint = colour(n.text("color", "primary"))
            val values = points.map { it.number("value").toFloat() }
            val low = minOf(0f, values.minOrNull() ?: 0f)
            val high = maxOf(low + 1, values.maxOrNull() ?: 1f)
            Column(m) {
                Canvas(Modifier.fillMaxWidth().height(n.number("plot-height", 180).dp)
                    .semantics { contentDescription = points.joinToString { "${it.text("text")}: ${it.number("value")}" } }
                    .pointerInput(points, n.flag("enabled", true)) { detectTapGestures { at ->
                        if (points.isNotEmpty() && n.flag("enabled", true)) {
                            val index = (at.x / size.width * points.size).toInt().coerceIn(points.indices)
                            emit(n.id, "select", points[index].id)
                        }
                    } }) {
                    if (points.isNotEmpty()) {
                        val width = size.width / points.size
                        fun y(value: Float) = size.height * (1 - (value - low) / (high - low))
                        if (n.text("kind", "bar") == "line") {
                            val path = Path()
                            values.forEachIndexed { i, v -> if (i == 0) path.moveTo(width / 2, y(v)) else path.lineTo((i + .5f) * width, y(v)) }
                            drawPath(path, tint, style = androidx.compose.ui.graphics.drawscope.Stroke(3.dp.toPx()))
                        } else values.forEachIndexed { i, v ->
                            drawRect(tint, Offset(i * width + width * .1f, minOf(y(v), y(0f))), Size(width * .8f, kotlin.math.abs(y(0f) - y(v))))
                        }
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    points.forEach { Text(it.text("text"), style = MaterialTheme.typography.labelSmall) }
                }
            }
        }
        else -> ContentControl(n, ack, emit, m)
    }
}

@Composable
private fun Calendar(n: Node, ack: Long, emit: Emit, m: Modifier) {
    val millis = (n.props.opt("value") as? Number)?.toLong()
    val source = millis?.let { Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate() }
    var selected by remember { mutableStateOf(source) }
    var lastEdit by remember { mutableLongStateOf(0) }
    var month by remember { mutableStateOf(YearMonth.from(source ?: LocalDate.now())) }
    LaunchedEffect(source, ack) {
        if (ack >= lastEdit && source != selected) {
            selected = source
            if (source != null) month = YearMonth.from(source)
        }
    }
    Column(m) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton({ month = month.minusMonths(1) }, Modifier.testTag("${n.id}/previous")) { Text("‹") }
            Text("${month.month.name.lowercase().replaceFirstChar { it.uppercase() }} ${month.year}", Modifier.padding(12.dp).testTag("${n.id}/month"))
            TextButton({ month = month.plusMonths(1) }, Modifier.testTag("${n.id}/next")) { Text("›") }
        }
        Row { listOf("M", "T", "W", "T", "F", "S", "S").forEach { Text(it, Modifier.weight(1f).padding(8.dp)) } }
        val offset = month.atDay(1).dayOfWeek.value - 1
        val rows = (offset + month.lengthOfMonth() + 6) / 7
        repeat(rows) { week -> Row {
            repeat(7) { column ->
                val day = week * 7 + column - offset + 1
                Box(Modifier.weight(1f)) {
                    if (day in 1..month.lengthOfMonth()) {
                        val date = month.atDay(day)
                        val value = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
                        TextButton({ selected = date; lastEdit = emit(n.id, "change", "$value") }, Modifier.testTag("${n.id}/$date"),
                            enabled = n.flag("enabled", true),
                            colors = ButtonDefaults.textButtonColors(containerColor = if (date == selected)
                                MaterialTheme.colorScheme.primaryContainer else androidx.compose.ui.graphics.Color.Transparent)) { Text("$day") }
                    }
                }
            }
        } }
        n.children.filter { it.text("date") == selected?.toString() }.forEach { Render(it, ack, emit) }
    }
}

@Composable
private fun DataTable(n: Node, emit: Emit, m: Modifier) {
    val columns = n.children.filter { it.type == "table-column" }
    val rows = n.children.filter { it.type == "table-row" }
    var sort by remember { mutableIntStateOf(-1) }
    var ascending by remember { mutableStateOf(true) }
    var page by remember { mutableIntStateOf(0) }
    val count = n.number("page-size", 10).coerceAtLeast(1)
    val pageCount = ((rows.size + count - 1) / count).coerceAtLeast(1)
    val currentPage = page.coerceIn(0, pageCount - 1)
    val ordered = if (sort < 0) rows else rows.sortedWith { a, b ->
        val ac = a.children.getOrNull(sort); val bc = b.children.getOrNull(sort)
        val result = if (columns.getOrNull(sort)?.flag("numeric") == true)
            (ac?.number("value") ?: 0).compareTo(bc?.number("value") ?: 0)
        else (ac?.text("text") ?: "").compareTo(bc?.text("text") ?: "", ignoreCase = true)
        if (ascending) result else -result
    }
    Column(m) {
        Column(Modifier.horizontalScroll(rememberScrollState())) {
            Row {
                columns.forEachIndexed { i, column ->
                    TextButton({ ascending = if (sort == i) !ascending else true; sort = i; page = 0 },
                        Modifier.width(column.number("width", 140).dp).testTag(column.id),
                        enabled = n.flag("enabled", true) && column.flag("sortable", true)) {
                        Text(column.text("text") + if (sort == i) (if (ascending) " ↑" else " ↓") else "")
                    }
                }
            }
            ordered.drop(currentPage * count).take(count).forEach { row -> key(row.id) {
                Surface(color = if (row.flag("selected")) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surface) {
                    Row(Modifier.testTag(row.id).clickable(enabled = n.flag("enabled", true) && row.flag("enabled", true)) {
                        emit(n.id, "select", row.text("value", row.id))
                    }) {
                        row.children.forEachIndexed { i, cell ->
                            Text(cell.text("text", if (cell.props.has("value")) "${cell.number("value")}" else ""),
                                Modifier.width(columns.getOrNull(i)?.number("width", 140)?.dp ?: 140.dp).padding(12.dp))
                        }
                    }
                }
                HorizontalDivider()
            } }
        }
        Row {
            TextButton({ page = currentPage - 1 }, Modifier.testTag("${n.id}/previous"), currentPage > 0) { Text("Previous") }
            Text("${currentPage + 1} / $pageCount", Modifier.padding(12.dp))
            TextButton({ page = currentPage + 1 }, Modifier.testTag("${n.id}/next"), currentPage + 1 < pageCount) { Text("Next") }
        }
    }
}
