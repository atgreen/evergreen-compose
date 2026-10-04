/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.input.InputModeManager
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalTestApi::class, androidx.compose.ui.ExperimentalComposeUiApi::class)
class CatalogTest {
    @get:Rule val ui = createAndroidComposeRule<ProbeActivity>()
    private var host: ComposeHost? = null
    private fun node(type: String, id: String, props: Map<String, Any> = emptyMap(), vararg children: JSONObject) =
        JSONObject().put("type", type).put("id", id).put("props", JSONObject(props)).put("children", JSONArray(children.toList()))
    private fun raw(json: String) {
        if (host == null) host = ComposeHost(ui.activity)
        host!!.publish(json)
        ui.waitForIdle()
        assertNull(host!!.getFailure())
    }
    private fun publish(tree: JSONObject, ack: Int = 0) = raw(JSONObject().put("protocol", 1).put("ack", ack).put("tree", tree).toString())
    @After fun close() { host?.close(); ui.waitForIdle() }

    @Test fun allFiftyControlsRenderFromTheActualLispGallery() {
        val fixtures = InstrumentationRegistry.getInstrumentation().context.assets.open("catalog.jsonl").bufferedReader().readLines()
        fixtures.forEach { line ->
            val fixture = JSONObject(line)
            val json = fixture.getJSONObject("snapshot").toString()
            raw(json)
            val tree = SnapshotDecoder().read(json).tree
            fun find(n: Node, id: String): Node? = if (n.id == id) n else n.children.firstNotNullOfOrNull { find(it, id) }
            val list = find(tree, "section/${fixture.getString("name")}")
            if (list != null) list.children.indices.forEach { index ->
                ui.onNodeWithTag(list.id).performScrollToIndex(index)
                ui.waitForIdle()
                assertNull(host!!.getFailure())
            }
        }
    }

    @Test fun sliderRetainsUnacknowledgedValueAndAcceptsCorrection() {
        fun slider(value: Int) = node("slider", "slider", mapOf("value" to value, "on-change" to true))
        fun progress() = ui.onNodeWithTag("slider").fetchSemanticsNode().config[SemanticsProperties.ProgressBarRangeInfo].current
        publish(slider(20))
        ui.onNodeWithTag("slider").performSemanticsAction(SemanticsActions.SetProgress) { it(70f) }
        assertEquals("(1 \"slider\" \"change\" \"70\")", host!!.pollEvent())
        publish(slider(10), 0)
        assertEquals(70f, progress())
        publish(slider(30), 1)
        assertEquals(30f, progress())
        assertNull(host!!.pollEvent())
    }

