import AVFoundation
import Flutter

final class IOSVoiceAudioEngine: NSObject {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let stateQueue = DispatchQueue(label: "agent.voice.audio.state")
  private var microphoneSink: FlutterEventSink?
  private var playbackSink: FlutterEventSink?
  private var running = false
  private var conversationMode = false
  private var voiceProcessingEnabled = false
  private var invalidResponses = Set<String>()
  private var pendingBuffers: [SegmentKey: Int] = [:]
  private var completedSegments: [SegmentKey: Int] = [:]
  private var completedResponses = Set<String>()
  private lazy var microphoneHandler = EventStreamHandler(
    onListen: { [weak self] sink in self?.microphoneSink = sink },
    onCancel: { [weak self] in self?.microphoneSink = nil }
  )
  private lazy var playbackHandler = EventStreamHandler(
    onListen: { [weak self] sink in self?.playbackSink = sink },
    onCancel: { [weak self] in self?.playbackSink = nil }
  )

  func register(with messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(name: "agent_voice/audio", binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    FlutterEventChannel(name: "agent_voice/microphone", binaryMessenger: messenger)
      .setStreamHandler(microphoneHandler)
    FlutterEventChannel(name: "agent_voice/playback", binaryMessenger: messenger)
      .setStreamHandler(playbackHandler)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      let arguments = call.arguments as? [String: Any]
      switch call.method {
      case "requestMicrophonePermission":
        requestPermission(result)
      case "applicationSupportDirectory":
        guard let directory = FileManager.default.urls(
          for: .applicationSupportDirectory,
          in: .userDomainMask
        ).first else { throw AudioError.supportDirectoryUnavailable }
        result(directory.path)
      case "start":
        let conversation = arguments?["mode"] as? String != "standby"
        result(try start(conversation: conversation))
      case "enqueuePlayback":
        guard
          let bytes = (arguments?["pcm"] as? FlutterStandardTypedData)?.data,
          let responseID = arguments?["responseId"] as? String,
          let segmentIndex = arguments?["segmentIndex"] as? Int
        else { throw AudioError.invalidArguments }
        try enqueue(bytes, responseID: responseID, segmentIndex: segmentIndex)
        result(nil)
      case "completeSegment":
        guard
          let responseID = arguments?["responseId"] as? String,
          let segmentIndex = arguments?["segmentIndex"] as? Int,
          let samples = arguments?["samples"] as? Int
        else { throw AudioError.invalidArguments }
        completeSegment(responseID: responseID, segmentIndex: segmentIndex, samples: samples)
        result(nil)
      case "completeResponse":
        guard let responseID = arguments?["responseId"] as? String else {
          throw AudioError.invalidArguments
        }
        completeResponse(responseID)
        result(nil)
      case "cancelPlayback":
        guard let responseID = arguments?["responseId"] as? String else {
          throw AudioError.invalidArguments
        }
        cancel(responseID)
        result(nil)
      case "pausePlayback":
        player.pause()
        result(nil)
      case "resumePlayback":
        if running { player.play() }
        result(nil)
      case "stop":
        stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "native_audio", message: error.localizedDescription, details: nil))
    }
  }

  private func requestPermission(_ result: @escaping FlutterResult) {
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted:
      result(true)
    case .denied:
      result(false)
    case .undetermined:
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        DispatchQueue.main.async { result(granted) }
      }
    @unknown default:
      result(false)
    }
  }

  private func start(conversation: Bool) throws -> [String: Any] {
    if running && conversationMode == conversation { return processingState() }
    if running { stop() }
    guard AVAudioSession.sharedInstance().recordPermission == .granted else {
      throw AudioError.permissionDenied
    }
    let session = AVAudioSession.sharedInstance()
    let options: AVAudioSession.CategoryOptions = conversation
      ? [.defaultToSpeaker, .allowBluetoothHFP]
      : [.allowBluetoothHFP]
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
    try session.setPreferredIOBufferDuration(0.02)
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let input = engine.inputNode
    if #available(iOS 13.0, *) {
      try input.setVoiceProcessingEnabled(true)
      voiceProcessingEnabled = input.isVoiceProcessingEnabled
    }
    if conversation {
      if !engine.attachedNodes.contains(player) {
        engine.attach(player)
      }
      guard let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
      ) else { throw AudioError.formatUnavailable }
      engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
    }

    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0,
      let captureFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
      ),
      let converter = AVAudioConverter(from: inputFormat, to: captureFormat)
    else { throw AudioError.formatUnavailable }

    input.installTap(onBus: 0, bufferSize: 1_920, format: inputFormat) {
      [weak self] buffer, _ in
      self?.convertCapture(buffer, converter: converter, outputFormat: captureFormat)
    }
    engine.prepare()
    try engine.start()
    if conversation { player.play() }
    stateQueue.sync {
      invalidResponses.removeAll()
      pendingBuffers.removeAll()
      completedSegments.removeAll()
      completedResponses.removeAll()
      running = true
      conversationMode = conversation
    }
    return processingState()
  }

  private func processingState() -> [String: Any] {
    [
      "mode": conversationMode ? "conversation" : "standby",
      "aecAvailable": true,
      "aecEnabled": voiceProcessingEnabled && conversationMode,
      "noiseSuppressionAvailable": true,
      "noiseSuppressionEnabled": voiceProcessingEnabled,
    ]
  }

  private func convertCapture(
    _ input: AVAudioPCMBuffer,
    converter: AVAudioConverter,
    outputFormat: AVAudioFormat
  ) {
    let ratio = 16_000 / input.format.sampleRate
    let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1
    guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
      return
    }
    var supplied = false
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, outputStatus in
      if supplied {
        outputStatus.pointee = .noDataNow
        return nil
      }
      supplied = true
      outputStatus.pointee = .haveData
      return input
    }
    guard status != .error, output.frameLength > 0,
      let source = output.int16ChannelData?[0]
    else { return }
    let data = Data(bytes: source, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    DispatchQueue.main.async { [weak self] in
      self?.microphoneSink?(FlutterStandardTypedData(bytes: data))
    }
  }

  private func enqueue(_ data: Data, responseID: String, segmentIndex: Int) throws {
    let shouldSchedule = stateQueue.sync {
      running && !invalidResponses.contains(responseID)
    }
    guard shouldSchedule && conversationMode else { return }
    guard data.count > 0, data.count.isMultiple(of: 2),
      let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
      ),
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(data.count / 2)
      ),
      let destination = buffer.int16ChannelData?[0]
    else { throw AudioError.invalidPCM }
    buffer.frameLength = buffer.frameCapacity
    data.withUnsafeBytes { source in
      if let address = source.baseAddress {
        UnsafeMutableRawPointer(destination).copyMemory(from: address, byteCount: data.count)
      }
    }
    let key = SegmentKey(responseID: responseID, segmentIndex: segmentIndex)
    stateQueue.sync { pendingBuffers[key, default: 0] += 1 }
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) {
      [weak self] _ in
      self?.bufferPlayed(key)
    }
    if !player.isPlaying { player.play() }
  }

  private func bufferPlayed(_ key: SegmentKey) {
    stateQueue.async { [weak self] in
      guard let self else { return }
      let count = max(0, (pendingBuffers[key] ?? 1) - 1)
      pendingBuffers[key] = count
      emitIfComplete(key)
      emitResponseIfComplete(key.responseID)
    }
  }

  private func completeSegment(responseID: String, segmentIndex: Int, samples: Int) {
    let key = SegmentKey(responseID: responseID, segmentIndex: segmentIndex)
    stateQueue.async { [weak self] in
      self?.completedSegments[key] = samples
      self?.emitIfComplete(key)
    }
  }

  private func completeResponse(_ responseID: String) {
    stateQueue.async { [weak self] in
      self?.completedResponses.insert(responseID)
      self?.emitResponseIfComplete(responseID)
    }
  }

  private func emitIfComplete(_ key: SegmentKey) {
    guard !invalidResponses.contains(key.responseID),
      pendingBuffers[key, default: 0] == 0,
      let samples = completedSegments.removeValue(forKey: key)
    else { return }
    pendingBuffers.removeValue(forKey: key)
    emit([
      "type": "segment.completed",
      "responseId": key.responseID,
      "segmentIndex": key.segmentIndex,
      "playedSamples": samples,
    ])
  }

  private func emitResponseIfComplete(_ responseID: String) {
    guard completedResponses.contains(responseID),
      !invalidResponses.contains(responseID),
      !pendingBuffers.contains(where: { $0.key.responseID == responseID && $0.value > 0 }),
      !completedSegments.keys.contains(where: { $0.responseID == responseID })
    else { return }
    completedResponses.remove(responseID)
    emit(["type": "response.finished", "responseId": responseID])
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.playbackSink?(event) }
  }

  private func cancel(_ responseID: String) {
    stateQueue.sync {
      invalidResponses.insert(responseID)
      pendingBuffers = pendingBuffers.filter { $0.key.responseID != responseID }
      completedSegments = completedSegments.filter { $0.key.responseID != responseID }
      completedResponses.remove(responseID)
    }
    player.stop()
    if running { player.play() }
  }

  private func stop() {
    let wasRunning = stateQueue.sync { () -> Bool in
      let value = running
      running = false
      return value
    }
    guard wasRunning else { return }
    engine.inputNode.removeTap(onBus: 0)
    player.stop()
    engine.stop()
    engine.reset()
    voiceProcessingEnabled = false
    conversationMode = false
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: .notifyOthersOnDeactivation
    )
    stateQueue.sync {
      invalidResponses.removeAll()
      pendingBuffers.removeAll()
      completedSegments.removeAll()
      completedResponses.removeAll()
    }
  }
}

private struct SegmentKey: Hashable {
  let responseID: String
  let segmentIndex: Int
}

private final class EventStreamHandler: NSObject, FlutterStreamHandler {
  let listen: (@escaping FlutterEventSink) -> Void
  let cancel: () -> Void

  init(
    onListen: @escaping (@escaping FlutterEventSink) -> Void,
    onCancel: @escaping () -> Void
  ) {
    listen = onListen
    cancel = onCancel
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    listen(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    cancel()
    return nil
  }
}

private enum AudioError: LocalizedError {
  case invalidArguments
  case permissionDenied
  case formatUnavailable
  case invalidPCM
  case supportDirectoryUnavailable

  var errorDescription: String? {
    switch self {
    case .invalidArguments: "Invalid native audio arguments"
    case .permissionDenied: "Microphone permission is required"
    case .formatUnavailable: "Required PCM format is unavailable"
    case .invalidPCM: "PCM data must contain little-endian Int16 samples"
    case .supportDirectoryUnavailable: "Application support directory is unavailable"
    }
  }
}
