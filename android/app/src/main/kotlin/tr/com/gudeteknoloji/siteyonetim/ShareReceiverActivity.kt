package tr.com.gudeteknoloji.siteyonetim

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast

/**
 * Banka uygulamasından "Paylaş > Site Yönetim" ile gelen dekont (Dalga 2 / 2B). AYRI etkinliktir: MainActivity'nin başlatma modu (singleTop) ve kapı akışı
 * değişmez. Arayüzsüzdür: dosyayı [ShareInbox]'a kopyalar, MainActivity'yi öne getirir ve kapanır. Dart tarafı bekleyen kaydı okuyup "Dekont bildir"
 * penceresini açar (oturum yoksa giriş sonrasında; kayıt 30 dakika bekler).
 */
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appContext = applicationContext
        val received = intent
        if (received?.action != Intent.ACTION_SEND) {
            finish()
            return
        }
        val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
            received.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            received.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        val type = received.type
        // Kopyalama arka planda (en çok 10 MB); izin, etkinlik bitmeden okunduğu için sürer.
        Thread {
            val ok = try {
                ShareInbox.save(appContext, uri, type)
            } catch (e: Exception) {
                false
            }
            runOnUiThread {
                if (ok) {
                    startActivity(
                        Intent(this, MainActivity::class.java).addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        )
                    )
                } else {
                    Toast.makeText(this, getString(R.string.share_receipt_rejected), Toast.LENGTH_LONG).show()
                }
                finish()
            }
        }.start()
    }
}
