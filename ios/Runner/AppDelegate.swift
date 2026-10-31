import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var sampleChannel: FlutterMethodChannel?
  private var tikTokCacheChannel: FlutterMethodChannel?
  private let tikTokCacheQueue = DispatchQueue(label: "com.cloudio.tiktok.cache", qos: .utility)
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let cacheChannel = FlutterMethodChannel(name: "com.cloudiolabs.cloudio/tiktok_audio_cache", binaryMessenger: controller.binaryMessenger)
      tikTokCacheChannel = cacheChannel
      cacheChannel.setMethodCallHandler { call, result in
        self.tikTokCacheQueue.async {
          do {
            let value = try Self.handleTikTokCache(call)
            DispatchQueue.main.async { result(value) }
          } catch {
            DispatchQueue.main.async { result(FlutterError(code: "audio_cache_failed", message: "Audio TikTok belum dapat disiapkan", details: ["domain": (error as NSError).domain, "code": (error as NSError).code])) }
          }
        }
      }
      let channel = FlutterMethodChannel(name: "com.cloudiolabs.cloudio/audio_sample", binaryMessenger: controller.binaryMessenger)
      sampleChannel = channel
      channel.setMethodCallHandler { call, result in
        guard call.method == "decode" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: Any],
              let bytes = args["bytes"] as? FlutterStandardTypedData,
              bytes.data.count <= 12 * 1024 * 1024 else {
          result(FlutterError(code: "invalid_audio", message: "Audio tidak valid", details: nil)); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let pcm = try Self.decodeSample(bytes.data)
            DispatchQueue.main.async { result(["pcm": FlutterStandardTypedData(bytes: pcm), "sampleRate": 16000, "channels": 1]) }
          } catch {
            DispatchQueue.main.async { result(FlutterError(code: "decode_failed", message: "Audio tidak dapat dibaca", details: nil)) }
          }
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  private static func tikTokCacheDirectory() throws -> URL {
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("cloudio-tiktok-audio-v1", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // Remove abandoned downloads/exports from interrupted preparations only.
    let cutoff = Date().addingTimeInterval(-600)
    for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
      if file.lastPathComponent.hasPrefix("download-") || file.lastPathComponent.hasPrefix("export-") {
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if modified < cutoff { try? FileManager.default.removeItem(at: file) }
      }
    }
    return directory
  }

  private static func cachedTikTokAudio(_ id: String, directory: URL) -> URL? {
    for ext in ["m4a", "mp3"] {
      let file = directory.appendingPathComponent("sound-\(id).\(ext)")
      if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return file
      }
    }
    return nil
  }

  private static func handleTikTokCache(_ call: FlutterMethodCall) throws -> Any? {
    let directory = try tikTokCacheDirectory()
    if call.method == "directory" { return directory.path }
    let args = call.arguments as? [String: Any] ?? [:]
    guard let id = args["id"] as? String, id.range(of: "^[0-9]+$", options: .regularExpression) != nil else {
      throw NSError(domain: "CloudioCache", code: 1)
    }
    if call.method == "lookup" { return cachedTikTokAudio(id, directory: directory)?.path }
    if call.method == "remove" {
      for ext in ["m4a", "mp3"] { try? FileManager.default.removeItem(at: directory.appendingPathComponent("sound-\(id).\(ext)")) }
      return nil
    }
    if call.method == "info" {
      guard let file = cachedTikTokAudio(id, directory: directory) else { return nil }
      let asset = AVURLAsset(url: file)
      return ["path": file.path, "bytes": (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
              "audioTracks": asset.tracks(withMediaType: .audio).count,
              "videoTracks": asset.tracks(withMediaType: .video).count,
              "durationMs": Int(CMTimeGetSeconds(asset.duration) * 1000),
              "thermalState": ProcessInfo.processInfo.thermalState.rawValue]
    }
    guard call.method == "extract", let inputPath = args["inputPath"] as? String else { return FlutterMethodNotImplemented }
    let input = URL(fileURLWithPath: inputPath).resolvingSymlinksInPath()
    guard input.deletingLastPathComponent() == directory.resolvingSymlinksInPath(),
          input.lastPathComponent.hasPrefix("download-"),
          (try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 64 * 1024 * 1024 else {
      throw NSError(domain: "CloudioCache", code: 2)
    }
    if let cached = cachedTikTokAudio(id, directory: directory) { return cached.path }
    // AVFoundation does not recognize this MP4 when it is named .part.
    let handle = try FileHandle(forReadingFrom: input)
    let prefix = [UInt8](handle.readData(ofLength: 12))
    handle.closeFile()
    let suffix: String
    if prefix.count >= 8 && String(bytes: prefix[4..<8], encoding: .ascii) == "ftyp" { suffix = "mp4" }
    else if prefix.count >= 2 && prefix[0] == 0xff && prefix[1] & 0xf6 == 0xf0 { suffix = "aac" }
    else { suffix = "mp3" }
    let staged = directory.appendingPathComponent("download-native-\(UUID().uuidString).\(suffix)")
    try FileManager.default.moveItem(at: input, to: staged)
    defer { try? FileManager.default.removeItem(at: staged) }
    let asset = AVURLAsset(url: staged)
    guard (try staged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 32 * 1024 * 1024 ||
          asset.tracks(withMediaType: .video).isEmpty else { throw NSError(domain: "CloudioCache", code: 2) }
    guard let audio = asset.tracks(withMediaType: .audio).first,
          CMTimeGetSeconds(audio.timeRange.duration).isFinite,
          CMTimeGetSeconds(audio.timeRange.duration) > 0 else { throw NSError(domain: "CloudioCache", code: 3) }
    if let description = audio.formatDescriptions.first,
       CMFormatDescriptionGetMediaSubType(description as! CMFormatDescription) == kAudioFormatMPEGLayer3,
       asset.tracks(withMediaType: .video).isEmpty {
      let output = directory.appendingPathComponent("sound-\(id).mp3")
      try FileManager.default.copyItem(at: staged, to: output)
      try trimTikTokCache(directory, keeping: output)
      return output.path
    }
    let composition = AVMutableComposition()
    guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      throw NSError(domain: "CloudioCache", code: 4)
    }
    try track.insertTimeRange(audio.timeRange, of: audio, at: .zero)
    let output = directory.appendingPathComponent("sound-\(id).m4a")
    let partial = directory.appendingPathComponent("export-\(id)-\(UUID().uuidString).m4a")
    defer { try? FileManager.default.removeItem(at: partial) }
    guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough),
          exporter.supportedFileTypes.contains(.m4a) else { throw NSError(domain: "CloudioCache", code: 5) }
    exporter.outputURL = partial
    exporter.outputFileType = .m4a
    exporter.shouldOptimizeForNetworkUse = false
    let done = DispatchSemaphore(value: 0)
    exporter.exportAsynchronously { done.signal() }
    guard done.wait(timeout: .now() + 15) == .success else {
      exporter.cancelExport()
      throw NSError(domain: "CloudioCache", code: 6)
    }
    guard exporter.status == .completed else { throw exporter.error ?? NSError(domain: "CloudioCache", code: 7) }
    let result = AVURLAsset(url: partial)
    guard result.tracks(withMediaType: .video).isEmpty,
          result.tracks(withMediaType: .audio).count == 1 else { throw NSError(domain: "CloudioCache", code: 8) }
    try FileManager.default.moveItem(at: partial, to: output)
    try trimTikTokCache(directory, keeping: output)
    return output.path
  }

  private static func trimTikTokCache(_ directory: URL, keeping: URL) throws {
    let files = try FileManager.default.contentsOfDirectory(at: directory,
      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
      .filter { $0.lastPathComponent.hasPrefix("sound-") && $0 != keeping }
      .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
                ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
    var count = files.count + 1
    var total = files.reduce((try? keeping.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) {
      $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    for file in files {
      if count <= 32 && total <= 128 * 1024 * 1024 { break }
      let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      try FileManager.default.removeItem(at: file)
      total -= bytes; count -= 1
    }
  }

  private static func decodeSample(_ media: Data) throws -> Data {
    let prefix = [UInt8](media.prefix(12))
    let suffix: String
    if prefix.count >= 8 && String(bytes: prefix[4..<8], encoding: .ascii) == "ftyp" { suffix = ".m4a" }
    else if prefix.count >= 4 && String(bytes: prefix[0..<4], encoding: .ascii) == "RIFF" { suffix = ".wav" }
    else if prefix.count >= 2 && prefix[0] == 0xff && prefix[1] & 0xf6 == 0xf0 { suffix = ".aac" }
    else { suffix = ".mp3" }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + suffix)
    try media.write(to: file, options: .atomic)
    defer { try? FileManager.default.removeItem(at: file) }
    let asset = AVURLAsset(url: file)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw NSError(domain: "CloudioAudio", code: 1)
    }
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 12, preferredTimescale: 16000))
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
      AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false
    ])
    guard reader.canAdd(output) else { throw NSError(domain: "CloudioAudio", code: 2) }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? NSError(domain: "CloudioAudio", code: 3) }
    defer { reader.cancelReading() }
    var pcm = Data()
    let started = Date()
    while pcm.count < 16000 * 12 * 2 && Date().timeIntervalSince(started) < 15,
          let sample = output.copyNextSampleBuffer() {
      if let block = CMSampleBufferGetDataBuffer(sample) {
        let size = min(CMBlockBufferGetDataLength(block), 16000 * 12 * 2 - pcm.count)
        var chunk = Data(count: size)
        let status = chunk.withUnsafeMutableBytes { pointer in
          CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: pointer.baseAddress!)
        }
        if status != kCMBlockBufferNoErr { throw NSError(domain: "CloudioAudio", code: 4) }
        pcm.append(chunk)
      }
      CMSampleBufferInvalidate(sample)
    }
    if reader.status == .failed || pcm.isEmpty { throw reader.error ?? NSError(domain: "CloudioAudio", code: 5) }
    return pcm
  }

}
