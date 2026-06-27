package com.example.cam_ml

import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val arSupportChannel = "cam_ml/ar_support"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, arSupportChannel)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"isArSupported" -> {
						val supported = packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_AR)
						result.success(supported)
					}
					else -> result.notImplemented()
				}
			}
	}
}
