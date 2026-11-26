package com.itsash.bolo

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.io.File

/**
 * Continuous dictation on top of SpeechRecognizer, prefering on-device recognition.
 *
 * The recognizer stops after a pause, so every end of a session (result, no match, timeout) starts
 * a new one while [active]. Dart merges the finals (lib/speech/transcript.dart); this class only
 * reports events: partial, final, state, error, notice, level.
 *
 * Two mic modes:
 *  - text only: the recognizer opens the mic itself (works everywhere).
 *  - text + audio (Android 13+): [AudioTee] owns the mic, saves a WAV and feeds the recognizer
 *    through EXTRA_AUDIO_SOURCE. If the recognizer refuses that before producing any text, the
 *    engine drops to text only and sends a notice.
 *
 * Everything runs on the main thread.
 */
class SpeechEngine(private val context: Context, private val emit: (Map<String, Any?>) -> Unit) {

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var tee: AudioTee? = null
    private var teeFile: File? = null
    private var pendingReadEnd: ParcelFileDescriptor? = null
    private var restartTask: Runnable? = null
    private var stopTimeout: Runnable? = null
    private var stoppedAudioPath: String? = null
    private var stoppedDurationMs = 0L

    private var active = false
    private var sessionOpen = false
    private var language = ""
    private var gotAnyResult = false
    private var busyRetries = 0
    private var stopDone: ((Map<String, Any?>) -> Unit)? = null
    private var lastLevel = 0L

    val isActive get() = active

    fun onDeviceAvailable(): Boolean =
        Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    fun recognizerAvailable(): Boolean = onDeviceAvailable() || SpeechRecognizer.isRecognitionAvailable(context)

    /** Returns true when audio is also being kept. */
    fun start(lang: String, keepAudio: Boolean, audioFile: File): Boolean {
        if (active) return tee != null
        language = lang
        active = true
        gotAnyResult = false
        busyRetries = 0
        stopDone = null
        tee = null
        teeFile = null
        stoppedAudioPath = null
        stoppedDurationMs = 0L
        if (keepAudio && Build.VERSION.SDK_INT >= 33) {
            val t = AudioTee(audioFile)
            if (t.start()) {
                tee = t
                teeFile = audioFile
            } else {
                emit(mapOf("type" to "notice", "code" to "audio_unavailable"))
            }
        } else if (keepAudio) {
            emit(mapOf("type" to "notice", "code" to "audio_needs_13"))
        }
        try {
            beginSession()
        } catch (e: Exception) {
            release()
            throw e
        }
        return tee != null
    }

    private fun createRecognizer(): SpeechRecognizer? {
        val r = when {
            onDeviceAvailable() -> SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            SpeechRecognizer.isRecognitionAvailable(context) -> SpeechRecognizer.createSpeechRecognizer(context)
            else -> null
        } ?: return null
        r.setRecognitionListener(listener)
        return r
    }

