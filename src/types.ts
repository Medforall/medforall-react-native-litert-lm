export interface LiteRTLMModule {
  isSupported(): Promise<boolean>;
  isModelCached(): Promise<boolean>;
  downloadModel(url: string): Promise<string>;
  deleteModel(): Promise<boolean>;
  getModelSize(): Promise<number>;
  loadModel(): Promise<boolean>;
  generateText(prompt: string): Promise<string>;
  describeImage(imageBase64: string, prompt: string): Promise<string>;
  unloadModel(): Promise<boolean>;
}
