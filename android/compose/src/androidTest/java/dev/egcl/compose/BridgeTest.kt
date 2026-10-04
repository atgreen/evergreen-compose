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

class BridgeTest {
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

    @Test fun eventsAndUpdates() {
        publish(node("button", "counter", mapOf("text" to "Count: 0", "on-click" to true)))
        ui.onNodeWithTag("counter").performClick()
        assertEquals("(1 \"counter\" \"click\" \"\")", host!!.pollEvent())
        publish(node("button", "counter", mapOf("text" to "Count: 1", "on-click" to true)), 1)
        ui.onNodeWithText("Count: 1").assertIsDisplayed()
        assertNull(host!!.pollEvent())
    }
    @Test fun editingRejectsOldSnapshotsButAcceptsAcknowledgedChanges() {
        fun field(text: String) = node("text-field", "editor", mapOf("value" to text, "on-change" to true))
        publish(field(""))
        ui.onNodeWithTag("editor").performTextInput("héllo 🌱")
        val event = host!!.pollEvent()!!
        assertTrue(event.contains("héllo 🌱"))
        publish(field("outdated"), 0)
        ui.onNodeWithTag("editor").assertTextContains("héllo 🌱")
        publish(field("normalised"), 1)
        ui.onNodeWithTag("editor").assertTextContains("normalised")
    }
    @Test fun nestedDialogsHaveIndependentDismissal() {
        publish(node("column", "root", emptyMap(),
            node("dialog", "first", mapOf("on-dismiss" to true), node("text", "one", mapOf("text" to "First dialog"))),
            node("dialog", "second", mapOf("on-dismiss" to true), node("text", "two", mapOf("text" to "Second dialog")))))
        ui.onNodeWithText("Second dialog").assertIsDisplayed()
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
        var event: String? = null
        ui.waitUntil(5000) { event = host!!.pollEvent(); event != null }
        assertEquals("(1 \"second\" \"dismiss\" \"\")", event)
        publish(node("dialog", "first", mapOf("on-dismiss" to true), node("text", "one", mapOf("text" to "First dialog"))), 1)
        ui.onNodeWithText("First dialog").assertIsDisplayed()
    }
    @Test fun swipeAndLazyScrolling() {
        val swipe = node("swipe", "task", mapOf("on-right" to true, "on-left" to true, "fill-width" to true),
            node("text", "label", mapOf("text" to "Sample task", "height" to 80, "fill-width" to true)))
        val rows = (0..99).map { node("text", "row-$it", mapOf("text" to "Row $it", "height" to 60)) }
        publish(node("lazy-column", "list", mapOf("fill" to true), swipe, *rows.toTypedArray()))
        ui.onNodeWithTag("task").performTouchInput { swipeRight() }
        ui.waitForIdle()
        assertEquals("(1 \"task\" \"right\" \"\")", host!!.pollEvent())
        ui.onNodeWithTag("list").performScrollToIndex(80)
        ui.onNodeWithText("Row 79").assertIsDisplayed()
        assertNull(host!!.pollEvent()) // Scrolling never needs a Lisp round trip.
    }
    @Test fun pauseResumeAndDisposal() {
        val tree = node("button", "alive", mapOf("text" to "Still here", "on-click" to true))
        publish(tree)
        ui.activityRule.scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
        ui.activityRule.scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
        ui.onNodeWithTag("alive").performClick()
        assertEquals("(1 \"alive\" \"click\" \"\")", host!!.pollEvent())
        host!!.close()
        ui.waitForIdle()
        ui.onNodeWithTag("alive").assertDoesNotExist()
        host!!.close() // Disposal is idempotent; another controller can mount.
        host = null
        publish(tree)
        ui.onNodeWithText("Still here").assertIsDisplayed()
    }

    @Test fun siblingInsertionPreservesUnacknowledgedText() {
        val field = node("text-field", "editor", mapOf("value" to "saved", "on-change" to true))
        publish(node("column", "root", emptyMap(), field))
        ui.onNodeWithTag("editor").performTextReplacement("newer input")
        assertTrue(host!!.pollEvent()!!.contains("newer input"))
        publish(node("column", "root", emptyMap(),
            node("text", "notice", mapOf("text" to "New sibling")), field), 0)
        ui.onNodeWithTag("editor").assertTextContains("newer input")
        ui.onNodeWithTag("editor").assertIsFocused()
    }

    @Test fun incrementalSnapshotsRetainNodesAndApplyEdits() {
        val decoder = SnapshotDecoder()
        val initial = decoder.read("""{"protocol":1,"ack":0,"reset":true,"root":"root","nodes":[
          {"id":"root","type":"column","props":{},"children":["label","editor"]},
          {"id":"label","type":"text","props":{"text":"Before"},"children":[]},
          {"id":"editor","type":"text-field","props":{"value":"Kept"},"children":[]}] }""")
        val next = decoder.read("""{"protocol":1,"ack":1,"reset":false,"root":"root","nodes":[
          {"id":"label","type":"text","props":{"text":"After"},"children":[]}]}""")
        assertEquals("After", next.tree.children[0].text("text"))
        assertSame(initial.tree.children[1], next.tree.children[1])
        val last = decoder.read("""{"protocol":1,"ack":2,"reset":false,"root":"root","nodes":[]}""")
        assertSame(next.tree, last.tree)
    }
    @Test fun disabledFabDoesNotEmit() {
        publish(node("fab", "disabled", mapOf("text" to "Submit", "enabled" to false, "on-click" to true)))
        ui.onNodeWithTag("disabled").assertIsNotEnabled()
        ui.onNodeWithTag("disabled").performTouchInput { click() }
        assertNull(host!!.pollEvent())
    }

}
