import Foundation

class LiteRTLMModelManager: NSObject {

  // MARK: - Singleton

  static let shared = LiteRTLMModelManager()

  // MARK: - Constants

  private let modelFileName = "gemma4-e4b.litertlm"

  // MARK: - Paths

  var modelDirectory: URL {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return documents.appendingPathComponent("litert-lm-models")
  }

  var modelPath: String {
    return modelDirectory.appendingPathComponent(modelFileName).path
  }

  // MARK: - Download state

  private var downloadProgress: ((Double) -> Void)?
  private var downloadCompletion: ((Result<String, Error>) -> Void)?

  private var urlSession: URLSession?

  // MARK: - Init

  private override init() {
    super.init()
  }

  // MARK: - Cache queries

  func isModelCached() -> Bool {
    return FileManager.default.fileExists(atPath: modelPath)
  }

  func modelSizeOnDisk() -> Int64 {
    guard isModelCached() else { return 0 }
    do {
      let attrs = try FileManager.default.attributesOfItem(atPath: modelPath)
      return (attrs[.size] as? Int64) ?? 0
    } catch {
      return 0
    }
  }

  // MARK: - Deletion

  func deleteModel() throws {
    guard isModelCached() else { return }
    try FileManager.default.removeItem(atPath: modelPath)
  }

  // MARK: - Download

  func downloadModel(
    from url: URL,
    onProgress: @escaping (Double) -> Void,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    // Persist closures for use in the delegate callbacks
    downloadProgress = onProgress
    downloadCompletion = completion

    // Ensure the model directory exists
    do {
      try FileManager.default.createDirectory(
        at: modelDirectory,
        withIntermediateDirectories: true,
        attributes: nil
      )
    } catch {
      completion(.failure(error))
      return
    }

    // Create a URLSession with self as the delegate
    let configuration = URLSessionConfiguration.default
    urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    let task = urlSession!.downloadTask(with: url)
    task.resume()
  }
}

// MARK: - URLSessionDownloadDelegate

extension LiteRTLMModelManager: URLSessionDownloadDelegate {

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    let callback = downloadProgress
    DispatchQueue.main.async {
      callback?(progress)
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let destination = URL(fileURLWithPath: modelPath)
    let completion = downloadCompletion

    do {
      // Remove any stale file at the destination before moving
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: location, to: destination)
      DispatchQueue.main.async {
        completion?(.success(destination.path))
      }
    } catch {
      DispatchQueue.main.async {
        completion?(.failure(error))
      }
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error = error else { return }
    let completion = downloadCompletion
    DispatchQueue.main.async {
      completion?(.failure(error))
    }
  }
}
