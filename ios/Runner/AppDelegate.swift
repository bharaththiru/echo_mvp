import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "echo.audio/methods"
  private var recorder: AVAudioRecorder?
  private var player: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      switch call.method {
      case "requestMicrophonePermission":
        self.requestMicrophonePermission(result: result)
      case "startRecording":
        if let args = call.arguments as? [String: Any],
           let path = args["path"] as? String {
          result(self.startRecording(path: path))
        } else {
          result(false)
        }
      case "stopRecording":
        result(self.stopRecording())
      case "startPlayback":
        if let args = call.arguments as? [String: Any],
           let path = args["path"] as? String {
          result(self.startPlayback(path: path))
        } else {
          result(false)
        }
      case "pausePlayback":
        result(self.pausePlayback())
      case "resumePlayback":
        result(self.resumePlayback())
      case "stopPlayback":
        result(self.stopPlayback())
      case "isPlaying":
        result(self.player?.isPlaying ?? false)
      case "getPlaybackPosition":
        let positionMs = Int((self.player?.currentTime ?? 0) * 1000)
        result(positionMs)
      case "getPlaybackDuration":
        let durationMs = Int((self.player?.duration ?? 0) * 1000)
        result(durationMs)
      case "seekTo":
        if let args = call.arguments as? [String: Any],
           let positionMs = args["positionMs"] as? Int {
          result(self.seekTo(positionMs: positionMs))
        } else {
          result(false)
        }
      case "setPlaybackVolume":
        if let args = call.arguments as? [String: Any],
           let volume = args["volume"] as? Double {
          self.player?.volume = Float(volume)
        }
        result(true)
      case "getAudioDuration":
        if let args = call.arguments as? [String: Any],
           let path = args["path"] as? String {
          result(self.getAudioDuration(path: path))
        } else {
          result(0)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func requestMicrophonePermission(result: @escaping FlutterResult) {
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      DispatchQueue.main.async {
        result(granted)
      }
    }
  }

  private func startRecording(path: String) -> Bool {
    stopRecording()
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .allowBluetooth]
      )
      try session.setActive(true)

      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
      ]
      let url = URL(fileURLWithPath: path)
      recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder?.prepareToRecord()
      recorder?.record()
      return true
    } catch {
      recorder = nil
      return false
    }
  }

  private func stopRecording() -> Bool {
    recorder?.stop()
    recorder = nil
    do {
      try AVAudioSession.sharedInstance().setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
    } catch {
      // Ignore deactivation failures.
    }
    return true
  }

  private func startPlayback(path: String) -> Bool {
    stopPlayback()
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playback,
        mode: .default,
        options: [.allowAirPlay, .allowBluetoothA2DP]
      )
      try session.setActive(true)

      let url = URL(fileURLWithPath: path)
      player = try AVAudioPlayer(contentsOf: url)
      player?.prepareToPlay()
      player?.play()
      return true
    } catch {
      player = nil
      return false
    }
  }

  private func pausePlayback() -> Bool {
    player?.pause()
    return true
  }

  private func resumePlayback() -> Bool {
    return player?.play() ?? false
  }

  private func stopPlayback() -> Bool {
    player?.stop()
    player = nil
    do {
      try AVAudioSession.sharedInstance().setActive(
        false,
        options: .notifyOthersOnDeactivation
      )
    } catch {
      // Ignore deactivation failures.
    }
    return true
  }

  private func seekTo(positionMs: Int) -> Bool {
    guard let p = player else { return false }
    p.currentTime = TimeInterval(positionMs) / 1000.0
    return true
  }

  private func getAudioDuration(path: String) -> Int {
    do {
      let url = URL(fileURLWithPath: path)
      let tempPlayer = try AVAudioPlayer(contentsOf: url)
      return Int(tempPlayer.duration * 1000)
    } catch {
      return 0
    }
  }
}
