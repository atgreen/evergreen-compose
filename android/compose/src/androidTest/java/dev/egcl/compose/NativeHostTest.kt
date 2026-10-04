/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain

class NativeHostTest {
    private val ui = createEmptyComposeRule()
    private val activity = ActivityScenarioRule(PlainProbeActivity::class.java)
    @get:Rule val rules: RuleChain = RuleChain.outerRule(ui).around(activity)
    private var host: ComposeHost? = null
    @After fun close() { host?.close(); ui.waitForIdle() }

    @Test fun searchHasBackHandlingWithoutAComponentActivity() {
        activity.scenario.onActivity { host = ComposeHost(it) }
        host!!.publish("""{"protocol":1,"ack":0,"tree":{
          "id":"search","type":"search-bar","props":{"label":"Search","on-change":true},"children":[
            {"id":"result","type":"text","props":{"text":"Search result"},"children":[]}]}}""")
        ui.waitForIdle()
        assertNull(host!!.getFailure())
        ui.onNodeWithTag("search").performTouchInput { click() }
        ui.onNodeWithText("Search result").assertIsDisplayed()
        // Keyboard transitions run outside Compose's idle clock. Hide it before
        // testing the host's Back dispatch so it cannot consume this key event.
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val serviceInfo = automation.serviceInfo
        val originalFlags = serviceInfo.flags
        serviceInfo.flags = originalFlags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        automation.serviceInfo = serviceInfo
        try {
            automation.waitForIdle(500, 5000)
            androidx.test.espresso.Espresso.closeSoftKeyboard()
            ui.waitUntil(5000) {
                automation.windows.none { it.type == android.view.accessibility.AccessibilityWindowInfo.TYPE_INPUT_METHOD }
            }
            ui.runOnIdle { assertTrue("Search must register a Back callback", host!!.onBackPressedDispatcher.hasEnabledCallbacks()) }
            androidx.test.espresso.Espresso.pressBack()
            ui.waitUntil(5000) { ui.onAllNodesWithText("Search result").fetchSemanticsNodes().isEmpty() }
            ui.onNodeWithText("Search result").assertDoesNotExist()
            ui.onNodeWithTag("search").assertExists()
        } finally {
            serviceInfo.flags = originalFlags
            automation.serviceInfo = serviceInfo
        }
    }
}
