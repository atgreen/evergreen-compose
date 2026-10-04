/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */
package dev.egcl.compose

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asComposePath
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.core.graphics.PathParser
import kotlin.math.min
import kotlin.math.roundToInt

private data class Ink(val color: String, val width: Int, val points: List<Offset>, val sequence: Long = 0)
private data class SavedInk(val color: Color, val width: Float, val path: Path)

internal fun appendInkPoint(points: List<Offset>, point: Offset): List<Offset> {
    // Keep the whole gesture within the event bound, including its endpoint.
    val retained = if (points.size >= 4096) points.filterIndexed { index, _ -> index % 2 == 0 } else points
    return retained + point
}

/** Active and unacknowledged strokes stay native; Lisp receives only pen-up. */
@Composable
internal fun DrawingPad(n: Node, ack: Long, emit: Emit, modifier: Modifier) {
    val pageWidth = n.number("view-width", 1000).coerceIn(1, 10000)
    val pageHeight = n.number("view-height", 1400).coerceIn(1, 10000)
    val latestNode by rememberUpdatedState(n)
    val latestEmit by rememberUpdatedState(emit)
    var active by remember { mutableStateOf<Ink?>(null) }
    val pending = remember { mutableStateListOf<Ink>() }
    LaunchedEffect(ack) { pending.removeAll { it.sequence <= ack } }
    val saved = n.children.map { child ->
        require(child.type == "ink-stroke") { "Drawing pads contain ink-stroke nodes" }
        remember(child) {
            SavedInk(Color(android.graphics.Color.parseColor(child.text("color", "#234b38"))),
                child.number("width", 8).coerceIn(1, 100).toFloat(),
                PathParser.createPathFromPathData(child.text("data"))?.asComposePath() ?: Path())
        }
    }
    val paper = colour(n.text("paper-color", "#fffdf6"))
    Canvas(modifier.clipToBounds().semantics {
        contentDescription = n.text("description", "Drawing paper. Drag a finger or stylus to draw.")
    }.pointerInput(n.id, pageWidth, pageHeight, n.flag("enabled", true)) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            if (!latestNode.flag("enabled", true)) return@awaitEachGesture
            val scale = min(size.width.toFloat() / pageWidth, size.height.toFloat() / pageHeight)
            if (scale <= 0f) return@awaitEachGesture
            val origin = Offset((size.width - pageWidth * scale) / 2f, (size.height - pageHeight * scale) / 2f)
            fun mapped(p: Offset) = Offset(((p.x - origin.x) / scale).roundToInt().coerceIn(0, pageWidth).toFloat(),
                ((p.y - origin.y) / scale).roundToInt().coerceIn(0, pageHeight).toFloat())
            val start = down.position - origin
            if (start.x !in 0f..(pageWidth * scale) || start.y !in 0f..(pageHeight * scale)) return@awaitEachGesture
            active = Ink(latestNode.text("pen-color", "#234b38"), latestNode.number("pen-width", 8).coerceIn(1, 100), listOf(mapped(down.position)))
            down.consume()
            try {
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.find { it.id == down.id } ?: break
                    if (change.isConsumed) break
                    val ink = active ?: break
                    val point = mapped(change.position)
                    if (point != ink.points.last()) active = ink.copy(points = appendInkPoint(ink.points, point))
                    change.consume()
                    if (!change.pressed) {
                        val complete = active!!
                        val points = complete.points.joinToString(" ", "(", ")") { "(${it.x.toInt()} ${it.y.toInt()})" }
                        val payload = "(${lispString(complete.color)} ${complete.width} $points)"
                        val sequence = latestEmit(n.id, "stroke", payload)
                        pending.add(complete.copy(sequence = sequence))
                        break
                    }
                }
            } finally { active = null }
        }
    }) {
        val scale = min(size.width / pageWidth, size.height / pageHeight)
        val origin = Offset((size.width - pageWidth * scale) / 2f, (size.height - pageHeight * scale) / 2f)
        withTransform({ translate(origin.x, origin.y); scale(scale, scale, Offset.Zero) }) {
            drawRect(paper, size = Size(pageWidth.toFloat(), pageHeight.toFloat()))
            fun paint(path: Path, color: Color, width: Float) =
                drawPath(path, color, style = Stroke(width, cap = StrokeCap.Round, join = StrokeJoin.Round))
            saved.forEach { paint(it.path, it.color, it.width) }
            (pending.filter { it.sequence > ack } + listOfNotNull(active)).forEach { ink ->
                val color = Color(android.graphics.Color.parseColor(ink.color))
                if (ink.points.size == 1) drawCircle(color, ink.width / 2f, ink.points.first())
                else {
                    val path = Path().apply {
                        moveTo(ink.points.first().x, ink.points.first().y)
                        ink.points.drop(1).forEach { lineTo(it.x, it.y) }
                    }
                    paint(path, color, ink.width.toFloat())
                }
            }
        }
    }
}
