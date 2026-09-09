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

import android.app.Activity
import android.content.Intent
import android.net.Uri
import com.sonicmesh.app.speech.SpeechRecognizerManager
import com.sonicmesh.app.speech.TextToSpeechManager

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.sonicmesh/control"
    private val EVENT_CHANNEL = "com.sonicmesh/events"
    private val PERMISSION_REQUEST_RECORD_AUDIO = 1001
    private val REQUEST_IMAGE_PICK = 1002

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingImageResult: MethodChannel.Result? = null
    private var pendingImageThumbnail: Boolean = true

    private lateinit var acousticEngine: AcousticEngine
    private lateinit var speechRecognizerManager: SpeechRecognizerManager
    private lateinit var textToSpeechManager: TextToSpeechManager

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val sendEvent: (Map<String, Any?>) -> Unit = { eventData ->
            mainHandler.post {
                eventSink?.success(eventData)
            }
        }

        acousticEngine = AcousticEngine(AcousticConfig.DEFAULT, context = this, onEvent = sendEvent)
        speechRecognizerManager = SpeechRecognizerManager(this, sendEvent)
        textToSpeechManager = TextToSpeechManager(this, sendEvent)

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
            "getIdentity" -> {
                result.success(acousticEngine.identityManager.toMap())
            }
            "startPing" -> {
                val loopback = call.argument<Boolean>("loopback") ?: false
                acousticEngine.sendPing(loopback)
                result.success(true)
            }
            "sendPrivateMessage" -> {
                val receiverId = call.argument<Int>("receiverId") ?: 0
                val message = call.argument<String>("message") ?: ""
                acousticEngine.sendPrivateMessage(receiverId, message)
                result.success(true)
            }
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
            "renameDevice" -> {
                val newName = call.argument<String>("name") ?: ""
                val success = acousticEngine.identityManager.renameDevice(newName)
                if (success) {
                    result.success(acousticEngine.identityManager.toMap())
                } else {
                    result.error("RENAME_FAILED", "Could not rename device", null)
                }
            }
            "startRelayMode" -> {
                val guardDelayMs = (call.argument<Int>("guardDelayMs") ?: 500).toLong()
                val repetitions = call.argument<Int>("repetitions") ?: 1
                val relayPrivate = call.argument<Boolean>("relayPrivate") ?: true
                acousticEngine.startRelayMode(guardDelayMs, repetitions, relayPrivate)
                result.success(true)
            }
            "stopRelayMode" -> {
                acousticEngine.stopRelayMode()
                result.success(true)
            }
            "getRelayStats" -> {
                result.success(acousticEngine.getRelayStats())
            }
            "testRelayPipeline" -> {
                val msg = call.argument<String>("message") ?: "Relay Node B Test Signal"
                val res = acousticEngine.testRelayPipeline(msg)
                result.success(res)
            }
            // Offline Speech-to-Text
            "startSpeechRecognition" -> {
                speechRecognizerManager.startListening()
                result.success(true)
            }
            "stopSpeechRecognition" -> {
                speechRecognizerManager.stopListening()
                result.success(true)
            }
            // Offline Text-to-Speech
            "ttsSpeak" -> {
                val text = call.argument<String>("text") ?: ""
                val ok = textToSpeechManager.speak(text)
                result.success(ok)
            }
            "ttsStop" -> {
                textToSpeechManager.stop()
                result.success(true)
            }
            "ttsPause" -> {
                textToSpeechManager.pause()
                result.success(true)
            }
            // Offline Image Transfer
            "pickImage" -> {
                pendingImageThumbnail = call.argument<Boolean>("isThumbnail") ?: true
                pendingImageResult = result
                try {
                    val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "image/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                    startActivityForResult(Intent.createChooser(intent, "Select Mesh Image"), REQUEST_IMAGE_PICK)
                } catch (e: Exception) {
                    pendingImageResult = null
                    result.error("PICKER_ERROR", e.message, null)
                }
            }
            "prepareImageFromBytes" -> {
                val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                val isThumbnail = call.argument<Boolean>("isThumbnail") ?: true
                val targetSize = if (isThumbnail) 64 else 128
                val prepared = acousticEngine.imageTransferManager?.prepareImageFromBytes(
                    bytes,
                    targetWidth = targetSize,
                    targetHeight = targetSize
                )
                if (prepared != null) {
                    result.success(mapOf(
                        "imageId" to prepared.imageId,
                        "width" to prepared.width,
                        "height" to prepared.height,
                        "fileSize" to prepared.fileSize,
                        "totalChunks" to prepared.totalChunks,
                        "estimatedDurationSec" to prepared.estimatedDurationSec,
                        "webpBytes" to prepared.webpBytes
                    ))
                } else {
                    result.error("IMAGE_PREP_FAILED", "Failed to compress/prepare image", null)
                }
            }
            "transmitImage" -> {
                val prepared = acousticEngine.imageTransferManager?.getLastPreparedImage()
                if (prepared != null) {
                    acousticEngine.sendImage(prepared)
                    result.success(true)
                } else {
                    result.error("NO_IMAGE_PREPARED", "No image prepared for transmission", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_IMAGE_PICK) {
            val res = pendingImageResult
            pendingImageResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri: Uri = data.data!!
                val prepared = acousticEngine.imageTransferManager?.prepareImageFromUri(uri, pendingImageThumbnail)
                if (prepared != null) {
                    res?.success(mapOf(
                        "imageId" to prepared.imageId,
                        "width" to prepared.width,
                        "height" to prepared.height,
                        "fileSize" to prepared.fileSize,
                        "totalChunks" to prepared.totalChunks,
                        "estimatedDurationSec" to prepared.estimatedDurationSec,
                        "webpBytes" to prepared.webpBytes
                    ))
                } else {
                    res?.error("IMAGE_PREP_FAILED", "Could not process image as WebP", null)
                }
            } else {
                res?.success(null)
            }
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
        speechRecognizerManager.destroy()
        textToSpeechManager.destroy()
        if (::acousticEngine.isInitialized) {
            acousticEngine.stopAll()
        }
    }
}
