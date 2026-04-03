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

      // Build engine settings
      guard let settings = litert_lm_engine_settings_create() else {
        throw LiteRTLMError.engineCreationFailed
      }
      defer { litert_lm_engine_settings_destroy(settings) }

      litert_lm_engine_settings_set_model_path(settings, path)
      litert_lm_engine_settings_set_backend(settings, backend)
      litert_lm_engine_settings_set_max_tokens(settings, Int32(maxTokens))

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
      guard let newSession = litert_lm_session_create(engine) else {
        throw LiteRTLMError.sessionCreationFailed
      }
      defer {
        litert_lm_session_destroy(newSession)
      }

      // Build text input
      var input = LiteRtLmInputData()
      input.type = kInputText
      input.text = (prompt as NSString).utf8String

      // Call generate
      guard let result = litert_lm_generate_content(newSession, &input, 1) else {
        throw LiteRTLMError.inferenceError("generate_content returned nil")
      }
      defer { litert_lm_result_destroy(result) }

      guard let responseText = litert_lm_result_get_text(result) else {
        throw LiteRTLMError.inferenceError("result contained no text")
      }

      return String(cString: responseText)
    }
  }

  // MARK: - Image Description

  func describeImage(imageData: Data, prompt: String) throws -> String {
    return try queue.sync {
      guard isLoaded, let engine = engine else {
        throw LiteRTLMError.modelNotLoaded
      }

      // Create session
      guard let newSession = litert_lm_session_create(engine) else {
        throw LiteRTLMError.sessionCreationFailed
      }
      defer {
        litert_lm_session_destroy(newSession)
      }

      // Build multimodal input array: text + image + imageEnd
      let imageBytes = [UInt8](imageData)

      var textInput = LiteRtLmInputData()
      textInput.type = kInputText
      textInput.text = (prompt as NSString).utf8String

      var imageInput = LiteRtLmInputData()
      imageInput.type = kInputImage
      imageBytes.withUnsafeBytes { ptr in
        imageInput.image_data = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self)
        imageInput.image_size = Int32(imageBytes.count)
      }

      var imageEndInput = LiteRtLmInputData()
      imageEndInput.type = kInputImageEnd

      var inputs: [LiteRtLmInputData] = [textInput, imageInput, imageEndInput]

      // Call generate
      guard let result = litert_lm_generate_content(newSession, &inputs, Int32(inputs.count)) else {
        throw LiteRTLMError.inferenceError("generate_content returned nil")
      }
      defer { litert_lm_result_destroy(result) }

      guard let responseText = litert_lm_result_get_text(result) else {
        throw LiteRTLMError.inferenceError("result contained no text")
      }

      return String(cString: responseText)
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
      litert_lm_session_destroy(s)
      session = nil
    }
    if let e = engine {
      litert_lm_engine_destroy(e)
      engine = nil
    }
    isLoaded = false
  }

  // MARK: - Deinit

  deinit {
    unloadModel()
  }
}
