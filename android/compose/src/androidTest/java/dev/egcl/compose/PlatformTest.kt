/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain

/** Platform adapters must also work on the plain Activity used by EGCL. */
class PlatformTest {
    private val ui = createEmptyComposeRule()
    private val activity = ActivityScenarioRule(PlainProbeActivity::class.java)
    @get:Rule val rules: RuleChain = RuleChain.outerRule(ui).around(activity)
    private var host: ComposeHost? = null
    private fun publish(type: String, props: Map<String, Any>) {
        if (host == null) activity.scenario.onActivity { host = ComposeHost(it) }
        val node = JSONObject().put("type", type).put("id", "control").put("props", JSONObject(props)).put("children", JSONArray())
        host!!.publish(JSONObject().put("protocol", 1).put("ack", 0).put("tree", node).toString())
        ui.waitForIdle()
        assertNull(host!!.getFailure())
    }
    private fun event(kind: String): String {
        var result: String? = null
        val seen = mutableListOf<String>()
        ui.waitUntil(15000) {
            var next = host!!.pollEvent()
            while (next != null) { seen.add(next); if (next.contains("\"$kind\"")) result = next; next = host!!.pollEvent() }
            result != null || seen.any { it.contains("\"error\"") }
        }
        assertNotNull("Expected $kind; events: $seen", result)
        return result!!
    }
    @After fun close() { host?.close(); ui.waitForIdle() }

    @Test fun mapLoadsInlineStyleAndReleasesOnRemoval() {
        publish("map", mapOf("height" to 220, "style" to """{"version":8,"sources":{},"layers":[{"id":"background","type":"background","paint":{"background-color":"#80a0c0"}}]}"""))
        event("load")
        publish("text", mapOf("text" to "Map removed"))
        ui.onNodeWithText("Map removed").assertIsDisplayed()
    }
    @Test fun mediaLoadsBundledAudioAndReleasesOnRemoval() {
        publish("media-player", mapOf("height" to 200, "source" to "asset:///sample.wav"))
        event("load")
        publish("text", mapOf("text" to "Player removed"))
        ui.onNodeWithText("Player removed").assertIsDisplayed()
    }
    @Test fun webViewLoadsInlineHtmlAndReleasesOnRemoval() {
        publish("web-view", mapOf("height" to 180, "html" to "<html><body>Test content</body></html>"))
        event("load")
        publish("text", mapOf("text" to "WebView removed"))
        ui.onNodeWithText("WebView removed").assertIsDisplayed()
    }
    @Test fun cameraCapturesIntoAppCache() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.uiAutomation.grantRuntimePermission(instrumentation.targetContext.packageName, android.Manifest.permission.CAMERA)
        publish("camera", mapOf("active" to true))
        ui.waitUntil(15000) {
            ui.onAllNodes(hasTestTag("control/capture") and isEnabled()).fetchSemanticsNodes().isNotEmpty()
        }
        ui.onNodeWithTag("control/capture").performClick()
        val result = event("capture")
        val uri = android.net.Uri.parse(result.substringAfter("\"capture\" \"").substringBefore('"'))
        val file = java.io.File(uri.path!!)
        try { assertTrue(file.length() > 1000) } finally { assertTrue(file.delete()) }
        publish("text", mapOf("text" to "Camera removed"))
        ui.onNodeWithText("Camera removed").assertIsDisplayed()
    }
    @Test fun documentPickerCancellationReturnsToPlainHost() = cancelPicker("document-picker")
    @Test fun photoPickerCancellationReturnsToPlainHost() = cancelPicker("photo-picker")
    private fun cancelPicker(type: String) {
        publish(type, emptyMap())
        ui.onNodeWithTag("control").performClick()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        // Wait until the external provider's window is focused, then cancel.
        ui.waitUntil(5000) {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            root != null && root.packageName?.toString() != instrumentation.targetContext.packageName
        }
        instrumentation.uiAutomation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
        event("dismiss")
        ui.onNodeWithTag("control").assertIsDisplayed().assertIsEnabled()
    }
}
