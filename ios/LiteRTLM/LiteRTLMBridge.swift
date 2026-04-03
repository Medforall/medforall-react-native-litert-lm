import Foundation
import LiteRTLMEngine

// MARK: - Errors

enum LiteRTLMError: Error {
  case engineCreationFailed
  case sessionCreationFailed
  case inferenceError(String)
  case modelNotLoaded
  case unsupportedDevice
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

  func loadModel(at path: String, backend: String = "cpu", maxTokens: Int = 4096) throws {
    try queue.sync {
      // Clean up any previously loaded model
      _unloadModel()

      // Build engine settings (new API takes all params in create)
      guard let settings = litert_lm_engine_settings_create(path, backend, nil, nil) else {
        throw LiteRTLMError.engineCreationFailed
      }
      defer { litert_lm_engine_settings_delete(settings) }

      litert_lm_engine_settings_set_max_num_tokens(settings, Int32(maxTokens))

      // Set cache directory
      let cacheDir = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)
        .first!
        .appendingPathComponent("litert-lm-cache")
        .path
      litert_lm_engine_settings_set_cache_dir(settings, cacheDir)

      // Create engine
      guard let newEngine = litert_lm_engine_create(settings) else {
        throw LiteRTLMError.engineCreationFailed
      }

      engine = newEngine
      isLoaded = true
    }
  }

  // MARK: - Text Generation

  func generateText(prompt: String) throws -> String {
    return try queue.sync {
      guard isLoaded, let engine = engine else {
        throw LiteRTLMError.modelNotLoaded
      }

      // Create session
      guard let newSession = litert_lm_engine_create_session(engine, nil) else {
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

      // Create session
      guard let newSession = litert_lm_engine_create_session(engine, nil) else {
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
