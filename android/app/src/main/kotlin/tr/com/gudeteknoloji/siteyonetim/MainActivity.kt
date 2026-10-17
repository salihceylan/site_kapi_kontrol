package tr.com.gudeteknoloji.siteyonetim

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "tr.com.gudeteknoloji.siteyonetim/wifi_helper"
    private val PUSH_CHANNEL = "tr.com.gudeteknoloji.siteyonetim/push"
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    // Telefon bildirimi (Faz 3b-B, docs/PLATFORM_BELGELER.md B5/B9): sunucu `android.notification.channel_id`
    // ile kanalı seçer; normal duyuru "announcements" (varsayılan önem), acil duyuru "urgent" (yüksek önem).
    // Oluşturma idempotenttir: var olan kanalın kullanıcı ayarları (ses, önem, kapalı) korunur.
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            manager.createNotificationChannel(
                NotificationChannel(
                    "announcements",
                    getString(R.string.push_channel_announcements),
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = getString(R.string.push_channel_announcements_description) }
            )
            manager.createNotificationChannel(
                NotificationChannel(
                    "urgent",
                    getString(R.string.push_channel_urgent),
                    NotificationManager.IMPORTANCE_HIGH
                ).apply { description = getString(R.string.push_channel_urgent_description) }
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Telefon bildirimi: Android API düzeyi (13 öncesinde bildirim izni sorulamaz, yalnız ayarlardan açılır).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PUSH_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "sdkInt") result.success(Build.VERSION.SDK_INT) else result.notImplemented()
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "bindToWifiNetwork" -> {
                    val success = bindToWifi()
                    result.success(success)
                }
                "unbindNetwork" -> {
                    val success = unbind()
                    result.success(success)
                }
                "isWifiConnected" -> {
                    val connected = isWifiConnected()
                    result.success(connected)
                }
                "acquireMulticastLock" -> {
                    acquireLocks()
                    result.success(true)
                }
                "releaseMulticastLock" -> {
                    releaseLocks()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        acquireLocks()
    }

    private fun acquireLocks() {
        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            if (wm != null) {
                if (multicastLock == null) {
                    multicastLock = wm.createMulticastLock("site_kapi_kontrol_multicast")
                    multicastLock?.setReferenceCounted(false)
                }
                if (multicastLock?.isHeld == false) {
                    multicastLock?.acquire()
                }

                if (wifiLock == null) {
                    val lockMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                    } else {
                        @Suppress("DEPRECATION")
                        WifiManager.WIFI_MODE_FULL_HIGH_PERF
                    }
                    wifiLock = wm.createWifiLock(lockMode, "site_kapi_kontrol_wifilock")
                    wifiLock?.setReferenceCounted(false)
                }
                if (wifiLock?.isHeld == false) {
                    wifiLock?.acquire()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun releaseLocks() {
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onResume() {
        super.onResume()
        acquireLocks()
    }

    override fun onPause() {
        releaseLocks()
        super.onPause()
    }

    private fun isWifiConnected(): Boolean {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
            for (network in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(network) ?: continue
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                    return true
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    private fun bindToWifi(): Boolean {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
            for (network in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(network) ?: continue
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        return cm.bindProcessToNetwork(network)
                    } else {
                        @Suppress("DEPRECATION")
                        return ConnectivityManager.setProcessDefaultNetwork(network)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    private fun unbind(): Boolean {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                return cm.bindProcessToNetwork(null)
            } else {
                @Suppress("DEPRECATION")
                return ConnectivityManager.setProcessDefaultNetwork(null)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    override fun onDestroy() {
        releaseLocks()
        unbind()
        super.onDestroy()
    }
}

