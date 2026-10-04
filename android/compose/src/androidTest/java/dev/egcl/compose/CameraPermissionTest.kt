/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */

package dev.egcl.compose

import android.Manifest
import android.content.pm.PackageManager
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.core.content.ContextCompat
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Run after revoking CAMERA on the isolated runtime app, before granting tests. */
class CameraPermissionTest {
    @get:Rule val ui = createAndroidComposeRule<ProbeActivity>()
    private var host: ComposeHost? = null
    @After fun close() { host?.close(); ui.waitForIdle() }
    private fun publish(active: Boolean) {
        host!!.publish("""{"protocol":1,"ack":0,"tree":{"id":"camera","type":"camera","props":{"active":$active},"children":[]}}""")
        ui.waitForIdle()
    }
    private fun allow(node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return false
        if (node.text?.toString() == "While using the app") return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        for (i in 0 until node.childCount) if (allow(node.getChild(i))) return true
        return false
    }
    @Test fun permissionGrantDoesNotOverrideANewerStop() {
        assertEquals("Run with CAMERA revoked on test runtime", PackageManager.PERMISSION_DENIED,
            ContextCompat.checkSelfPermission(ui.activity, Manifest.permission.CAMERA))
        host = ComposeHost(ui.activity)
        publish(true)
        ui.onNodeWithTag("camera/start").performClick()
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        ui.waitUntil(5000) { automation.rootInActiveWindow?.packageName?.toString()?.contains("permissioncontroller") == true }
        publish(false)
        assertTrue("Permission allow button", allow(automation.rootInActiveWindow))
        ui.waitUntil(5000) { ContextCompat.checkSelfPermission(ui.activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED }
        ui.waitForIdle()
        ui.onNodeWithTag("camera/start").assertExists()
        ui.onNodeWithTag("camera/capture").assertDoesNotExist()
    }
}
