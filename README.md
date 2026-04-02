# react-native-litert-lm

React Native bridge for [Google LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) — on-device LLM inference using Google's optimized runtime. Run Gemma 4 and other supported models entirely on-device with 2-bit quantization, per-layer embeddings, and Metal GPU acceleration.

**iOS only.** Android support planned for a future release.

## Why LiteRT-LM?

LiteRT-LM is Google's own optimized runtime for running Gemma models on mobile. Compared to llama.cpp:

| Metric | LiteRT-LM | llama.cpp |
|--------|-----------|-----------|
| Quantization | 2-bit | 4-bit |
| RAM usage | ~2.5 GB | ~5 GB |
| Model download | ~1.5 GB | ~2.5 GB |
| Inference speed | 30-40+ tok/s | 15-25 tok/s |
| Min device RAM | 6 GB | 8 GB |

## Supported Devices

- iPhone 15 / 15 Plus (6 GB RAM) — viable with 2-bit quantization
- iPhone 15 Pro / Pro Max (8 GB RAM)
- iPhone 16 all models (8 GB+)

Not supported: iPhone 14 and older (insufficient RAM or Neural Engine).

## Installation

```bash
npm install @medforall/react-native-litert-lm
```

### Expo

Add the plugin to your `app.config.js`:

```js
plugins: [
  '@medforall/react-native-litert-lm',
  // ... other plugins
],
```

Then rebuild:

```bash
npx expo prebuild --clean
npx expo run:ios --device
```

### Bare React Native

The CocoaPods spec handles linking automatically. After `npm install`, run:

```bash
cd ios && pod install
```

## Usage

```typescript
import {
  isSupported,
  isModelCached,
  downloadModel,
  loadModel,
  generateText,
  describeImage,
  unloadModel,
} from '@medforall/react-native-litert-lm';

// 1. Check device capability
const supported = await isSupported();
if (!supported) return; // Device has < 6 GB RAM

// 2. Download model (first time only, ~1.5 GB)
const cached = await isModelCached();
if (!cached) {
  await downloadModel('https://your-cdn.com/gemma4-e4b.litertlm');
}

// 3. Load model into memory (5-8 seconds)
await loadModel();

// 4a. Text generation
const summary = await generateText(
  'Summarize: EO, EC, ITCH at 2:15am, REPO at 3:00am, EC'
);

// 4b. Vision — describe an image
const description = await describeImage(
  base64JpegString,
  'Describe what you see. Note any people and their activity.'
);

// 5. Cleanup when done
await unloadModel();
```

## API

### Device Check

#### `isSupported(): Promise<boolean>`

Returns `true` if the device has enough RAM (>= 6 GB) for on-device inference.

### Model Management

#### `isModelCached(): Promise<boolean>`

Returns `true` if the model file has been downloaded and exists on disk.

#### `downloadModel(url: string): Promise<string>`

Downloads the model file from the given URL. Returns the local file path. The model is stored in the app's Documents directory and persists across app restarts.

#### `deleteModel(): Promise<boolean>`

Deletes the cached model from disk and unloads it from memory. Use this to free storage (~1.5 GB).

#### `getModelSize(): Promise<number>`

Returns the size of the cached model in bytes, or `0` if not cached.

### Inference

#### `loadModel(): Promise<boolean>`

Loads the cached model into memory. This is a **slow operation** — expect 5-8 seconds on first call after app launch. Must be called before `generateText` or `describeImage`. Subsequent calls are near-instant if the model is already loaded.

#### `generateText(prompt: string): Promise<string>`

Generates text from a text-only prompt. The model must be loaded first.

#### `describeImage(imageBase64: string, prompt: string): Promise<string>`

Generates a description from a JPEG image + text prompt. `imageBase64` must be a base64-encoded JPEG string. The model must be loaded first.

#### `unloadModel(): Promise<boolean>`

Unloads the model from memory and frees RAM. Call this when the user leaves the AI feature or the app backgrounds.

