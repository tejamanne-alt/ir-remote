package com.example.irremote

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.ConsumerIrManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Bridges Dart to [ConsumerIrManager].
 *
 * - Capability detection uses both PackageManager.FEATURE_CONSUMER_IR and
 *   ConsumerIrManager.hasIrEmitter(); it is never inferred from brand or model.
 * - getCarrierFrequencies() may return null; that is reported as unknown.
 * - transmit() blocks until the pattern has been sent, so it runs on one
 *   background thread (a serial queue) and never on the UI thread. The measured
 *   duration of every call is logged.
 */
class ConsumerIrChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val manager: ConsumerIrManager? =
        context.getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCapabilities" -> result.success(capabilities())
            "transmit" -> transmit(call, result)
            else -> result.notImplemented()
        }
    }

    private fun capabilities(): Map<String, Any?> = ConsumerIrCapabilities.detect(context)

    private fun transmit(call: MethodCall, result: MethodChannel.Result) {
        val carrier = call.argument<Int>("carrierHz")
        val pattern = call.argument<IntArray>("pattern")
        val ir = manager
        if (carrier == null || pattern == null || pattern.isEmpty()) {
            result.error("INVALID", "carrierHz and a non-empty pattern are required", null)
            return
        }
        if (ir == null || !ir.hasIrEmitter()) {
            result.error("NO_EMITTER", "this phone has no IR emitter", null)
            return
        }
        executor.execute {
            val start = SystemClock.elapsedRealtimeNanos()
            try {
                ir.transmit(carrier, pattern)
                val elapsedUs = (SystemClock.elapsedRealtimeNanos() - start) / 1000
                Log.d(TAG, "transmit carrier=$carrier durations=${pattern.size} took ${elapsedUs}us")
                mainHandler.post { result.success(mapOf("elapsedUs" to elapsedUs)) }
            } catch (e: SecurityException) {
                mainHandler.post { result.error("PERMISSION", e.message, null) }
            } catch (e: IllegalArgumentException) {
                mainHandler.post { result.error("INVALID", e.message, null) }
            } catch (e: RuntimeException) {
                mainHandler.post { result.error("HARDWARE", e.message, null) }
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    companion object {
        private const val CHANNEL = "irremote/consumer_ir"
        private const val TAG = "ConsumerIr"
    }
}

/**
 * Runtime emitter detection, separate from the channel so instrumented tests
 * can call it directly. Uses both PackageManager.FEATURE_CONSUMER_IR and
 * ConsumerIrManager.hasIrEmitter(); never infers anything from brand or model.
 */
object ConsumerIrCapabilities {
    private const val TAG = "ConsumerIr"

    fun detect(context: Context): Map<String, Any?> {
        val manager = context.getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager
        val hasFeature =
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_CONSUMER_IR)
        val hasEmitter = try {
            manager?.hasIrEmitter() == true
        } catch (e: RuntimeException) {
            Log.w(TAG, "hasIrEmitter() failed", e)
            false
        }
        val ranges: List<List<Int>>? = try {
            manager?.carrierFrequencies?.map { listOf(it.minFrequency, it.maxFrequency) }
        } catch (e: RuntimeException) {
            Log.w(TAG, "getCarrierFrequencies() failed", e)
            null
        }
        if (hasEmitter && ranges == null) {
            Log.w(TAG, "getCarrierFrequencies() returned null; carrier ranges unknown")
        }
        return mapOf(
            "hasFeature" to hasFeature,
            "hasEmitter" to hasEmitter,
            "carrierRanges" to ranges,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "sdkInt" to Build.VERSION.SDK_INT,
        )
    }
}
