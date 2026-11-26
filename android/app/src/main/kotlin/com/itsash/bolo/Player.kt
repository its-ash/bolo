package com.itsash.bolo

import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper

/** One-file-at-a-time audio playback. Sends {type: play, playing, path, posMs, durMs} events. */
class Player(private val emit: (Map<String, Any?>) -> Unit) {

    private val handler = Handler(Looper.getMainLooper())
    private var mp: MediaPlayer? = null
    private var path: String? = null

    private val tick = object : Runnable {
        override fun run() {
            val p = mp ?: return
            if (p.isPlaying) {
                send(true)
                handler.postDelayed(this, 250)
            }
        }
    }

    /** Plays [file] from the start, or resumes it if it is the paused file. */
    fun play(file: String): Boolean {
        val current = mp
        if (current != null && path == file) {
            current.start()
            handler.removeCallbacks(tick)
            handler.post(tick)
            send(true)
            return true
        }
        stop()
        return try {
            val p = MediaPlayer()
            mp = p
            path = file
            p.setDataSource(file)
            p.setOnCompletionListener {
                handler.removeCallbacks(tick)
                emit(mapOf("type" to "play", "playing" to false, "path" to file, "posMs" to 0, "durMs" to it.duration))
                release()
            }
            p.prepare()
            p.start()
            handler.removeCallbacks(tick)
            handler.post(tick)
            send(true)
            true
        } catch (e: Exception) {
            release()
            false
        }
    }

    fun pause() {
        val p = mp ?: return
        if (p.isPlaying) p.pause()
        handler.removeCallbacks(tick)
        send(false)
    }

    fun seek(ms: Int) {
        val p = mp ?: return
        p.seekTo(ms)
        send(p.isPlaying)
    }

    fun stop() {
        val file = path
        handler.removeCallbacks(tick)
        if (mp != null && file != null) {
            emit(mapOf("type" to "play", "playing" to false, "path" to file, "posMs" to 0, "durMs" to 0))
        }
        release()
    }

    private fun release() {
        runCatching { mp?.release() }
        mp = null
        path = null
    }

    private fun send(playing: Boolean) {
        val p = mp ?: return
        emit(
            mapOf(
                "type" to "play", "playing" to playing, "path" to path,
                "posMs" to p.currentPosition, "durMs" to p.duration,
            ),
        )
    }
}
