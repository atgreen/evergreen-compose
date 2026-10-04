/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asComposePath
import androidx.compose.ui.graphics.drawscope.DrawStyle
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.core.graphics.PathParser

private data class Shape(val node: Node, val path: Path?, val fill: Color, val stroke: Color)

/** Portable vector coordinates let Lisp describe illustrations and data graphics. */
@Composable
internal fun VectorCanvas(n: Node, modifier: Modifier) {
    val width = n.number("view-width", 100)
    val height = n.number("view-height", 100)
    require(width > 0 && height > 0) { "Canvas viewport dimensions must be positive" }
    val shapes = n.children.map { shape ->
        require(shape.type in listOf("path", "rect", "circle", "line")) { "Invalid canvas shape: ${shape.type}" }
        val path = if (shape.type == "path") remember(shape.text("data")) {
            PathParser.createPathFromPathData(shape.text("data"))?.asComposePath()
        } else null
        Shape(shape, path,
            colour(shape.text("fill", if (shape.props.has("stroke")) "" else "primary")),
            colour(shape.text("stroke")))
    }
    Canvas(modifier.clipToBounds()) {
        withTransform({ scale(size.width / width, size.height / height, Offset.Zero) }) {
            shapes.forEach { shape ->
                val p = shape.node
                fun paint(color: Color, style: DrawStyle) {
                    if (color == Color.Unspecified) return
                    when (p.type) {
                        "path" -> shape.path?.let { drawPath(it, color, style = style) }
                        "rect" -> drawRoundRect(color,
                            Offset(p.number("x").toFloat(), p.number("y").toFloat()),
                            Size(p.number("width").coerceAtLeast(0).toFloat(), p.number("height").coerceAtLeast(0).toFloat()),
                            CornerRadius(p.number("radius").coerceAtLeast(0).toFloat()), style = style)
                        "circle" -> drawCircle(color, p.number("radius").coerceAtLeast(0).toFloat(),
                            Offset(p.number("cx").toFloat(), p.number("cy").toFloat()), style = style)
                        "line" -> drawLine(color,
                            Offset(p.number("x").toFloat(), p.number("y").toFloat()),
                            Offset(p.number("x2").toFloat(), p.number("y2").toFloat()),
                            strokeWidth = p.number("stroke-width", 1).coerceAtLeast(1).toFloat())
                    }
                }
                paint(shape.fill, Fill)
                paint(shape.stroke, Stroke(p.number("stroke-width", 1).coerceAtLeast(1).toFloat()))
            }
        }
    }
}
