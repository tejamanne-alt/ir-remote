package com.astradite.irremote

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Holds a Wi-Fi MulticastLock only while hub discovery runs, as the build
 * contract requires. Dart calls acquireMulticastLock before discovery and
 * releaseMulticastLock when it ends.
 */
class NetworkChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "irremote/network")
    private val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    private var lock: WifiManager.MulticastLock? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquireMulticastLock" -> {
                if (lock == null) {
                    lock = wifi?.createMulticastLock("irremote-discovery")?.apply {
                        setReferenceCounted(false)
                        acquire()
                    }
                }
                result.success(lock != null)
            }
            "releaseMulticastLock" -> {
                release()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun release() {
        lock?.let { if (it.isHeld) it.release() }
        lock = null
    }

    fun dispose() {
        release()
        channel.setMethodCallHandler(null)
    }
}
