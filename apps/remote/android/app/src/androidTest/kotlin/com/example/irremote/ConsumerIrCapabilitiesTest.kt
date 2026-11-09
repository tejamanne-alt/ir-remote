package com.example.irremote

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.ConsumerIrManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * M3 gate: runtime capability detection on a real Android runtime (emulator
 * in CI). Each reported value must agree with the platform API it comes from.
 * The Dart side (EmitterInfo.canTransmit) only trusts an emitter when the
 * feature flag and hasIrEmitter() both say yes.
 */
@RunWith(AndroidJUnit4::class)
class ConsumerIrCapabilitiesTest {
    private val context: Context =
        InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun reportsEveryField() {
        val caps = ConsumerIrCapabilities.detect(context)
        for (key in listOf("hasFeature", "hasEmitter", "carrierRanges", "manufacturer", "model", "sdkInt")) {
            assertTrue("missing $key", caps.containsKey(key))
        }
        assertEquals(Build.MANUFACTURER, caps["manufacturer"])
        assertEquals(Build.MODEL, caps["model"])
        assertEquals(Build.VERSION.SDK_INT, caps["sdkInt"])
    }

    @Test
    fun featureFlagMatchesPackageManager() {
        val caps = ConsumerIrCapabilities.detect(context)
        val expected = context.packageManager.hasSystemFeature(PackageManager.FEATURE_CONSUMER_IR)
        assertEquals(expected, caps["hasFeature"])
    }

    @Test
    fun emitterMatchesConsumerIrManager() {
        val caps = ConsumerIrCapabilities.detect(context)
        val manager = context.getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager
        assertEquals(manager?.hasIrEmitter() == true, caps["hasEmitter"])
    }
}
