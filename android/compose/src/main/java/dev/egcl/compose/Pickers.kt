/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NumericSlider(n: Node, ack: Long, emit: Emit, m: Modifier) {
    val minimum = n.number("min", 0)
    val maximum = n.number("max", 100)
    require(minimum < maximum) { "Slider min must be less than max" }
    fun value(key: String, default: Int) = n.number(key, default).coerceIn(minimum, maximum).toFloat()
    var start by remember { mutableFloatStateOf(value("value", minimum)) }
    var end by remember { mutableFloatStateOf(value("end", maximum).coerceAtLeast(start)) }
    var dragging by remember { mutableStateOf(false) }
    var lastEdit by remember { mutableLongStateOf(0) }
    LaunchedEffect(n.number("value", minimum), n.number("end", maximum), minimum, maximum, ack) {
        if (!dragging && ack >= lastEdit) {
            start = value("value", minimum)
            end = value("end", maximum).coerceAtLeast(start)
        }
    }
    val finish = {
        dragging = false
        val text = if (n.type == "range-slider") "${start.roundToInt()},${end.roundToInt()}" else start.roundToInt().toString()
        lastEdit = emit(n.id, "change", text)
    }
    if (n.type == "range-slider") RangeSlider(value = start..end,
        onValueChange = { dragging = true; start = it.start; end = it.endInclusive }, modifier = m,
        enabled = n.flag("enabled", true), valueRange = minimum.toFloat()..maximum.toFloat(),
        steps = n.number("steps").coerceAtLeast(0), onValueChangeFinished = finish)
    else Slider(start, { dragging = true; start = it }, m, enabled = n.flag("enabled", true),
        valueRange = minimum.toFloat()..maximum.toFloat(), steps = n.number("steps").coerceAtLeast(0), onValueChangeFinished = finish)
}

private fun Node.date(key: String): Long? = (props.opt(key) as? Number)?.toLong()

/** Native picker state stays ahead of acknowledged Lisp snapshots, just like an
 * editor. Programmatic changes update `reported` first so they never echo back. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun Picker(n: Node, ack: Long, emit: Emit, m: Modifier) {
    val enabled = n.flag("enabled", true)
    // No focusGroup here: it would intercept the inherited canFocus property
    // before the picker fields/buttons receive it.
    var gate = m.focusProperties { canFocus = enabled }.onPreviewKeyEvent { !enabled }
    if (!enabled) gate = gate.alpha(0.38f).clearAndSetSemantics { disabled() }.pointerInput(Unit) {
        awaitPointerEventScope {
            while (true) awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
        }
    }
    Box(gate) { PickerContent(n, ack, { id, kind, value -> if (enabled) emit(id, kind, value) else 0L }, Modifier) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PickerContent(n: Node, ack: Long, emit: Emit, m: Modifier) {
    val latest by rememberUpdatedState(n)
    val latestEmit by rememberUpdatedState(emit)
    var lastEdit by remember { mutableLongStateOf(0) }
    when (n.type) {
        "date-picker" -> {
            val state = rememberDatePickerState(initialSelectedDateMillis = n.date("value"),
                initialDisplayMode = if (n.flag("input-mode")) DisplayMode.Input else DisplayMode.Picker)
            var reported by remember { mutableStateOf(state.selectedDateMillis) }
            LaunchedEffect(n.date("value"), ack) {
                if (ack >= lastEdit) { state.selectedDateMillis = n.date("value"); reported = state.selectedDateMillis }
            }
            LaunchedEffect(state) {
                snapshotFlow { state.selectedDateMillis }.distinctUntilChanged().collect { value ->
                    if (value != reported) { reported = value; lastEdit = latestEmit(latest.id, "change", value?.toString() ?: "") }
                }
            }
            DatePicker(state, m, showModeToggle = n.flag("show-mode-toggle", true))
        }
        "date-range-picker" -> {
            val state = rememberDateRangePickerState(initialSelectedStartDateMillis = n.date("value"),
                initialSelectedEndDateMillis = n.date("end"),
                initialDisplayMode = if (n.flag("input-mode")) DisplayMode.Input else DisplayMode.Picker)
            var reported by remember { mutableStateOf(state.selectedStartDateMillis to state.selectedEndDateMillis) }
            LaunchedEffect(n.date("value"), n.date("end"), ack) {
                if (ack >= lastEdit) {
                    state.setSelection(n.date("value"), n.date("end"))
                    reported = state.selectedStartDateMillis to state.selectedEndDateMillis
                }
            }
            LaunchedEffect(state) {
                snapshotFlow { state.selectedStartDateMillis to state.selectedEndDateMillis }.distinctUntilChanged().collect { value ->
                    if (value != reported) {
                        reported = value
                        lastEdit = latestEmit(latest.id, "change", "${value.first ?: ""},${value.second ?: ""}")
                    }
                }
            }
            DateRangePicker(state, if (n.props.has("height") || n.flag("fill")) m else m.height(480.dp),
                showModeToggle = n.flag("show-mode-toggle", true))
        }
        "time-picker" -> {
            val hour = n.number("hour", 12)
            val minute = n.number("minute")
            require(hour in 0..23 && minute in 0..59) { "Time must be hour 0..23 and minute 0..59" }
            var state by remember { mutableStateOf(TimePickerState(hour, minute, n.flag("24-hour", true))) }
            var reported by remember { mutableStateOf(state.hour to state.minute) }
            LaunchedEffect(hour, minute, n.flag("24-hour", true), ack) {
                if (ack >= lastEdit) {
                    reported = hour to minute
                    if (state.hour != hour || state.minute != minute || state.is24hour != n.flag("24-hour", true))
                        state = TimePickerState(hour, minute, n.flag("24-hour", true))
                }
            }
            LaunchedEffect(state) {
                snapshotFlow { state.hour to state.minute }.distinctUntilChanged().collect { value ->
                    if (value != reported) { reported = value; lastEdit = latestEmit(latest.id, "change", "${value.first},${value.second}") }
                }
            }
            if (n.flag("input-mode")) TimeInput(state, m) else TimePicker(state, m)
        }
    }
}
