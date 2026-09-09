package com.sonicmesh.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.sonicmesh.app.acoustic.AcousticConfig
import com.sonicmesh.app.acoustic.AcousticEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.sonicmesh/control"
    private val EVENT_CHANNEL = "com.sonicmesh/events"
    private val PERMISSION_REQUEST_RECORD_AUDIO = 1001

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null

    private lateinit var acousticEngine: AcousticEngine

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        acousticEngine = AcousticEngine(AcousticConfig.DEFAULT) { eventData ->
            mainHandler.post {
                eventSink?.success(eventData)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasAudioPermission" -> {
                val granted = ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED
                result.success(granted)
            }
            "requestAudioPermission" -> {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else {
                    pendingPermissionResult = result
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.RECORD_AUDIO),
                        PERMISSION_REQUEST_RECORD_AUDIO
                    )
                }
            }
            "startBroadcast" -> {
                val message = call.argument<String>("message") ?: ""
                val repetitions = call.argument<Int>("repetitions") ?: 1
                acousticEngine.broadcast(message, repetitions)
                result.success(true)
            }
            "requestRetransmission" -> {
                val missingSeq = (call.argument<Int>("missingSequence") ?: 1).toShort()
                val total = (call.argument<Int>("totalExpected") ?: 1).toShort()
                acousticEngine.sendRetransmissionRequest(missingSeq, total)
                result.success(true)
            }
            "stopBroadcast" -> {
                acousticEngine.stopAll()
                result.success(true)
            }
            "startListening" -> {
                acousticEngine.startListening()
                result.success(true)
            }
            "stopListening" -> {
                acousticEngine.stopListening()
                result.success(true)
            }
            "runLoopbackTest" -> {
                val message = call.argument<String>("message") ?: "SonicMesh Offline Acoustic Test"
                val res = acousticEngine.runLoopbackTest(message)
                result.success(res)
            }
            "getDiagnostics" -> {
                val res = acousticEngine.getDiagnostics()
                result.success(res)
            }
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_RECORD_AUDIO) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::acousticEngine.isInitialized) {
            acousticEngine.stopAll()
        }
    }
}
