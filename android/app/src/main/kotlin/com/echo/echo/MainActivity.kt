package com.echo.echo

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private val channelName = "echo.audio/methods"
    private val recordAudioRequestCode = 1001
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var recorder: MediaRecorder? = null
    private var player: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestMicrophonePermission" -> requestMicrophonePermission(result)
                    "startRecording" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(startRecording(path))
                    }
                    "stopRecording" -> result.success(stopRecording())
                    "startPlayback" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(startPlayback(path))
                    }
                    "pausePlayback" -> result.success(pausePlayback())
                    "resumePlayback" -> result.success(resumePlayback())
                    "stopPlayback" -> result.success(stopPlayback())
                    "isPlaying" -> result.success(player?.isPlaying ?: false)
                    "getPlaybackPosition" -> result.success(player?.currentPosition ?: 0)
                    "getPlaybackDuration" -> result.success(player?.duration ?: 0)
                    "seekTo" -> {
                        val positionMs = call.argument<Int>("positionMs") ?: 0
                        result.success(seekTo(positionMs))
                    }
                    "setPlaybackVolume" -> {
                        val volume = call.argument<Double>("volume") ?: 1.0
                        setPlaybackVolume(volume.toFloat())
                        result.success(true)
                    }
                    "getAudioDuration" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.success(0)
                            return@setMethodCallHandler
                        }
                        result.success(getAudioDuration(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestMicrophonePermission(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            recordAudioRequestCode
        )
    }

    private fun startRecording(path: String): Boolean {
        stopRecording()
        return try {
            recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                MediaRecorder()
            }
            recorder?.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioChannels(1)
                setAudioSamplingRate(44100)
                setOutputFile(path)
                prepare()
                start()
            }
            true
        } catch (ex: Exception) {
            recorder?.release()
            recorder = null
            false
        }
    }

    private fun stopRecording(): Boolean {
        return try {
            recorder?.apply {
                stop()
                reset()
                release()
            }
            recorder = null
            true
        } catch (ex: Exception) {
            recorder?.release()
            recorder = null
            false
        }
    }

    private fun startPlayback(path: String): Boolean {
        stopPlayback()
        return try {
            player = MediaPlayer().apply {
                setDataSource(path)
                prepare()
                start()
            }
            true
        } catch (ex: Exception) {
            player?.release()
            player = null
            false
        }
    }

    private fun pausePlayback(): Boolean {
        player?.pause()
        return true
    }

    private fun resumePlayback(): Boolean {
        return if (player == null) {
            false
        } else {
            player?.start()
            true
        }
    }

    private fun stopPlayback(): Boolean {
        return try {
            player?.apply {
                stop()
                release()
            }
            player = null
            true
        } catch (ex: Exception) {
            player?.release()
            player = null
            false
        }
    }

    private fun seekTo(positionMs: Int): Boolean {
        val p = player ?: return false
        return try {
            p.seekTo(positionMs)
            true
        } catch (ex: Exception) {
            false
        }
    }

    private fun setPlaybackVolume(volume: Float) {
        player?.setVolume(volume, volume)
    }

    private fun getAudioDuration(path: String): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            duration?.toIntOrNull() ?: 0
        } catch (ex: Exception) {
            0
        } finally {
            retriever.release()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == recordAudioRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
