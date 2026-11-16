package com.itsash.bolo

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.util.concurrent.LinkedBlockingQueue
import kotlin.math.abs

/**
 * Owns the microphone while "keep audio" is on (Android 13+). It records 16 kHz mono PCM into a
 * WAV file and, at the same time, feeds the same samples to the speech recognizer through a pipe
 * (RecognizerIntent.EXTRA_AUDIO_SOURCE), so the recognizer never opens the mic itself and the two
 * do not fight over it. The pipe is replaced every time the recognizer session restarts.
 */
class AudioTee(private val file: File) {

    companion object {
        const val RATE = 16000
        private const val HEADER = 44
    }

    @Volatile private var feeder: PipeFeeder? = null
    @Volatile private var running = false
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    private var bytes = 0L

    /** Loudest sample of the last chunk, 0..1. Read by the engine for the level meter. */
    @Volatile var level = 0.0
        private set

    fun start(): Boolean {
        val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (min <= 0) return false
        val r = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, RATE,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, RATE),
            )
        } catch (e: Exception) {
            return false
        }
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            r.release()
            return false
        }
        file.parentFile?.mkdirs()
        val out = try {
            FileOutputStream(file).also { it.write(ByteArray(HEADER)) }
        } catch (e: Exception) {
            r.release()
            return false
        }
        try {
            r.startRecording()
        } catch (e: Exception) {
            r.release()
            out.close()
            return false
        }
        if (r.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            r.release()
            out.close()
            return false
        }
        record = r
        running = true
        thread = Thread {
            val buf = ByteArray(3200) // 100 ms
            try {
                while (running) {
                    val n = r.read(buf, 0, buf.size)
                    if (n <= 0) {
                        if (n < 0) break else continue
                    }
                    out.write(buf, 0, n)
                    bytes += n
                    var peak = 0
                    var i = 0
                    while (i + 1 < n) {
                        val s = (buf[i].toInt() and 0xFF) or (buf[i + 1].toInt() shl 8)
                        peak = maxOf(peak, abs(s.toShort().toInt()))
                        i += 2
                    }
                    level = peak / 32768.0
                    feeder?.offer(buf.copyOf(n))
                }
            } catch (_: Exception) {
            } finally {
                runCatching { out.close() }
            }
        }.also { it.start() }
        return true
    }

    /** Opens a new pipe for the next recognizer session and returns its read end. */
    fun newPipe(): ParcelFileDescriptor {
        val pair = ParcelFileDescriptor.createPipe()
        feeder?.close()
        feeder = PipeFeeder(pair[1])
        return pair[0]
    }

    fun closePipe() {
        feeder?.close()
        feeder = null
    }

    /** Stops recording and finishes the WAV header. Returns the duration in ms. */
    fun stop(): Long {
        running = false
        closePipe()
        runCatching { record?.stop() }
        thread?.join(1000)
        runCatching { record?.release() }
        record = null
        val data = bytes
        runCatching {
            RandomAccessFile(file, "rw").use { f -> f.write(wavHeader(data)) }
        }
        return data * 1000L / (RATE * 2)
    }

    fun discard() {
        stop()
        file.delete()
    }

    private fun wavHeader(data: Long): ByteArray {
        val h = java.nio.ByteBuffer.allocate(HEADER).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        h.put("RIFF".toByteArray()).putInt((36 + data).toInt())
        h.put("WAVE".toByteArray()).put("fmt ".toByteArray())
        h.putInt(16).putShort(1).putShort(1).putInt(RATE).putInt(RATE * 2).putShort(2).putShort(16)
        h.put("data".toByteArray()).putInt(data.toInt())
        return h.array()
    }
}

/** Writes chunks to the recognizer's pipe on its own thread so a slow reader never stalls recording. */
class PipeFeeder(pfd: ParcelFileDescriptor) {
    private val out = ParcelFileDescriptor.AutoCloseOutputStream(pfd)
    private val queue = LinkedBlockingQueue<ByteArray>(300)
    @Volatile private var open = true

    private val thread = Thread {
        try {
            while (true) {
                val b = queue.take()
                if (b.isEmpty()) break
                out.write(b)
            }
        } catch (_: Exception) {
        } finally {
            runCatching { out.close() }
        }
    }.also { it.start() }

    fun offer(b: ByteArray) {
        if (open) queue.offer(b)
    }

    fun close() {
        open = false
        queue.clear()
        queue.offer(ByteArray(0))
        runCatching { out.close() }
    }
}
