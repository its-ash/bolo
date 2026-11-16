package com.itsash.bolo

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * MethodChannel "com.itsash.bolo/control" (Dart: lib/speech/speech_platform.dart):
 *   status() -> {files, sdk, mic, onDevice, available}
 *   requestMic() -> bool (system dialog; false if refused)
 *   start({lang, keepAudio, id}) -> {audio: bool}   audio = WAV is being kept for this note
 *   stop() -> {audioPath?, durationMs}              waits for the last text first
 *   openLanguageSettings({lang}), openAppSettings()
 *   play({path}) -> bool, pausePlay(), stopPlay(), seek({ms})
 *   shareText({text}), shareAudio({path})
 * EventChannel "com.itsash.bolo/events": maps with a "type" key, see SpeechEngine and Player.
 */
class MainActivity : FlutterActivity() {

    private var sink: EventChannel.EventSink? = null
    private lateinit var engine: SpeechEngine
    private lateinit var player: Player
    private var pendingMic: MethodChannel.Result? = null

    private fun send(event: Map<String, Any?>) {
        sink?.success(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        engine = SpeechEngine(this, ::send)
        player = Player(::send)

        EventChannel(messenger, "com.itsash.bolo/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })

        MethodChannel(messenger, "com.itsash.bolo/control").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "files" to filesDir.absolutePath,
                            "sdk" to android.os.Build.VERSION.SDK_INT,
                            "mic" to hasMic(),
                            "onDevice" to engine.onDeviceAvailable(),
                            "available" to engine.recognizerAvailable(),
                        ),
                    )
                    "requestMic" -> {
                        if (hasMic()) {
                            result.success(true)
                        } else {
                            pendingMic?.success(false)
                            pendingMic = result
                            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 77)
                        }
                    }
                    "start" -> {
                        val id = call.argument<String>("id") ?: System.currentTimeMillis().toString()
                        val keep = call.argument<Boolean>("keepAudio") ?: false
                        val lang = call.argument<String>("lang") ?: ""
                        player.stop()
                        val file = File(File(filesDir, "audio"), "$id.wav")
                        val audio = engine.start(lang, keep, file)
                        result.success(mapOf("audio" to audio))
                    }
                    "stop" -> engine.stop { result.success(it) }
                    "openLanguageSettings" -> {
                        val lang = call.argument<String>("lang") ?: ""
                        engine.triggerDownload(lang)
                        result.success(openLanguageSettings())
                    }
                    "openAppSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
                        )
                        result.success(null)
                    }
                    "play" -> result.success(player.play(call.argument<String>("path") ?: ""))
                    "pausePlay" -> {
                        player.pause()
                        result.success(null)
                    }
                    "stopPlay" -> {
                        player.stop()
                        result.success(null)
                    }
                    "seek" -> {
                        player.seek(call.argument<Number>("ms")?.toInt() ?: 0)
                        result.success(null)
                    }
                    "shareText" -> {
                        val i = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                        }
                        startActivity(Intent.createChooser(i, null))
                        result.success(null)
                    }
                    "shareAudio" -> {
                        val file = File(call.argument<String>("path") ?: "")
                        if (!file.exists()) {
                            result.error("missing", "Audio file not found", null)
                        } else {
                            val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                            val i = Intent(Intent.ACTION_SEND).apply {
                                type = "audio/wav"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(i, null))
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("failed", e.message, null)
            }
        }
    }

    private fun hasMic() =
        checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    /** Tries the Google speech pack screen first, then the generic voice and language settings. */
    private fun openLanguageSettings(): Boolean {
        val candidates = listOf(
            Intent().setComponent(
                ComponentName(
                    "com.google.android.googlequicksearchbox",
                    "com.google.android.apps.gsa.settingsui.VoiceSearchPreferences",
                ),
            ),
            Intent("android.settings.VOICE_INPUT_SETTINGS"),
            Intent(Settings.ACTION_LOCALE_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (i in candidates) {
            try {
                startActivity(i)
                return true
            } catch (_: ActivityNotFoundException) {
            } catch (_: SecurityException) {
            }
        }
        return false
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 77) {
            pendingMic?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingMic = null
        }
    }

    override fun onDestroy() {
        if (::engine.isInitialized) engine.release()
        if (::player.isInitialized) player.stop()
        super.onDestroy()
    }
}
