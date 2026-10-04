/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */
package dev.egcl.compose

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.ext.junit.rules.ActivityScenarioRule
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain

class DrawingPadTest {
    private val ui = createEmptyComposeRule()
    private val activity = ActivityScenarioRule(PlainProbeActivity::class.java)
    @get:Rule val rules: RuleChain = RuleChain.outerRule(ui).around(activity)
    private var host: ComposeHost? = null

    private fun publish(enabled: Boolean = true) {
        activity.scenario.onActivity { host = ComposeHost(it) }
        host!!.publish("""{"protocol":1,"ack":0,"tree":{"id":"paper","type":"drawing-pad",
            "props":{"width":240,"height":320,"view-width":600,"view-height":800,
            "pen-color":"#234b38","pen-width":8,"on-stroke":true,"enabled":$enabled},"children":[]}}""")
        ui.waitForIdle()
        assertNull(host!!.getFailure())
    }
    @After fun close() { host?.close(); ui.waitForIdle() }

    @Test fun dragProducesOneCompletedStroke() {
        publish()
        ui.onNodeWithTag("paper").performTouchInput {
            down(Offset(width * .25f, height * .25f))
            moveTo(Offset(width * .5f, height * .5f))
        }
        assertNull("Moving must not cross JNI for every sample", host!!.pollEvent())
        ui.onNodeWithTag("paper").performTouchInput { up() }
        var event: String? = null
        ui.waitUntil(5000) { event = host!!.pollEvent(); event != null }
        assertTrue(event!!.contains("\"stroke\""))
        assertTrue(event!!.contains("(150 200)"))
        assertTrue(event!!.contains("(300 400)"))
        assertNull(host!!.pollEvent())
    }
    @Test fun tapProducesADotAndCancelProducesNothing() {
        publish()
        ui.onNodeWithTag("paper").performTouchInput { click(center) }
        var event: String? = null
        ui.waitUntil(5000) { event = host!!.pollEvent(); event != null }
        assertTrue(event!!.contains("(300 400)"))
        ui.onNodeWithTag("paper").performTouchInput { down(center); moveBy(Offset(20f, 20f)); cancel() }
        assertNull(host!!.pollEvent())
    }
    @Test fun disabledPadIgnoresInk() {
        publish(false)
        ui.onNodeWithTag("paper").performTouchInput { click(center) }
        assertNull(host!!.pollEvent())
    }
    @Test fun longStrokeKeepsItsBeginningAndFinalEndpoint() {
        var points = listOf(Offset.Zero)
        repeat(5000) { points = appendInkPoint(points, Offset((it + 1).toFloat(), 50f)) }
        assertTrue(points.size <= 4096)
        assertEquals(Offset.Zero, points.first())
        assertEquals(Offset(5000f, 50f), points.last())
    }

}
