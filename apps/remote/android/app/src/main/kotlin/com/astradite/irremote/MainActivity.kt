package com.astradite.irremote

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var consumerIr: ConsumerIrChannel? = null
    private var network: NetworkChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        consumerIr = ConsumerIrChannel(applicationContext, messenger)
        network = NetworkChannel(applicationContext, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        consumerIr?.dispose()
        consumerIr = null
        network?.dispose()
        network = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