    private fun beginSession() {
        if (!active) return
        if (recognizer == null) recognizer = createRecognizer()
        val r = recognizer
        if (r == null) {
            fail("no_recognizer", false)
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            if (language.isNotEmpty()) {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, language)
            }
        }
        var readEnd: ParcelFileDescriptor? = null
        val t = tee
        if (t != null && Build.VERSION.SDK_INT >= 33) {
            readEnd = t.newPipe()
            intent.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readEnd)
            intent.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            intent.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            intent.putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, AudioTee.RATE)
        }
        try {
            sessionOpen = true
            r.startListening(intent)
            emit(mapOf("type" to "state", "listening" to true))
        } catch (e: Exception) {
            sessionOpen = false
            runCatching { readEnd?.close() }
            readEnd = null
            fail("start_failed", false)
        }
        // The recognizer got its own copy of the descriptor with the call above.
        readEnd?.let { fd ->
            closePendingReadEnd()
            pendingReadEnd = fd
            handler.postDelayed({
                runCatching { fd.close() }
                if (pendingReadEnd === fd) pendingReadEnd = null
            }, 1500)
        }
    }

    private fun cancelTimers() {
        restartTask?.let { handler.removeCallbacks(it) }
        restartTask = null
        stopTimeout?.let { handler.removeCallbacks(it) }
        stopTimeout = null
    }

    private fun closePendingReadEnd() {
        pendingReadEnd?.let { runCatching { it.close() } }
        pendingReadEnd = null
    }

    private fun scheduleRestart(delay: Long = 250) {
        sessionOpen = false
        if (stopDone != null) {
            finish()
            return
        }
        if (!active) return
        restartTask?.let { handler.removeCallbacks(it) }
        val task = Runnable {
            restartTask = null
            beginSession()
        }
        restartTask = task
        handler.postDelayed(task, delay)
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}

        override fun onRmsChanged(rmsdB: Float) {
            val now = System.currentTimeMillis()
            if (now - lastLevel < 80) return
            lastLevel = now
            // With the tee the recognizer sees no mic, so use our own peak level.
            val level = tee?.level ?: ((rmsdB.coerceIn(0f, 10f)) / 10.0)
            emit(mapOf("type" to "level", "value" to level))
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text = first(partialResults) ?: return
            emit(mapOf("type" to "partial", "text" to text))
        }

        override fun onResults(results: Bundle?) {
            val text = first(results)
            if (!text.isNullOrBlank()) {
                gotAnyResult = true
                busyRetries = 0
                emit(mapOf("type" to "final", "text" to text))
            }
            scheduleRestart()
        }

        override fun onError(error: Int) {
            sessionOpen = false
            if (stopDone != null) {
                finish()
                return
            }
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> scheduleRestart()
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> {
                    if (++busyRetries > 3) fail("busy", false) else {
                        recognizer?.destroy()
                        recognizer = null
                        scheduleRestart(600)
                    }
                }
                SpeechRecognizer.ERROR_CLIENT -> {
                    // Happens right after cancel/stop; also when the recognizer rejects the audio source.
                    if (!dropAudioIfFresh()) scheduleRestart(400)
                }
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> fail("permission", false)
                SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED, SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
                    fail("language", true)
                SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                SpeechRecognizer.ERROR_SERVER, SpeechRecognizer.ERROR_SERVER_DISCONNECTED,
                SpeechRecognizer.ERROR_TOO_MANY_REQUESTS ->
                    if (!dropAudioIfFresh()) fail("offline_missing", true)
                else -> if (!dropAudioIfFresh()) fail("error_$error", false)
            }
        }
    }

    /**
     * Text + audio mode and the recognizer failed before it ever gave text: assume it does not
     * accept an app-supplied audio source. Fall back to text only. Returns true if it did.
     */
    private fun dropAudioIfFresh(): Boolean {
        val t = tee ?: return false
        if (gotAnyResult) return false
        closePendingReadEnd()
        t.discard()
        tee = null
        teeFile = null
        recognizer?.destroy()
        recognizer = null
        emit(mapOf("type" to "notice", "code" to "audio_unsupported"))
        scheduleRestart(300)
        return true
    }

    private fun first(b: Bundle?): String? =
        b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()

    private fun fail(code: String, offlineMissing: Boolean) {
        emit(mapOf("type" to "error", "code" to code, "offlineMissing" to offlineMissing))
        // Keep the audio and whatever text Dart already has: just stop listening.
        active = false
        sessionOpen = false
        cancelTimers()
        closePendingReadEnd()
        runCatching { recognizer?.destroy() }
        recognizer = null
        tee?.let {
            stoppedDurationMs = it.stop()
            stoppedAudioPath = teeFile?.absolutePath
        }
        tee = null
        teeFile = null
        emit(mapOf("type" to "state", "listening" to false))
    }

    /** Ends dictation. [done] gets {audioPath, durationMs} once the last text has been delivered. */
    fun stop(done: (Map<String, Any?>) -> Unit) {
        if (stopDone != null) {
            done(mapOf("audioPath" to null, "durationMs" to 0))
            return
        }
        if (!active && recognizer == null && tee == null && stoppedAudioPath == null) {
            done(mapOf("audioPath" to null, "durationMs" to 0))
            return
        }
        active = false
        cancelTimers()
        stopDone = done
        if (sessionOpen) {
            runCatching { recognizer?.stopListening() }
            // The recognizer should answer with a result soon; do not wait forever.
            val timeout = Runnable {
                stopTimeout = null
                finish()
            }
            stopTimeout = timeout
            handler.postDelayed(timeout, 1500)
        } else {
            finish()
        }
    }

    private fun finish() {
        val done = stopDone ?: return
        stopDone = null
        cancelTimers()
        closePendingReadEnd()
        sessionOpen = false
        runCatching { recognizer?.destroy() }
        recognizer = null
        var path = stoppedAudioPath
        var duration = stoppedDurationMs
        stoppedAudioPath = null
        stoppedDurationMs = 0L
        tee?.let {
            duration = it.stop()
            path = teeFile?.absolutePath
        }
        tee = null
        teeFile = null
        active = false
        emit(mapOf("type" to "state", "listening" to false))
        done(mapOf("audioPath" to path, "durationMs" to duration))
    }

    fun release() {
        active = false
        sessionOpen = false
        cancelTimers()
        closePendingReadEnd()
        runCatching { recognizer?.destroy() }
        recognizer = null
        tee?.discard()
        tee = null
        teeFile = null
        stoppedAudioPath = null
        stoppedDurationMs = 0L
        stopDone = null
    }

    /** Best-effort: ask the on-device recognizer to download the pack for [lang] (Android 13+). */
    fun triggerDownload(lang: String) {
        if (Build.VERSION.SDK_INT < 33 || !onDeviceAvailable()) return
        runCatching {
            val r = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                if (lang.isNotEmpty()) putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
            }
            r.triggerModelDownload(i)
            handler.postDelayed({ runCatching { r.destroy() } }, 5000)
        }
    }
}
