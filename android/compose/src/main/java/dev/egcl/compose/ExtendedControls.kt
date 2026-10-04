/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

/** Local edits remain visible until Lisp has acknowledged their event sequence. */
internal class LocalValue<T>(initial: T) {
    var value by mutableStateOf(initial)
    var sequence = 0L
    fun edit(next: T, sequence: Long) { value = next; this.sequence = sequence }
}
@Composable
internal fun <T> localValue(source: T, ack: Long): LocalValue<T> {
    val state = remember { LocalValue(source) }
    SideEffect { if (ack >= state.sequence) state.value = source }
    return state
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ExtendedControl(n: Node, ack: Long, emit: Emit, m: Modifier) {
    val enabled = n.flag("enabled", true)
    when (n.type) {
        "number-stepper", "rating" -> {
            val min = n.number("min", if (n.type == "rating") 1 else 0)
            val max = n.number("max", if (n.type == "rating") 5 else 100)
            require(max >= min) { "max must be at least min" }
            val value = localValue(n.number("value", min).coerceIn(min, max), ack)
            fun change(next: Int) { val v = next.coerceIn(min, max); value.edit(v, emit(n.id, "change", "$v")) }
            Row(m) {
                if (n.type == "rating") {
                    require(max - min <= 20) { "Rating range is too large" }
                    for (i in min..max) IconToggleButton(value.value >= i, { change(i) },
                        Modifier.testTag("${n.id}/$i"), enabled) { Text(if (value.value >= i) "★" else "☆") }
                } else {
                    val step = n.number("step", 1).coerceAtLeast(1)
                    OutlinedButton({ change((value.value.toLong() - step).coerceAtLeast(min.toLong()).toInt()) },
                        Modifier.testTag("${n.id}/decrease"), enabled && value.value > min) { Text("−") }
                    Text(value.value.toString(), Modifier.padding(16.dp).testTag("${n.id}/value"))
                    OutlinedButton({ change((value.value.toLong() + step).coerceAtMost(max.toLong()).toInt()) },
                        Modifier.testTag("${n.id}/increase"), enabled && value.value < max) { Text("+") }
                }
            }
        }
        "otp-field" -> {
            val length = n.number("length", 6).coerceIn(1, 32)
            val value = localValue(n.text("value"), ack)
            OutlinedTextField(value.value, { input ->
                val next = input.filter { it in '0'..'9' }.take(length)
                if (next != value.value) value.edit(next, emit(n.id, "change", next))
            }, m, enabled = enabled, label = { Text(n.text("label", "Code")) }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword))
        }
        "accordion" -> {
            val open = localValue(n.flag("expanded"), ack)
            Column(m) {
                TextButton({ val next = !open.value; open.edit(next, emit(n.id, "change", "$next")) },
                    Modifier.fillMaxWidth().testTag("${n.id}/toggle"), enabled) {
                    Text((if (open.value) "▾ " else "▸ ") + n.text("text"))
                }
                if (open.value) Children(n, ack, emit)
            }
        }
        "combo-box" -> {
            val value = localValue(n.text("value"), ack)
            var expanded by remember { mutableStateOf(false) }
            ExposedDropdownMenuBox(expanded, { if (enabled) expanded = it }, m) {
                OutlinedTextField(value.value, { value.edit(it, emit(n.id, "change", it)); expanded = true },
                    Modifier.menuAnchor().fillMaxWidth().testTag("${n.id}/input"), enabled = enabled,
                    singleLine = true, label = { Text(n.text("label")) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) })
                val options = n.children.filter { it.text("text").contains(value.value, ignoreCase = true) }
                ExposedDropdownMenu(expanded && options.isNotEmpty(), { expanded = false }) {
                    options.forEach { option -> key(option.id) {
                        DropdownMenuItem({ Text(option.text("text")) }, {
                            value.edit(option.text("text"), emit(n.id, "select", option.text("value", option.id)))
                            expanded = false
                        }, Modifier.testTag(option.id), enabled = option.flag("enabled", true))
                    } }
                }
            }
        }
        "multi-select" -> Column(m) {
            n.children.forEach { option -> key(option.id) {
                val selected = localValue(option.flag("selected"), ack)
                FilterChip(selected.value, {
                    val next = !selected.value
                    selected.edit(next, emit(option.id, "change", "$next"))
                }, { Text(option.text("text")) }, Modifier.testTag(option.id), enabled && option.flag("enabled", true))
            } }
        }
        "list-detail" -> BoxWithConstraints(m) {
            val list = n.children.filter { it.text("slot") == "list" }
            val detail = n.children.filter { it.text("slot") == "detail" }
            if (maxWidth >= n.number("breakpoint", 600).dp) Row(Modifier.fillMaxSize()) {
                Column(Modifier.weight(1f)) { list.forEach { Render(it, ack, emit) } }
                Column(Modifier.weight(2f)) { detail.forEach { Render(it, ack, emit) } }
            } else Column { (if (n.flag("show-detail")) detail else list).forEach { Render(it, ack, emit) } }
        }
        else -> ExtendedCollection(n, ack, emit, m)
    }
}