    @Test fun rangeSliderReportsBothEndpoints() {
        publish(node("range-slider", "range", mapOf("value" to 20, "end" to 80, "on-change" to true)))
        ui.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.ProgressBarRangeInfo))[0]
            .performSemanticsAction(SemanticsActions.SetProgress) { it(40f) }
        assertEquals("(1 \"range\" \"change\" \"40,80\")", host!!.pollEvent())
        assertNull(host!!.pollEvent())
    }

    @Test fun rapidBooleanTogglesDoNotWaitForLisp() {
        listOf("switch", "checkbox", "icon-toggle-button").forEach { type ->
            publish(node(type, type, mapOf("checked" to false, "on-change" to true, "icon" to "favorite")))
            ui.onNodeWithTag(type).performClick()
            assertTrue(host!!.pollEvent()!!.contains("\"true\""))
            ui.onNodeWithTag(type).assertIsOn().performClick()
            assertTrue(host!!.pollEvent()!!.contains("\"false\""))
            ui.onNodeWithTag(type).assertIsOff()
        }
    }

    @Test fun pagersChangePagesLocallyAndAcknowledgeCorrections() {
        listOf("horizontal-pager", "vertical-pager").forEach { type ->
            fun pager(page: Int) = node(type, type, mapOf("page" to page, "height" to 200, "on-change" to true),
                *(0..3).map { node("text", "$type/$it", mapOf("text" to "Page $it", "fill" to true)) }.toTypedArray())
            publish(pager(0))
            ui.onNodeWithTag(type).performTouchInput { if (type == "horizontal-pager") swipeLeft() else swipeUp() }
            ui.waitForIdle()
            val event = host!!.pollEvent()!!
            assertTrue(event.contains("\"change\" \"1\""))
            val sequence = event.substringAfter('(').substringBefore(' ').toInt()
            publish(pager(0), sequence - 1)
            ui.onNodeWithTag("$type/1").assertIsDisplayed()
            publish(pager(2), sequence)
            ui.onNodeWithTag("$type/2").assertIsDisplayed()
            assertNull(host!!.pollEvent())
        }
    }

    @Test fun dateSelectionUsesUtcMillisAndRejectsStaleSnapshots() {
        fun date(value: Long) = node("date-picker", "date", mapOf("value" to value, "on-change" to true))
        publish(date(0))
        ui.onNodeWithText("January 15", substring = true).performClick()
        ui.waitForIdle()
        assertEquals("(1 \"date\" \"change\" \"1209600000\")", host!!.pollEvent())
        publish(date(0), 0)
        ui.onNodeWithText("January 15", substring = true).assertIsSelected()
        publish(date(1296000000), 1)
        ui.onNodeWithText("January 16", substring = true).assertIsSelected()
        assertNull(host!!.pollEvent())
    }

    @Test fun timeInputReportsHourAndMinute() {
        publish(node("time-picker", "time", mapOf("hour" to 12, "minute" to 0, "input-mode" to true, "on-change" to true)))
        ui.onAllNodes(hasSetTextAction())[0].performTextReplacement("14")
        ui.waitForIdle()
        assertTrue(host!!.pollEvent()!!.contains("\"14,0\""))
    }

    @Test fun programmaticDateNormalizationDoesNotEmitUserEvents() {
        listOf("date-picker", "date-range-picker").forEach { type ->
            publish(node(type, type, mapOf("value" to 1791072000001L, "on-change" to true)))
            assertNull(host!!.pollEvent())
            publish(node(type, type, mapOf("value" to 1791158400001L, "on-change" to true)))
            assertNull(host!!.pollEvent())
        }
    }

    @Test fun disabledPickersBlockTouchAndAccessibilityEdits() {
        listOf("date-picker", "date-range-picker", "time-picker").forEach { type ->
            publish(node(type, type, mapOf("enabled" to false, "on-change" to true, "value" to 0)))
            ui.onNodeWithTag(type).assertIsNotEnabled().performTouchInput { click() }
            ui.waitForIdle()
            assertNull(host!!.pollEvent())
        }
    }

    @Test fun keyboardTraversalSkipsDisabledPicker() {
        val tree = Node.read(node("column", "root", emptyMap(),
            node("button", "before", mapOf("text" to "Before", "on-click" to true)),
            node("time-picker", "disabled-time", mapOf("input-mode" to true, "enabled" to false)),
            node("button", "after", mapOf("text" to "After", "on-click" to true))))
        lateinit var input: InputModeManager
        ui.setContent {
            input = LocalInputModeManager.current
            MaterialTheme { Render(tree, 0, { _, _, _ -> error("Disabled picker emitted an event") }) }
        }
        // Explicit keyboard mode also works on phones with no physical keyboard.
        ui.runOnIdle { assertTrue(input.requestInputMode(InputMode.Keyboard)) }
        ui.onNodeWithTag("before").performSemanticsAction(SemanticsActions.RequestFocus) { assertTrue(it()) }
        ui.onNodeWithTag("before").assertIsFocused()
        ui.onNodeWithTag("before").performKeyInput { pressKey(Key.Tab) }
        ui.onNodeWithTag("after").assertIsFocused()
    }

    @Test fun actionSelectionAndRemovalCallbacks() {
        listOf("text-button", "tonal-button", "assist-chip", "input-chip", "tri-state-checkbox", "radio-button", "list-item").forEach { type ->
            publish(node(type, type, mapOf("text" to "Tap", "on-click" to true)))
            ui.onNodeWithTag(type).performClick()
            assertTrue(host!!.pollEvent()!!.contains("\"$type\" \"click\""))
        }
        publish(node("input-chip", "contact", mapOf("text" to "Contact", "on-dismiss" to true)))
        ui.onNodeWithTag("contact/remove").performClick()
        assertTrue(host!!.pollEvent()!!.contains("\"contact\" \"dismiss\""))
        publish(node("segmented-buttons", "segments", emptyMap(),
            node("segment", "day", mapOf("text" to "Day", "selected" to true)),
            node("segment", "week", mapOf("text" to "Week", "on-click" to true))))
        ui.onNodeWithTag("week").performClick()
        assertTrue(host!!.pollEvent()!!.contains("\"week\" \"click\""))
    }

    @Test fun menusAndAlertsDeliverSemanticActions() {
        publish(node("dropdown-menu", "menu", mapOf("expanded" to true, "on-dismiss" to true),
            node("button", "anchor", mapOf("slot" to "anchor", "text" to "Menu")),
            node("menu-item", "copy", mapOf("text" to "Copy", "on-click" to true))))
        ui.onNodeWithTag("copy").performClick()
        assertEquals("(1 \"copy\" \"click\" \"\")", host!!.pollEvent())
        publish(node("alert-dialog", "alert", mapOf("title" to "Confirm", "text" to "Sample", "on-confirm" to true)), 1)
        ui.onNodeWithText("OK").performClick()
        assertEquals("(2 \"alert\" \"confirm\" \"\")", host!!.pollEvent())
    }

    @Test fun imagesLoadAndFailuresReachLisp() {
        publish(node("image", "image", mapOf("asset" to "sample.png", "description" to "Sample image", "width" to 100, "height" to 100, "on-error" to true)))
        ui.waitUntil(5000) { ui.onAllNodesWithContentDescription("Sample image").fetchSemanticsNodes().isNotEmpty() }
        ui.onNodeWithText("Image unavailable").assertDoesNotExist()
        assertNull(host!!.pollEvent())
        publish(node("image", "image", mapOf("asset" to "missing.png", "on-error" to true)))
        ui.waitUntil(5000) { ui.onAllNodesWithText("Image unavailable").fetchSemanticsNodes().isNotEmpty() }
        ui.waitForIdle()
        assertTrue(host!!.pollEvent()!!.contains("\"error\""))
    }
}