## Architecture

The library bridges Google's LiteRT-LM C API to React Native through four layers:

```
┌─────────────────────────────────────────────────────┐
│  React Native (JavaScript)                          │
│                                                     │
│  src/index.ts                                       │
│  Typed async functions → NativeModules.LiteRTLM     │
└──────────────────────┬──────────────────────────────┘
                       │ RCT Bridge
┌──────────────────────▼──────────────────────────────┐
│  Native Module Layer                                │
│                                                     │
│  LiteRTLMModule.swift  ←→  LiteRTLMModule.m         │
│  @objc methods with       ObjC bridge macros        │
│  RCTPromiseResolveBlock   (RCT_EXTERN_MODULE)       │
│  Dispatches to background                           │
│  queue for all inference                            │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│  Swift Bridge Layer                                 │
│                                                     │
│  LiteRTLMBridge.swift                               │
│  Swift wrapper around C API. Manages engine and     │
│  session lifecycle. Thread-safe via serial           │
│  DispatchQueue. Handles:                            │
│  - Engine creation from .litertlm model file        │
│  - Text-only inference (single InputData)           │
│  - Multimodal inference (text + image + imageEnd)   │
│  - Memory cleanup on unload/deinit                  │
│                                                     │
│  LiteRTLMModelManager.swift                         │
│  Singleton for model file management:               │
│  - URLSession download with progress delegate       │
│  - Documents directory caching                      │
│  - File existence checks and deletion               │
└──────────────────────┬──────────────────────────────┘
                       │ ObjC Bridging Header
┌──────────────────────▼──────────────────────────────┐
│  LiteRT-LM C API                                    │
│                                                     │
│  litert_lm_engine.h  +  libLiteRTLM.a               │
│                                                     │
│  Opaque pointer types:                              │
│  - LiteRtLmEngine (heavyweight, holds model weights)│
│  - LiteRtLmSession (stateful inference session)     │
│  - LiteRtLmResponses (inference results)            │
│  - LiteRtLmEngineSettings (engine configuration)    │
│  - LiteRtLmConversation (multi-turn chat)           │
│                                                     │
│  Key functions:                                     │
│  - litert_lm_engine_settings_create()               │
│  - litert_lm_engine_create()                        │
│  - litert_lm_engine_create_session()                │
│  - litert_lm_session_generate_content()             │
│  - litert_lm_session_generate_content_stream()      │
│  - litert_lm_conversation_create()                  │
│  - litert_lm_conversation_send_message()            │
│                                                     │
│  Multimodal input via InputData struct:              │
│  - kInputText (UTF-8 string)                        │
│  - kInputImage (raw JPEG bytes)                     │
│  - kInputImageEnd (end marker)                      │
│  - kInputAudio / kInputAudioEnd (future)            │
└─────────────────────────────────────────────────────┘
```

### File Breakdown

```
react-native-litert-lm/
├── ios/
│   ├── LiteRTLM/
│   │   ├── LiteRTLMModule.swift        # RN native module — @objc methods,
│   │   │                               # promise-based, dispatches to bg queue
│   │   ├── LiteRTLMModule.m            # ObjC bridge macros (RCT_EXTERN_MODULE)
│   │   ├── LiteRTLMBridge.swift        # Swift ↔ C API wrapper — engine/session
│   │   │                               # lifecycle, text + vision inference
│   │   ├── LiteRTLMModelManager.swift  # Download, cache, delete model files
│   │   │                               # via URLSession with progress delegate
│   │   └── react-native-litert-lm-Bridging-Header.h
│   │                                   # Imports RCTBridgeModule + C header
│   └── Vendor/
│       ├── libLiteRTLM.a               # Prebuilt static library (22 MB, arm64)
│       │                               # Monolithic archive: C API + runtime +
│       │                               # all transitive deps (absl, sentencepiece,
│       │                               # XNNPACK, flatbuffers, etc.)
│       ├── include/
│       │   └── litert_lm_engine.h      # C API header — all public types and
│       │                               # functions for engine, session, conversation
│       └── prebuilt/
│           └── libGemmaModelConstraintProvider.dylib
│                                       # GPU constraint provider for iOS arm64
├── src/
│   ├── index.ts                        # Public TypeScript API — typed wrappers
│   │                                   # around NativeModules with error handling
│   └── types.ts                        # LiteRTLMModule interface definition
├── app.plugin.js                       # Expo config plugin (stub)
├── react-native-litert-lm.podspec      # CocoaPods spec — links static lib,
│                                       # sets header search paths, bridging header
└── package.json
```

