import Foundation
import LiteRTLMEngine

// MARK: - Errors

enum LiteRTLMError: LocalizedError {
  case engineCreationFailed
  case sessionCreationFailed
  case inferenceError(String)
  case modelNotLoaded
  case unsupportedDevice

  var errorDescription: String? {
    switch self {
    case .engineCreationFailed: return "Engine creation failed — model file may be corrupt or incompatible with CPU backend"
    case .sessionCreationFailed: return "Session creation failed — insufficient memory or invalid config"
    case .inferenceError(let msg): return "Inference error: \(msg)"
    case .modelNotLoaded: return "Model not loaded — call loadModel() first"
    case .unsupportedDevice: return "Device not supported for on-device inference"
    }
  }
}

// MARK: - LiteRTLMBridge

class LiteRTLMBridge {

  // MARK: - Properties

  private(set) var isLoaded: Bool = false

  private var engine: OpaquePointer?
  private var session: OpaquePointer?

  private let queue = DispatchQueue(label: "com.litert-lm.bridge", qos: .userInitiated)

  // MARK: - Device Support

  static func isDeviceSupported() -> Bool {
    let sixGB: UInt64 = 6 * 1024 * 1024 * 1024
    return ProcessInfo.processInfo.physicalMemory >= sixGB
  }

  // MARK: - Model Loading

  func loadModel(at path: String, backend: String = "cpu", maxTokens: Int = 1024) throws {
    try queue.sync {
      // Clean up any previously loaded model
      _unloadModel()

      NSLog("[LiteRTLM] loadModel: path=%@, backend=%@, maxTokens=%d", path, backend, maxTokens)

      // Enable verbose native logging from LiteRT LM
      litert_lm_set_min_log_level(0)

      // Build engine settings (new API takes all params in create)
      guard let settings = litert_lm_engine_settings_create(path, backend, nil, nil) else {
        NSLog("[LiteRTLM] FAILED: litert_lm_engine_settings_create returned nil")
        throw LiteRTLMError.engineCreationFailed
      }
      defer { litert_lm_engine_settings_delete(settings) }

      NSLog("[LiteRTLM] Settings created OK, setting max tokens and cache dir")
      litert_lm_engine_settings_set_max_num_tokens(settings, Int32(maxTokens))

      // Ensure cache directory exists
      let cacheDirURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("litert-lm-cache")
      try? FileManager.default.createDirectory(at: cacheDirURL, withIntermediateDirectories: true)
      litert_lm_engine_settings_set_cache_dir(settings, cacheDirURL.path)

      NSLog("[LiteRTLM] Creating engine...")

      // Capture stderr during engine creation to surface C++ error messages
      let stderrPipe = Pipe()
      let origStderr = dup(STDERR_FILENO)
      dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

      // Create engine
      let newEngine = litert_lm_engine_create(settings)

      // Restore stderr and read captured output
      fflush(stderr)
      dup2(origStderr, STDERR_FILENO)
      close(origStderr)
      stderrPipe.fileHandleForWriting.closeFile()
      let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""

      if !stderrOutput.isEmpty {
        NSLog("[LiteRTLM] Engine stderr: %@", stderrOutput)
      }

      guard let createdEngine = newEngine else {
        NSLog("[LiteRTLM] FAILED: litert_lm_engine_create returned nil")
        let trimmed = stderrOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = trimmed.isEmpty ? "unknown (no stderr output)" : String(trimmed.suffix(500))
        throw LiteRTLMError.inferenceError("engineCreationFailed: \(reason)")
      }
      NSLog("[LiteRTLM] Engine created OK")

      engine = createdEngine
      isLoaded = true
    }
  }

  // MARK: - Text Generation

  private func createSessionConfig(maxOutputTokens: Int = 512) -> OpaquePointer? {
    guard let config = litert_lm_session_config_create() else { return nil }
    litert_lm_session_config_set_max_output_tokens(config, Int32(maxOutputTokens))
    return config
  }

  func generateText(prompt: String) throws -> String {
    return try queue.sync {
      guard isLoaded, let engine = engine else {
        throw LiteRTLMError.modelNotLoaded
      }

      // Create session with config
      let config = createSessionConfig()
      defer { if let c = config { litert_lm_session_config_delete(c) } }

      guard let newSession = litert_lm_engine_create_session(engine, config) else {
        throw LiteRTLMError.sessionCreationFailed
      }
      defer {
        litert_lm_session_delete(newSession)
      }

      // Build text input
      let promptData = Array(prompt.utf8)
      var input = InputData()
      input.type = kInputText

      let result: String = try promptData.withUnsafeBufferPointer { buf in
        input.data = UnsafeRawPointer(buf.baseAddress)
        input.size = buf.count

        guard let responses = litert_lm_session_generate_content(newSession, &input, 1) else {
          throw LiteRTLMError.inferenceError("generate_content returned nil")
        }
        defer { litert_lm_responses_delete(responses) }

        guard let responseText = litert_lm_responses_get_response_text_at(responses, 0) else {
          throw LiteRTLMError.inferenceError("result contained no text")
        }

        return String(cString: responseText)
      }

      return result
    }
  }

  // MARK: - Image Description

  func describeImage(imageData: Data, prompt: String) throws -> String {
    return try queue.sync {
      guard isLoaded, let engine = engine else {
        throw LiteRTLMError.modelNotLoaded
      }

      // Create session with config
      let config = createSessionConfig()
      defer { if let c = config { litert_lm_session_config_delete(c) } }

      guard let newSession = litert_lm_engine_create_session(engine, config) else {
        throw LiteRTLMError.sessionCreationFailed
      }
      defer {
        litert_lm_session_delete(newSession)
      }

      // Build multimodal input array: text + image + imageEnd
      let promptBytes = Array(prompt.utf8)
      let imageBytes = [UInt8](imageData)

      let result: String = try promptBytes.withUnsafeBufferPointer { promptBuf in
        try imageBytes.withUnsafeBufferPointer { imageBuf in
          var textInput = InputData()
          textInput.type = kInputText
          textInput.data = UnsafeRawPointer(promptBuf.baseAddress)
          textInput.size = promptBuf.count

          var imageInput = InputData()
          imageInput.type = kInputImage
          imageInput.data = UnsafeRawPointer(imageBuf.baseAddress)
          imageInput.size = imageBuf.count

          var imageEndInput = InputData()
          imageEndInput.type = kInputImageEnd
          imageEndInput.data = nil
          imageEndInput.size = 0

          var inputs: [InputData] = [textInput, imageInput, imageEndInput]

          guard let responses = litert_lm_session_generate_content(newSession, &inputs, inputs.count) else {
            throw LiteRTLMError.inferenceError("generate_content returned nil")
          }
          defer { litert_lm_responses_delete(responses) }

          guard let responseText = litert_lm_responses_get_response_text_at(responses, 0) else {
            throw LiteRTLMError.inferenceError("result contained no text")
          }

          return String(cString: responseText)
        }
      }

      return result
    }
  }

  // MARK: - Unload

  func unloadModel() {
    queue.sync {
      _unloadModel()
    }
  }

  // Private unload — must be called from within queue.sync block
  private func _unloadModel() {
    if let s = session {
      litert_lm_session_delete(s)
      session = nil
    }
    if let e = engine {
      litert_lm_engine_delete(e)
      engine = nil
    }
    isLoaded = false
  }

  // MARK: - Deinit

  deinit {
    unloadModel()
  }
}
