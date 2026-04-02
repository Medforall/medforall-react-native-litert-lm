import { NativeModules, Platform } from 'react-native';
import type { LiteRTLMModule } from './types';

const LINKING_ERROR =
  `The package 'react-native-litert-lm' doesn't seem to be linked. Make sure: \n\n` +
  `- You rebuilt the app after installing the package\n` +
  `- You are not using Expo Go\n`;

const LiteRTLM: LiteRTLMModule =
  Platform.OS === 'android'
    ? new Proxy({} as LiteRTLMModule, {
        get() {
          throw new Error('Android support coming soon');
        },
      })
    : NativeModules.LiteRTLM
    ? NativeModules.LiteRTLM
    : new Proxy({} as LiteRTLMModule, {
        get() {
          throw new Error(LINKING_ERROR);
        },
      });

/** Returns true if on-device LLM inference is supported on this device. */
export function isSupported(): Promise<boolean> {
  return LiteRTLM.isSupported();
}

/** Returns true if a model has already been downloaded and is cached locally. */
export function isModelCached(): Promise<boolean> {
  return LiteRTLM.isModelCached();
}

/**
 * Downloads a model from the given URL to local storage.
 * @param url - Remote URL of the model file to download.
 * @returns The local file path where the model was saved.
 */
export function downloadModel(url: string): Promise<string> {
  return LiteRTLM.downloadModel(url);
}

/** Deletes the locally cached model. Returns true on success. */
export function deleteModel(): Promise<boolean> {
  return LiteRTLM.deleteModel();
}

/** Returns the size of the cached model in bytes. */
export function getModelSize(): Promise<number> {
  return LiteRTLM.getModelSize();
}

/**
 * Loads the cached model into memory for inference.
 * This is a slow operation — expect 5–8 seconds on first load.
 * Call this once before running generateText or describeImage.
 */
export function loadModel(): Promise<boolean> {
  return LiteRTLM.loadModel();
}

/**
 * Generates text from the given prompt using the loaded model.
 * @param prompt - The input text prompt.
 * @returns The model's generated text response.
 */
export function generateText(prompt: string): Promise<string> {
  return LiteRTLM.generateText(prompt);
}

/**
 * Describes an image using the loaded vision-capable model.
 * @param imageBase64 - The image encoded as a base64 string (JPEG format).
 * @param prompt - A text prompt to guide the image description.
 * @returns The model's description of the image.
 */
export function describeImage(imageBase64: string, prompt: string): Promise<string> {
  return LiteRTLM.describeImage(imageBase64, prompt);
}

/** Unloads the model from memory. Returns true on success. */
export function unloadModel(): Promise<boolean> {
  return LiteRTLM.unloadModel();
}

export type { LiteRTLMModule } from './types';
