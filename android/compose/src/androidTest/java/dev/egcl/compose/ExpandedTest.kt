/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ExpandedTest {
    @get:Rule val ui = createAndroidComposeRule<ProbeActivity>()
    private var host: ComposeHost? = null
    private fun node(type: String, id: String, props: Map<String, Any> = emptyMap(), vararg children: JSONObject) =
        JSONObject().put("type", type).put("id", id).put("props", JSONObject(props)).put("children", JSONArray(children.toList()))
    private fun publish(tree: JSONObject, ack: Int = 0) {
        if (host == null) host = ComposeHost(ui.activity)
        host!!.publish(JSONObject().put("protocol", 1).put("ack", ack).put("tree", tree).toString())
        ui.waitForIdle()
        assertNull(host!!.getFailure())
    }
    @After fun close() { host?.close(); ui.waitForIdle() }
    @Test fun stepperIsImmediateAndIgnoresStaleEcho() {
        fun stepper(value: Int) = node("number-stepper", "quantity", mapOf("value" to value, "min" to 0, "max" to 3))
        publish(stepper(0))
        ui.onNodeWithTag("quantity/increase").performClick().performClick()
        assertEquals("(1 \"quantity\" \"change\" \"1\")", host!!.pollEvent())
        assertEquals("(2 \"quantity\" \"change\" \"2\")", host!!.pollEvent())
        publish(stepper(0))
        ui.onNodeWithTag("quantity/value").assertTextEquals("2")
        publish(stepper(1), 2)
        ui.onNodeWithTag("quantity/value").assertTextEquals("1")
    }
    @Test fun accordionTogglesLocally() {
        publish(node("accordion", "details", mapOf("text" to "Details"), node("text", "body", mapOf("text" to "Expanded"))))
        ui.onNodeWithTag("body").assertDoesNotExist()
        ui.onNodeWithTag("details/toggle").performClick()
        ui.onNodeWithTag("body").assertIsDisplayed()
        ui.onNodeWithTag("details/toggle").performClick()
        ui.onNodeWithTag("body").assertDoesNotExist()
    }
    @Test fun otpKeepsLeadingZerosAndFiltersInput() {
        publish(node("otp-field", "code", mapOf("length" to 4)))
        ui.onNodeWithTag("code").performTextInput("0a12345")
        ui.onNodeWithTag("code").assertTextContains("0123")
        assertEquals("(1 \"code\" \"change\" \"0123\")", host!!.pollEvent())
    }
    @Test fun comboFiltersAndSelectsOptions() {
        publish(node("combo-box", "fruit", emptyMap(),
            node("option", "apple", mapOf("text" to "Apple", "value" to "a")),
            node("option", "pear", mapOf("text" to "Pear", "value" to "p"))))
        ui.onNodeWithTag("fruit/input").performTextInput("Pe")
        ui.onNodeWithTag("pear").performClick()
        assertTrue(host!!.pollEvent()!!.contains("\"change\" \"Pe\""))
        assertTrue(host!!.pollEvent()!!.contains("\"select\" \"p\""))
        ui.onNodeWithTag("fruit/input").assertTextContains("Pear")
    }

    @Test fun multipleOptionsToggleIndependently() {
        publish(node("multi-select", "choices", emptyMap(), node("option", "one", mapOf("text" to "One")), node("option", "two", mapOf("text" to "Two"))))
        ui.onNodeWithTag("one").performClick()
        ui.onNodeWithTag("two").performClick()
        ui.onNodeWithTag("one").performClick()
        assertEquals("(1 \"one\" \"change\" \"true\")", host!!.pollEvent())
        assertEquals("(2 \"two\" \"change\" \"true\")", host!!.pollEvent())
        assertEquals("(3 \"one\" \"change\" \"false\")", host!!.pollEvent())
    }
    @Test fun reorderAccessibilityChangesLocalOrderAndReportsMove() {
        publish(node("reorderable-list", "order", emptyMap(), node("text", "a", mapOf("text" to "Alpha")), node("text", "b", mapOf("text" to "Beta"))))
        val actions = ui.onNodeWithTag("a/row").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsActions.CustomActions]
        ui.runOnIdle { assertTrue(actions.first { it.label == "Move later" }.action()) }
        assertEquals("(1 \"order\" \"move\" \"0,1\")", host!!.pollEvent())
        assertTrue(ui.onNodeWithTag("b/row").fetchSemanticsNode().boundsInRoot.top < ui.onNodeWithTag("a/row").fetchSemanticsNode().boundsInRoot.top)
    }
    @Test fun calendarSelectsUtcDateAndBrowsesMonths() {
        publish(node("calendar", "calendar", mapOf("value" to 1791072000000L)))
        ui.onNodeWithTag("calendar/2026-10-05").performClick()
        assertEquals("(1 \"calendar\" \"change\" \"1791158400000\")", host!!.pollEvent())
        ui.onNodeWithTag("calendar/next").performClick()
        ui.onNodeWithTag("calendar/month").assertTextEquals("November 2026")
    }
    @Test fun tableSortsNumericValuesAndPaginates() {
        publish(node("data-table", "table", mapOf("page-size" to 2), node("table-column", "score", mapOf("text" to "Score", "numeric" to true)),
            node("table-row", "row9", emptyMap(), node("cell", "c9", mapOf("value" to 9))),
            node("table-row", "row2", emptyMap(), node("cell", "c2", mapOf("value" to 2))),
            node("table-row", "row10", emptyMap(), node("cell", "c10", mapOf("value" to 10)))))
        ui.onNodeWithTag("score").performClick()
        assertTrue(ui.onNodeWithTag("row2").fetchSemanticsNode().boundsInRoot.top < ui.onNodeWithTag("row9").fetchSemanticsNode().boundsInRoot.top)
        ui.onNodeWithTag("table/next").performClick()
        ui.onNodeWithTag("row10").assertIsDisplayed().performClick()
        assertEquals("(1 \"table\" \"select\" \"row10\")", host!!.pollEvent())
    }
    @Test fun refreshGestureEmitsOnceUntilAcknowledged() {
        publish(node("pull-to-refresh", "refresh", mapOf("height" to 300), node("lazy-column", "items", mapOf("fill" to true), node("text", "text", mapOf("text" to "Pull")))))
        ui.onNodeWithTag("items").performTouchInput { swipeDown(durationMillis = 500) }
        ui.waitForIdle()
        assertEquals("(1 \"refresh\" \"refresh\" \"\")", host!!.pollEvent())
    }
    @Test fun revealExposesActionWithoutActivatingIt() {
        publish(node("swipe-reveal", "swipe", mapOf("height" to 80), node("button", "delete", mapOf("slot" to "end", "text" to "Delete")),
            node("card", "front", mapOf("height" to 80, "fill-width" to true), node("text", "label", mapOf("text" to "Swipe")))))
        ui.onNodeWithTag("swipe").performTouchInput { swipeLeft() }
        ui.onNodeWithTag("delete").assertIsDisplayed()
        assertNull(host!!.pollEvent())
        ui.onNodeWithTag("delete").performClick()
        assertEquals("(1 \"delete\" \"click\" \"\")", host!!.pollEvent())
    }
    @Test fun asyncImageLoadsAndCanBeUnmounted() {
        publish(node("async-image", "image", mapOf("asset" to "sample.png", "height" to 160, "width" to 200)))
        var event: String? = null
        ui.waitUntil(5000) { event = host!!.pollEvent(); event != null }
        assertTrue(event!!.contains("\"load\""))
        publish(node("text", "replacement", mapOf("text" to "Removed")), 1)
        ui.onNodeWithTag("replacement").assertIsDisplayed()
    }

    @Test fun chartRespectsChangedEnabledFlag() {
        host = ComposeHost(ui.activity)
        host!!.publish("""{"protocol":1,"ack":0,"reset":true,"root":"chart","nodes":[
          {"type":"point","id":"point","props":{"text":"One","value":5},"children":[]},
          {"type":"chart","id":"chart","props":{"enabled":true},"children":["point"]}]}""")
        ui.waitForIdle()
        ui.onNodeWithTag("chart").performTouchInput { click() }
        assertNotNull(host!!.pollEvent())
        host!!.publish("""{"protocol":1,"ack":0,"reset":false,"root":"chart","nodes":[
          {"type":"chart","id":"chart","props":{"enabled":false},"children":["point"]}]}""")
        ui.waitForIdle()
        ui.onNodeWithTag("chart").performTouchInput { click() }
        assertNull(host!!.pollEvent())
    }
    @Test fun cameraAcceptsProgrammaticStop() {
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.grantRuntimePermission(ui.activity.packageName, android.Manifest.permission.CAMERA)
        publish(node("camera", "camera", mapOf("active" to true)))
        ui.onNodeWithTag("camera/capture").assertExists()
        publish(node("camera", "camera", mapOf("active" to false)))
        ui.onNodeWithTag("camera/start").assertExists()
        ui.onNodeWithTag("camera/capture").assertDoesNotExist()
    }

    @Test fun calendarStaleEchoDoesNotMoveTheMonth() {
        fun calendar(value: Long) = node("calendar", "calendar", mapOf("value" to value))
        publish(calendar(1790812800000L))
        ui.onNodeWithTag("calendar/2026-10-02").performClick()
        ui.onNodeWithTag("calendar/next").performClick()
        ui.onNodeWithTag("calendar/2026-11-02").performClick()
        publish(calendar(1790899200000L), 1)
        ui.onNodeWithTag("calendar/month").assertTextEquals("November 2026")
    }

    @Test fun unrelatedAckDoesNotResetBrowsedCalendarMonth() {
        val calendar = node("calendar", "calendar", mapOf("value" to 1790812800000L))
        publish(calendar)
        ui.onNodeWithTag("calendar/next").performClick()
        publish(calendar, 1)
        ui.onNodeWithTag("calendar/month").assertTextEquals("November 2026")
    }

    @Test fun longPressDragReordersWithoutWaitingForLisp() {
        publish(node("reorderable-list", "order", emptyMap(),
            node("text", "a", mapOf("text" to "Alpha")), node("text", "b", mapOf("text" to "Beta")), node("text", "c", mapOf("text" to "Gamma"))))
        val distance = ui.onNodeWithTag("b/row").fetchSemanticsNode().boundsInRoot.center.y - ui.onNodeWithTag("a/row").fetchSemanticsNode().boundsInRoot.center.y
        ui.onNodeWithTag("a/drag").performTouchInput {
            down(center); advanceEventTime(600); moveBy(androidx.compose.ui.geometry.Offset(0f, distance)); advanceEventTime(100); up()
        }
        assertEquals("(1 \"order\" \"move\" \"0,1\")", host!!.pollEvent())
    }
    @Test fun ratingEmitsNumericSelection() {
        publish(node("rating", "rating", mapOf("value" to 2)))
        ui.onNodeWithTag("rating/4").performClick()
        assertEquals("(1 \"rating\" \"change\" \"4\")", host!!.pollEvent())
    }
}
