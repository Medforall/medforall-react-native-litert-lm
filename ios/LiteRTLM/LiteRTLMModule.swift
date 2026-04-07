import Foundation
import React

@objc(LiteRTLMModule)
class LiteRTLMModule: NSObject {

    private let bridge = LiteRTLMBridge()
    private let manager = LiteRTLMModelManager.shared
    private let queue = DispatchQueue(label: "com.medforall.litert-lm.module", qos: .userInitiated)

    @objc static func requiresMainQueueSetup() -> Bool { false }

    @objc func isSupported(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(LiteRTLMBridge.isDeviceSupported())
    }

    @objc func isModelCached(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(manager.isModelCached())
    }

    @objc func downloadModel(_ url: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        guard let modelURL = URL(string: url) else {
            reject("INVALID_URL", "The provided URL is invalid: \(url)", nil)
            return
        }
        manager.downloadModel(from: modelURL, onProgress: { _ in }) { result in
            switch result {
            case .success(let path):
                resolve(path)
            case .failure(let error):
                reject("DOWNLOAD_FAILED", error.localizedDescription, error)
            }
        }
    }

    @objc func deleteModel(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        bridge.unloadModel()
        do {
            try manager.deleteModel()
            resolve(true)
        } catch {
            reject("DELETE_FAILED", error.localizedDescription, error)
        }
    }

    @objc func getModelSize(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(manager.modelSizeOnDisk())
    }

    @objc func loadModel(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let path = self.manager.modelPath
            let fm = FileManager.default
            let exists = fm.fileExists(atPath: path)
            var sizeStr = "N/A"
            if exists, let attrs = try? fm.attributesOfItem(atPath: path),
               let sz = attrs[.size] as? Int64 {
                sizeStr = "\(sz / (1024*1024))MB"
            }
            do {
                try self.bridge.loadModel(at: path)
                resolve(true)
            } catch {
                let detail = "path=\(path), exists=\(exists), size=\(sizeStr), backend=cpu, maxTokens=1024, error=\(error)"
                reject("LOAD_FAILED", detail, error)
            }
        }
    }

    @objc func generateText(_ prompt: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let result = try self.bridge.generateText(prompt: prompt)
                resolve(result)
            } catch {
                reject("GENERATE_FAILED", error.localizedDescription, error)
            }
        }
    }

    @objc func describeImage(_ imageBase64: String, prompt: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let imageData = Data(base64Encoded: imageBase64) else {
                reject("INVALID_IMAGE", "Failed to decode base64 image data", nil)
                return
            }
            do {
                let result = try self.bridge.describeImage(imageData: imageData, prompt: prompt)
                resolve(result)
            } catch {
                reject("DESCRIBE_IMAGE_FAILED", error.localizedDescription, error)
            }
        }
    }

    @objc func unloadModel(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.bridge.unloadModel()
            resolve(true)
        }
    }
}