### Threading Model

All inference runs off the main thread:

1. **JS thread** calls `NativeModules.LiteRTLM.generateText(prompt)`
2. **RN bridge** marshals the call to the native module on the native modules thread
3. **LiteRTLMModule** dispatches to a serial `DispatchQueue` (`.userInitiated` QoS)
4. **LiteRTLMBridge** executes the C API call synchronously on that queue
5. Result resolves the JS Promise back on the JS thread

The serial queue ensures no concurrent access to the engine — only one inference runs at a time.

### Memory Management

- **Engine** (`LiteRtLmEngine*`) is heavyweight — holds all model weights in memory (~2.5 GB at 2-bit quantization). Only one should exist at a time.
- **Session** (`LiteRtLmSession*`) is lightweight and created per inference call, then destroyed.
- `unloadModel()` destroys the engine and frees all memory.
- `deinit` on `LiteRTLMBridge` calls `unloadModel()` automatically.
- The XNNPACK shader cache (stored in Caches directory) speeds up subsequent model loads.

### Building the Static Library

The prebuilt `libLiteRTLM.a` was compiled from [google-ai-edge/LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) using Bazel:

```bash
# Prerequisites: Bazelisk (manages Bazel version automatically)
brew install bazelisk

# Clone source
git clone https://github.com/google-ai-edge/LiteRT-LM.git
cd LiteRT-LM

# Build for iOS arm64 (requires Xcode 15+)
bazel build -c opt --apple_platform_type=ios --cpu=ios_arm64 //c:engine

# The output is at bazel-bin/c/libengine.a
# This only contains the C API wrapper objects.

# Create monolithic archive with all dependencies:
mkdir /tmp/litert-build
find bazel-bin/ -name "*.o" -exec cp {} /tmp/litert-build/ \;
cd /tmp/litert-build
ar rcs libLiteRTLM.a *.o
# Result: ~22 MB static archive with all symbols
```

To rebuild after a LiteRT-LM update, repeat the above steps and replace `ios/Vendor/libLiteRTLM.a`.

## Model Files

The library expects `.litertlm` format model files. For Gemma 4 E4B:

- **Hugging Face:** `litert-community/gemma-4-E4B-it-litert-lm`
- **Size:** ~1.5 GB (2-bit quantized with per-layer embeddings)

Host the model on a CDN and pass the URL to `downloadModel()`.

## Error Codes

| Code | Description |
|------|-------------|
| `INVALID_URL` | The download URL is malformed |
| `DOWNLOAD_FAILED` | Model download failed (network error, disk full) |
| `DELETE_FAILED` | Could not delete cached model |
| `LOAD_FAILED` | Engine creation failed (corrupt model, insufficient memory) |
| `GENERATE_FAILED` | Text inference failed |
| `DESCRIBE_IMAGE_FAILED` | Vision inference failed |
| `INVALID_IMAGE` | Could not decode base64 image data |

## Roadmap

- [ ] Android support (Kotlin native module wrapping LiteRT-LM Android SDK)
- [ ] Streaming token output via event emitter
- [ ] Audio input support (Gemma 4 E4B native audio encoder)
- [ ] Download progress events
- [ ] Android AICore / Gemini Nano 4 integration

## License

MIT
