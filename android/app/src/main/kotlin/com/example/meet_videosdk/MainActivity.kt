package com.example.meet_videosdk

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Hosts a native microphone level meter exposed to Flutter over an
 * [EventChannel]. While listening, it reads raw PCM from [AudioRecord] on a
 * background thread, computes the RMS amplitude per buffer, and streams a
 * normalised 0..1 level to Dart.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "videosdk/mic_level"
    private var meter: MicLevelMeter? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        if (events == null) return
                        meter = MicLevelMeter(events).also { it.start() }
                    }

                    override fun onCancel(arguments: Any?) {
                        meter?.stop()
                        meter = null
                    }
                },
            )
    }
}

private class MicLevelMeter(private val events: EventChannel.EventSink) {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var running = false
    private var thread: Thread? = null

    fun start() {
        if (running) return
        running = true
        thread = Thread { loop() }.also { it.start() }
    }

    fun stop() {
        running = false
        thread?.join(200)
        thread = null
    }

    private fun loop() {
        val sampleRate = 16000
        val minBuffer = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            emit(0.0)
            return
        }

        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                minBuffer * 2,
            )
        } catch (e: SecurityException) {
            emit(0.0)
            return
        }

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            emit(0.0)
            return
        }

        val buffer = ShortArray(minBuffer)
        try {
            record.startRecording()
            while (running) {
                val read = record.read(buffer, 0, buffer.size)
                if (read <= 0) continue
                var sumSquares = 0.0
                for (i in 0 until read) {
                    val sample = buffer[i].toDouble()
                    sumSquares += sample * sample
                }
                val rms = sqrt(sumSquares / read)
                // 32768 is the max magnitude of a signed 16-bit sample.
                emit(min(1.0, rms / 32768.0 * 6.0))
            }
        } catch (e: IllegalStateException) {
            emit(0.0)
        } finally {
            try {
                record.stop()
            } catch (e: IllegalStateException) {
                // already stopped
            }
            record.release()
        }
    }

    private fun emit(level: Double) {
        if (!running) return
        mainHandler.post {
            if (running) events.success(level)
        }
    }
}
