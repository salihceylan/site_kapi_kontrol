package com.example.site_kapi_kontrol

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.site_kapi_kontrol/wifi_helper"
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                    @Suppress("DEPRECATION")
                    wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "site_kapi_kontrol_wifilock")
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

