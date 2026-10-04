/*
 * SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
 * SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0
 */
package dev.egcl.compose

import android.content.Context
import android.text.Html
import android.util.AtomicFile
import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentLinkedQueue

internal fun lispString(text: String) = "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

/** App-private durable storage and bounded network IO, independent of rendering. */
internal class AppServices(context: Context) {
    private val state = AtomicFile(File(context.filesDir, "eg-compose-state.sexp"))
    private val executor = Executors.newFixedThreadPool(2)
    private val results = ConcurrentLinkedQueue<String>()
    @Volatile private var closed = false
    fun readState(): String? = if (state.baseFile.exists() || File(state.baseFile.path + ".bak").exists())
        state.openRead().use { it.readBytes().toString(Charsets.UTF_8) } else null
    fun writeState(text: String) {
        val output = state.startWrite()
        try { output.write(text.toByteArray(Charsets.UTF_8)); state.finishWrite(output) }
        catch (e: Exception) { state.failWrite(output); throw e }
    }
    fun request(id: Int, address: String, kind: String) {
        executor.execute {
            var status = 0
            val result = try {
                val response = download(address)
                status = response.first
                check(status in 200..299) { "HTTP $status" }
                val body = if (kind == "feed") parseFeed(response.second, response.third) else response.second
                "($id $status ${lispString(body)} nil)"
            } catch (e: Exception) { "($id $status nil ${lispString(e.message ?: "Network request failed")})" }
            if (!closed) results.add(result)
        }
    }
    fun poll(): String? = results.poll()
    fun close() { closed = true; executor.shutdownNow(); results.clear() }

    private fun download(address: String): Triple<Int, String, String> {
        var url = URL(address)
        val deadline = System.nanoTime() + 30_000_000_000L
        repeat(6) {
            require(url.protocol == "https" && url.userInfo == null) { "An HTTPS URL is required" }
            val connection = url.openConnection() as HttpURLConnection
            try {
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 10_000
                connection.readTimeout = 10_000
                connection.setRequestProperty("User-Agent", "EvergreenCompose/1.3")
                connection.setRequestProperty("Accept", "application/rss+xml, application/atom+xml, text/xml, text/plain, */*")
                val status = connection.responseCode
                if (status in listOf(301, 302, 303, 307, 308)) {
                    url = URL(url, connection.getHeaderField("Location") ?: error("Missing redirect location"))
                } else {
                    if (status !in 200..299) return Triple(status, "", url.toString())
                    val output = ByteArrayOutputStream()
                    connection.inputStream.use { input ->
                        val buffer = ByteArray(8192)
                        while (true) {
                            check(!Thread.currentThread().isInterrupted && System.nanoTime() < deadline) { "Request timed out" }
                            val count = input.read(buffer)
                            if (count < 0) break
                            check(output.size() + count <= 2 * 1024 * 1024) { "Response exceeds 2 MiB" }
                            output.write(buffer, 0, count)
                        }
                    }
                    val charset = connection.contentType?.substringAfter("charset=", "")?.substringBefore(';')?.trim()?.trim('"')
                    return Triple(status, output.toString(if (charset.isNullOrEmpty()) "UTF-8" else charset), url.toString())
                }
            } finally { connection.disconnect() }
        }
        error("Too many redirects")
    }
}

/** RSS 2.0 and Atom text/enclosures. Never resolve external entities or render feed HTML. */
internal fun parseFeed(xml: String, base: String): String {
    val parser = Xml.newPullParser()
    parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true)
    parser.setInput(xml.reader())
    val items = mutableListOf<String>()
    var fields: MutableMap<String, String>? = null
    var itemDepth = 0
    var field: String? = null
    var fieldDepth = 0
    var text = StringBuilder()
    var recognized = false
    fun plain(value: String) = Html.fromHtml(value.take(16000), Html.FROM_HTML_MODE_LEGACY).toString().trim().take(12000)
    fun link(value: String, audio: Boolean = false): String = try {
        val url = URL(URL(base), value.trim())
        if ((url.protocol == "https" || (!audio && url.protocol == "http")) && url.userInfo == null) url.toString() else ""
    } catch (_: Exception) { "" }
    while (parser.eventType != XmlPullParser.END_DOCUMENT) {
        when (parser.eventType) {
            XmlPullParser.DOCDECL -> error("DTD declarations are not supported")
            XmlPullParser.START_TAG -> {
                val name = parser.name.lowercase()
                if (parser.depth == 1) recognized = name in listOf("rss", "feed", "rdf")
                if (fields == null && name in listOf("item", "entry")) {
                    fields = linkedMapOf(); itemDepth = parser.depth
                } else if (fields != null && parser.depth == itemDepth + 1) {
                    field = name; fieldDepth = parser.depth; text = StringBuilder()
                    if (name == "enclosure" || name == "link") {
                        val href = parser.getAttributeValue(null, "url") ?: parser.getAttributeValue(null, "href")
                        val relation = parser.getAttributeValue(null, "rel") ?: "alternate"
                        if (href != null) {
                            if (name == "enclosure" || relation == "enclosure") {
                                val type = parser.getAttributeValue(null, "type") ?: "audio/unknown"
                                if ((type.startsWith("audio/") || type.startsWith("video/"))) fields["audio"] = link(href, true)
                            } else if (relation == "alternate") fields["link"] = link(href)
                        }
                    }
                }
            }
            XmlPullParser.TEXT, XmlPullParser.CDSECT, XmlPullParser.ENTITY_REF ->
                if (field != null && text.length < 16000) text.append(parser.text ?: "")
            XmlPullParser.END_TAG -> {
                if (fields != null && parser.depth == fieldDepth && field != null) {
                    val value = text.toString().trim()
                    if (value.isNotEmpty()) fields[field] = value
                    field = null
                }
                if (fields != null && parser.depth == itemDepth) {
                    val title = plain(fields["title"] ?: "Untitled")
                    val target = fields["link"]?.let { link(it) } ?: ""
                    val key = fields["guid"] ?: fields["id"] ?: target.ifEmpty { title }
                    val summary = plain(fields["description"] ?: fields["summary"] ?: fields["encoded"] ?: fields["content"] ?: "")
                    val entry = linkedMapOf("key" to key.take(2048), "title" to title.take(512), "link" to target,
                        "summary" to summary, "author" to plain(fields["creator"] ?: fields["author"] ?: ""),
                        "date" to (fields["pubdate"] ?: fields["published"] ?: fields["updated"] ?: ""),
                        "audio" to (fields["audio"] ?: ""))
                    items.add(entry.entries.joinToString(" ", "(", ")") { ":${it.key} ${lispString(it.value)}" })
                    fields = null
                    if (items.size >= 50) break
                }
            }
        }
        parser.nextToken()
    }
    require(recognized) { "Not an RSS or Atom feed" }
    return items.joinToString(" ", "(", ")")
}
