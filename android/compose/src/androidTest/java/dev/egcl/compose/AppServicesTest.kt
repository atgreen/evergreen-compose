/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */
package dev.egcl.compose

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppServicesTest {
    @Test fun rssEntitiesAndAudio() {
        val parsed = parseFeed("""<rss><channel><item><guid>stable</guid><title>A &amp; B</title><description><![CDATA[<p>Read <b>Lisp</b>.</p>]]></description><link>/article</link><enclosure url="https://example.org/audio.mp3" type="audio/mpeg"/></item></channel></rss>""", "https://example.org/rss")
        assertTrue(parsed.contains(":title \"A & B\""))
        assertTrue(parsed.contains("Read Lisp."))
        assertTrue(parsed.contains("https://example.org/article"))
        assertTrue(parsed.contains(":audio \"https://example.org/audio.mp3\""))
    }
    @Test fun atomNamespacesAndEscaping() {
        val parsed = parseFeed("""<feed xmlns="http://www.w3.org/2005/Atom"><entry><id>one</id><title>"Lisp"</title><author><name>Ada</name></author><link href="/one"/><summary>notes</summary></entry></feed>""", "https://example.org/feed")
        assertTrue(parsed.contains(":author \"Ada\""))
        assertTrue(parsed.contains("\\\"Lisp\\\""))
        assertTrue(parsed.contains("https://example.org/one"))
    }
    @Test fun rejectsUnsafeXmlAndNonFeeds() {
        for (xml in listOf("<html><body>Not a feed</body></html>", "<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><rss>&x;</rss>")) {
            try { parseFeed(xml, "https://example.org"); fail("Accepted invalid feed") }
            catch (_: Exception) { }
        }
    }
    @Test fun privateStateSurvivesNewServiceInstance() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val first = AppServices(context)
        first.writeState("(:draft \"a \\\"quote\\\"\" :saved nil)")
        first.close()
        val second = AppServices(context)
        assertEquals("(:draft \"a \\\"quote\\\"\" :saved nil)", second.readState())
        second.close()
    }
    @Test fun errorsReturnAsynchronously() {
        val service = AppServices(InstrumentationRegistry.getInstrumentation().targetContext)
        try {
            service.request(17, "file:///etc/passwd", "text")
            var result: String? = null
            val until = System.nanoTime() + 5_000_000_000L
            while (result == null && System.nanoTime() < until) { result = service.poll(); Thread.sleep(10) }
            assertNotNull(result)
            assertTrue(result!!.startsWith("(17 0 nil "))
        } finally { service.close() }
    }
}
