package tr.com.gudeteknoloji.siteyonetim

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * "Paylaş" ile gelen dekontun tek bekleyen kaydı (Dalga 2 / 2B). Dosya cache/share_inbox altında tutulur (30 dakika), Dart tarafı bir kez okuyup siler.
 * Yalnız content:// kabul edilir; file:// ve uygulamanın kendi sağlayıcıları reddedilir (özel dosyalar sızmasın). Dosya adı ve içerik günlüğe yazılmaz.
 */
object ShareInbox {
    const val MAX_BYTES = 10 * 1024 * 1024
    private const val TTL_MS = 30 * 60 * 1000L
    private val ALLOWED = setOf("application/pdf", "image/jpeg", "image/png")

    private fun dir(context: Context): File = File(context.cacheDir, "share_inbox").apply { mkdirs() }

    /** Paylaşılan uri'yi kopyalar; başarıda true. Geçersiz kaynak/tür/boyut: false (hiçbir şey saklanmaz). */
    fun save(context: Context, uri: Uri?, declaredType: String?): Boolean {
        if (uri == null || uri.scheme != "content") return false
        val authority = uri.authority ?: return false
        if (authority.startsWith(context.packageName)) return false
        val resolver = context.contentResolver
        val mime = (resolver.getType(uri) ?: declaredType ?: "").lowercase()
        if (mime !in ALLOWED) return false
        var name = "dekont"
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0)?.let { if (it.isNotBlank()) name = it.take(120) }
        }
        val out = ByteArrayOutputStream()
        try {
            resolver.openInputStream(uri)?.use { input ->
                val buffer = ByteArray(16 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    out.write(buffer, 0, read)
                    if (out.size() > MAX_BYTES) return false
                }
            } ?: return false
        } catch (e: Exception) {
            return false
        }
        if (out.size() == 0) return false
        clear(context)
        File(dir(context), "pending.bin").writeBytes(out.toByteArray())
        File(dir(context), "pending.json").writeText(
            JSONObject().put("name", name).put("mime", mime).put("savedAt", System.currentTimeMillis()).toString()
        )
        return true
    }

    /** Bekleyen kaydı döndürür ve siler (süresi dolmuşsa null). */
    fun take(context: Context): Map<String, Any>? {
        val meta = File(dir(context), "pending.json")
        val data = File(dir(context), "pending.bin")
        try {
            if (!meta.exists() || !data.exists()) return null
            val json = JSONObject(meta.readText())
            if (System.currentTimeMillis() - json.getLong("savedAt") > TTL_MS) return null
            return mapOf("name" to json.getString("name"), "mime" to json.getString("mime"), "bytes" to data.readBytes())
        } catch (e: Exception) {
            return null
        } finally {
            clear(context)
        }
    }

    fun clear(context: Context) {
        File(dir(context), "pending.bin").delete()
        File(dir(context), "pending.json").delete()
    }
}
