/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.ext.junit.rules.ActivityScenarioRule
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain

class SampleControlsTest {
    private val ui = createEmptyComposeRule()
    private val activity = ActivityScenarioRule(PlainProbeActivity::class.java)
    @get:Rule val rules: RuleChain = RuleChain.outerRule(ui).around(activity)
    private var host: ComposeHost? = null
    private fun publish(tree: String) {
        if (host == null) activity.scenario.onActivity { host = ComposeHost(it) }
        host!!.publish("""{"protocol":1,"ack":0,"tree":$tree}""")
        ui.waitForIdle()
        assertNull(host!!.getFailure())
    }
    @After fun close() { host?.close(); ui.waitForIdle() }

    @Test fun applicationBackReturnsAnEventWithoutFinishingTheActivity() {
        publish("""{"id":"screen","type":"theme","props":{"on-back":true},"children":[
            {"id":"label","type":"text","props":{"text":"Article"},"children":[]}]}""")
        androidx.test.espresso.Espresso.pressBack()
        var event: String? = null
        ui.waitUntil(5000) { event = host!!.pollEvent(); event != null }
        assertEquals("(1 \"screen\" \"back\" \"\")", event)
        ui.onNodeWithText("Article").assertExists()
    }

    @Test fun vectorViewportScalesToTheAvailableCanvas() {
        publish("""{"id":"drawing","type":"canvas","props":{"width":200,"height":100,
            "view-width":100,"view-height":100,"background":"#ffffff"},"children":[
            {"id":"shape","type":"path","props":{"data":"M0 0H50V100H0Z","fill":"#ff0000"},"children":[]}]}""")
        val bitmap = ui.onNodeWithTag("drawing").captureToImage().asAndroidBitmap()
        assertEquals(android.graphics.Color.RED, bitmap.getPixel(bitmap.width / 4, bitmap.height / 2))
        assertEquals(android.graphics.Color.WHITE, bitmap.getPixel(bitmap.width * 3 / 4, bitmap.height / 2))
    }

    @Test fun appPaletteChangesSemanticColors() {
        publish("""{"id":"theme","type":"theme","props":{"primary":"#ff0000"},"children":[
            {"id":"swatch","type":"box","props":{"width":60,"height":60,"background":"primary"},"children":[]}]}""")
        val bitmap = ui.onNodeWithTag("swatch").captureToImage().asAndroidBitmap()
        assertEquals(android.graphics.Color.RED, bitmap.getPixel(bitmap.width / 2, bitmap.height / 2))
    }

    @Test fun listCanRevealANewMessageByStableId() {
        val rows = (0..99).joinToString(",") {
            """{"id":"row-$it","type":"text","props":{"text":"Message $it","height":60},"children":[]}"""
        }
        publish("""{"id":"messages","type":"lazy-column","props":{"height":300,"scroll-to":"row-99"},"children":[$rows]}""")
        ui.onNodeWithText("Message 99").assertIsDisplayed()
    }
}
