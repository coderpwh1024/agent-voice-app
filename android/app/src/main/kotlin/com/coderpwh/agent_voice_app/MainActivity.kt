package com.coderpwh.agent_voice_app

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlin.concurrent.thread
import kotlin.math.max

class MainActivity : FlutterActivity(), MethodChannel.MethodCallHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audio by lazy {
        VoiceAudioEngine(
            mainHandler,
            getSystemService(AUDIO_SERVICE) as AudioManager,
        )
    }
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "agent_voice/audio").setMethodCallHandler(this)
        MethodChannel(messenger, "agent_voice/secure_session").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "read" -> result.success(readSecureSession())
                    "write" -> {
                        writeSecureSession(requireNotNull(call.arguments as? String))
                        result.success(null)
                    }
                    "delete" -> {
                        securePreferences().edit().remove(SECURE_SESSION_VALUE).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("secure_session", error.message, null)
            }
        }
        EventChannel(messenger, "agent_voice/microphone").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    audio.microphoneSink = events
                }

                override fun onCancel(arguments: Any?) {
                    audio.microphoneSink = null
                }
            },
        )
        EventChannel(messenger, "agent_voice/playback").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    audio.playbackSink = events
                }

                override fun onCancel(arguments: Any?) {
                    audio.playbackSink = null
                }
            },
        )
    }

    private fun securePreferences() =
        getSharedPreferences(SECURE_SESSION_PREFERENCES, MODE_PRIVATE)

    private fun sessionKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(SECURE_SESSION_KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                SECURE_SESSION_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    private fun writeSecureSession(value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, sessionKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val payload = ByteArray(cipher.iv.size + encrypted.size)
        cipher.iv.copyInto(payload)
        encrypted.copyInto(payload, cipher.iv.size)
        securePreferences().edit()
            .putString(SECURE_SESSION_VALUE, Base64.encodeToString(payload, Base64.NO_WRAP))
            .apply()
    }

    private fun readSecureSession(): String? {
        val encoded = securePreferences().getString(SECURE_SESSION_VALUE, null) ?: return null
        return try {
            val payload = Base64.decode(encoded, Base64.NO_WRAP)
            if (payload.size <= GCM_IV_BYTES) return null
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                sessionKey(),
                GCMParameterSpec(GCM_TAG_BITS, payload.copyOfRange(0, GCM_IV_BYTES)),
            )
            String(
                cipher.doFinal(payload.copyOfRange(GCM_IV_BYTES, payload.size)),
                Charsets.UTF_8,
            )
        } catch (_: Exception) {
            securePreferences().edit().remove(SECURE_SESSION_VALUE).apply()
            null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "requestMicrophonePermission" -> requestMicrophonePermission(result)
                "start" -> {
                    if (!hasMicrophonePermission()) {
                        result.error("microphone_permission", "Microphone permission is required", null)
                    } else {
                        audio.start()
                        result.success(null)
                    }
                }
                "enqueuePlayback" -> {
                    val pcm = call.argument<ByteArray>("pcm")
                        ?: throw IllegalArgumentException("pcm is required")
                    audio.enqueue(
                        pcm,
                        requireNotNull(call.argument<String>("responseId")),
                        requireNotNull(call.argument<Int>("segmentIndex")),
                    )
                    result.success(null)
                }
                "completeSegment" -> {
                    audio.completeSegment(
                        requireNotNull(call.argument<String>("responseId")),
                        requireNotNull(call.argument<Int>("segmentIndex")),
                        requireNotNull(call.argument<Int>("samples")),
                    )
                    result.success(null)
                }
                "completeResponse" -> {
                    audio.completeResponse(requireNotNull(call.argument<String>("responseId")))
                    result.success(null)
                }
                "cancelPlayback" -> {
                    audio.cancel(requireNotNull(call.argument<String>("responseId")))
                    result.success(null)
                }
                "pausePlayback" -> {
                    audio.pause()
                    result.success(null)
                }
                "resumePlayback" -> {
                    audio.resume()
                    result.success(null)
                }
                "stop" -> {
                    audio.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("native_audio", error.message, null)
        }
    }

    private fun hasMicrophonePermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestMicrophonePermission(result: MethodChannel.Result) {
        if (hasMicrophonePermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("permission_in_progress", "Microphone permission request is active", null)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            MICROPHONE_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MICROPHONE_PERMISSION_REQUEST) {
            pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }

    override fun onDestroy() {
        audio.stop()
        super.onDestroy()
    }

    companion object {
        private const val MICROPHONE_PERMISSION_REQUEST = 9021
        private const val SECURE_SESSION_PREFERENCES = "agent_voice_secure_session"
        private const val SECURE_SESSION_VALUE = "encrypted_value"
        private const val SECURE_SESSION_KEY_ALIAS = "agent_voice_session_key"
        private const val GCM_IV_BYTES = 12
        private const val GCM_TAG_BITS = 128
    }
}

private class VoiceAudioEngine(
    private val mainHandler: Handler,
    private val audioManager: AudioManager,
) {
    @Volatile
    var microphoneSink: EventChannel.EventSink? = null

    @Volatile
    var playbackSink: EventChannel.EventSink? = null

    private val running = AtomicBoolean(false)
    private val paused = AtomicBoolean(false)
    private val invalidResponses: MutableSet<String> = ConcurrentHashMap.newKeySet()
    private val commands = LinkedBlockingQueue<PlaybackCommand>()
    private val markers = CopyOnWriteArrayList<PlaybackMarker>()
    private val playbackLock = Any()
    private var record: AudioRecord? = null
    private var track: AudioTrack? = null
    private var aec: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var captureThread: Thread? = null
    private var playbackThread: Thread? = null
    private var monitorThread: Thread? = null
    private var writtenFrames = 0L
    private var audioRouteConfigured = false
    private var previousAudioMode: Int? = null
    private var previousSpeakerphoneOn: Boolean? = null
    private var previousCommunicationDevice: AudioDeviceInfo? = null
    private var previousVoiceCallVolume: Int? = null
    private var appliedVoiceCallVolume: Int? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        try {
            invalidResponses.clear()
            commands.clear()
            markers.clear()
            writtenFrames = 0
            configureAudioRoute()
            startPlayback()
            startCapture()
            startMonitor()
        } catch (error: Exception) {
            stop()
            throw error
        }
    }

    private fun configureAudioRoute() {
        previousAudioMode = audioManager.mode
        audioRouteConfigured = true
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            previousCommunicationDevice = audioManager.communicationDevice
            val currentDevice = audioManager.communicationDevice
            val shouldUseSpeaker = currentDevice == null ||
                currentDevice.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE ||
                currentDevice.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
            if (shouldUseSpeaker) {
                val speaker = audioManager.availableCommunicationDevices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                } ?: throw IllegalStateException("Built-in speaker is unavailable")
                if (!audioManager.setCommunicationDevice(speaker)) {
                    throw IllegalStateException("Unable to route voice playback to speaker")
                }
                ensureAudibleSpeakerVolume()
            }
        } else {
            @Suppress("DEPRECATION")
            previousSpeakerphoneOn = audioManager.isSpeakerphoneOn
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = true
            ensureAudibleSpeakerVolume()
        }
    }

    private fun ensureAudibleSpeakerVolume() {
        val current = audioManager.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
        val maximum = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
        val minimumAudible = (maximum * 7 + 9) / 10
        if (current < minimumAudible) {
            previousVoiceCallVolume = current
            appliedVoiceCallVolume = minimumAudible
            audioManager.setStreamVolume(
                AudioManager.STREAM_VOICE_CALL,
                minimumAudible,
                0,
            )
        }
    }

    private fun restoreAudioRoute() {
        if (!audioRouteConfigured) return
        try {
            val appliedVolume = appliedVoiceCallVolume
            val previousVolume = previousVoiceCallVolume
            if (
                appliedVolume != null &&
                previousVolume != null &&
                audioManager.getStreamVolume(AudioManager.STREAM_VOICE_CALL) == appliedVolume
            ) {
                audioManager.setStreamVolume(
                    AudioManager.STREAM_VOICE_CALL,
                    previousVolume,
                    0,
                )
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val previousDevice = previousCommunicationDevice
                val isStillAvailable = previousDevice != null &&
                    audioManager.availableCommunicationDevices.any { it.id == previousDevice.id }
                if (isStillAvailable) {
                    audioManager.setCommunicationDevice(previousDevice!!)
                } else {
                    audioManager.clearCommunicationDevice()
                }
            } else {
                @Suppress("DEPRECATION")
                audioManager.isSpeakerphoneOn = previousSpeakerphoneOn ?: false
            }
        } finally {
            audioManager.mode = previousAudioMode ?: AudioManager.MODE_NORMAL
            previousAudioMode = null
            previousSpeakerphoneOn = null
            previousCommunicationDevice = null
            previousVoiceCallVolume = null
            appliedVoiceCallVolume = null
            audioRouteConfigured = false
        }
    }

    private fun startCapture() {
        val minimum = AudioRecord.getMinBufferSize(
            INPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val bufferSize = max(minimum, 1280)
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            INPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize * 2,
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            throw IllegalStateException("AudioRecord initialization failed")
        }
        record = recorder
        if (AcousticEchoCanceler.isAvailable()) {
            aec = AcousticEchoCanceler.create(recorder.audioSessionId)?.apply { enabled = true }
        }
        if (NoiseSuppressor.isAvailable()) {
            noiseSuppressor = NoiseSuppressor.create(recorder.audioSessionId)?.apply {
                enabled = true
            }
        }
        recorder.startRecording()
        captureThread = thread(name = "agent-voice-capture", start = true) {
            val buffer = ByteArray(1280) // 40 ms of PCM16 at 16 kHz.
            while (running.get()) {
                val count = recorder.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                if (count > 0) {
                    val payload = buffer.copyOf(count - (count % 2))
                    mainHandler.post { microphoneSink?.success(payload) }
                } else if (count < 0 && running.get()) {
                    mainHandler.post {
                        microphoneSink?.error("capture_failed", "AudioRecord read failed: $count", null)
                    }
                    break
                }
            }
        }
    }

    private fun startPlayback() {
        val minimum = AudioTrack.getMinBufferSize(
            OUTPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val player = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(OUTPUT_SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(max(minimum, 9600))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        if (player.state != AudioTrack.STATE_INITIALIZED) {
            player.release()
            throw IllegalStateException("AudioTrack initialization failed")
        }
        track = player
        player.play()
        playbackThread = thread(name = "agent-voice-playback", start = true) {
            while (running.get()) {
                val command = try {
                    commands.take()
                } catch (_: InterruptedException) {
                    break
                }
                if (invalidResponses.contains(command.responseId)) continue
                when (command) {
                    is PlaybackCommand.Audio -> synchronized(playbackLock) {
                        var offset = 0
                        while (running.get() && offset < command.pcm.size) {
                            val count = player.write(
                                command.pcm,
                                offset,
                                command.pcm.size - offset,
                                AudioTrack.WRITE_BLOCKING,
                            )
                            if (count <= 0) break
                            offset += count
                            writtenFrames += count / 2L
                        }
                    }
                    is PlaybackCommand.SegmentDone -> markers.add(
                        PlaybackMarker.Segment(
                            command.responseId,
                            command.segmentIndex,
                            command.samples,
                            writtenFrames,
                        ),
                    )
                    is PlaybackCommand.ResponseDone -> markers.add(
                        PlaybackMarker.Response(command.responseId, writtenFrames),
                    )
                }
            }
        }
    }

    private fun startMonitor() {
        monitorThread = thread(name = "agent-voice-playback-monitor", start = true) {
            var wrapOffset = 0L
            var previousRaw = 0L
            while (running.get()) {
                val player = track
                if (player != null && player.state == AudioTrack.STATE_INITIALIZED && !paused.get()) {
                    val raw = player.playbackHeadPosition.toLong() and 0xffffffffL
                    if (raw < previousRaw) wrapOffset += 1L shl 32
                    previousRaw = raw
                    val played = wrapOffset + raw
                    val ready = markers.filter { it.targetFrame <= played }
                    ready.forEach { marker ->
                        if (markers.remove(marker) && !invalidResponses.contains(marker.responseId)) {
                            emitMarker(marker)
                        }
                    }
                }
                try {
                    Thread.sleep(20)
                } catch (_: InterruptedException) {
                    break
                }
            }
        }
    }

    private fun emitMarker(marker: PlaybackMarker) {
        val event: Map<String, Any> = when (marker) {
            is PlaybackMarker.Segment -> mapOf(
                "type" to "segment.completed",
                "responseId" to marker.responseId,
                "segmentIndex" to marker.segmentIndex,
                "playedSamples" to marker.samples,
            )
            is PlaybackMarker.Response -> mapOf(
                "type" to "response.finished",
                "responseId" to marker.responseId,
            )
        }
        mainHandler.post { playbackSink?.success(event) }
    }

    fun enqueue(pcm: ByteArray, responseId: String, segmentIndex: Int) {
        if (running.get() && !invalidResponses.contains(responseId)) {
            commands.offer(PlaybackCommand.Audio(responseId, segmentIndex, pcm.copyOf()))
        }
    }

    fun completeSegment(responseId: String, segmentIndex: Int, samples: Int) {
        if (running.get() && !invalidResponses.contains(responseId)) {
            commands.offer(PlaybackCommand.SegmentDone(responseId, segmentIndex, samples))
        }
    }

    fun completeResponse(responseId: String) {
        if (running.get() && !invalidResponses.contains(responseId)) {
            commands.offer(PlaybackCommand.ResponseDone(responseId))
        }
    }

    fun cancel(responseId: String) {
        invalidResponses.add(responseId)
        commands.removeIf { it.responseId == responseId }
        markers.removeIf { it.responseId == responseId }
        synchronized(playbackLock) {
            track?.pause()
            track?.flush()
            writtenFrames = track?.playbackHeadPosition?.toLong()?.and(0xffffffffL) ?: 0
            track?.play()
        }
    }

    fun pause() {
        paused.set(true)
        track?.pause()
    }

    fun resume() {
        paused.set(false)
        track?.play()
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        captureThread?.interrupt()
        playbackThread?.interrupt()
        monitorThread?.interrupt()
        try {
            record?.stop()
        } catch (_: IllegalStateException) {
        }
        synchronized(playbackLock) {
            try {
                track?.pause()
                track?.flush()
                track?.stop()
            } catch (_: IllegalStateException) {
            }
        }
        captureThread?.join(500)
        playbackThread?.join(500)
        monitorThread?.join(500)
        aec?.release()
        noiseSuppressor?.release()
        record?.release()
        track?.release()
        aec = null
        noiseSuppressor = null
        record = null
        track = null
        commands.clear()
        markers.clear()
        invalidResponses.clear()
        writtenFrames = 0
        restoreAudioRoute()
    }

    companion object {
        private const val INPUT_SAMPLE_RATE = 16000
        private const val OUTPUT_SAMPLE_RATE = 24000
    }
}

private sealed class PlaybackCommand(open val responseId: String) {
    data class Audio(
        override val responseId: String,
        val segmentIndex: Int,
        val pcm: ByteArray,
    ) : PlaybackCommand(responseId)

    data class SegmentDone(
        override val responseId: String,
        val segmentIndex: Int,
        val samples: Int,
    ) : PlaybackCommand(responseId)

    data class ResponseDone(override val responseId: String) : PlaybackCommand(responseId)
}

private sealed class PlaybackMarker(
    open val responseId: String,
    open val targetFrame: Long,
) {
    data class Segment(
        override val responseId: String,
        val segmentIndex: Int,
        val samples: Int,
        override val targetFrame: Long,
    ) : PlaybackMarker(responseId, targetFrame)

    data class Response(
        override val responseId: String,
        override val targetFrame: Long,
    ) : PlaybackMarker(responseId, targetFrame)
}
