import Foundation
import CoreML
import Accelerate
import UIKit
import CoreVideo

actor CLIPScoringService {
    static let shared = CLIPScoringService()
    
    // CoreML生成されたクラスが存在する前提（Xcodeが自動生成します）
    // lazy var visionEncoder = try? CLIPVisionEncoder(configuration: MLModelConfiguration())
    // lazy var textEncoder = try? CLIPTextEncoder(configuration: MLModelConfiguration())
    
    private let textModelName = "sentence-transformers/clip-ViT-B-32-multilingual-v1"
    
    // キャッシュされたCoreMLモデル
    private var visionEncoderModel: MLModel?
    private var textEncoderModel: MLModel?
    
    private init() {}
    
    private func loadModel(resourceName: String) throws -> MLModel {
        guard let modelURL = Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") else {
            throw CLIPError.modelNotLoaded
        }
        let config = MLModelConfiguration()
        #if targetEnvironment(simulator)
        config.computeUnits = .cpuOnly // SimulatorのGPU/MPSクラッシュを回避
        #else
        config.computeUnits = .cpuAndNeuralEngine
        #endif
        
        return try MLModel(contentsOf: modelURL, configuration: config)
    }
    
    private func getVisionModel() throws -> MLModel {
        if let model = visionEncoderModel { return model }
        let model = try loadModel(resourceName: "CLIPVisionEncoder")
        self.visionEncoderModel = model
        return model
    }
    
    private func getTextModel() throws -> MLModel {
        if let model = textEncoderModel { return model }
        let model = try loadModel(resourceName: "CLIPTextEncoder")
        self.textEncoderModel = model
        return model
    }
    
    /// スライド画像とセリフテキストの合致度（コサイン類似度 0.0〜1.0）を算出します
    func computeRelevanceScore(slideImage: UIImage, speechText: String) async throws -> Float {
        // 1. セリフテキストのベクトル化
        let textEmbeds = try await getTextEmbeddings(text: speechText)
        
        // 2. スライド画像のベクトル化
        let imageEmbeds = try await getImageEmbeddings(image: slideImage)
        
        // 3. コサイン類似度の計算
        let similarity = cosineSimilarity(a: textEmbeds, b: imageEmbeds)
        
        // CLIPの類似度は通常 -1.0 ~ 1.0 だが、おおよそ 0.1~0.4 周辺に分布することが多い
        // アプリケーション層でスケール調整(0~100点)を行います。ここでは生のコサイン類似度を返します。
        return similarity
    }
    
    private func getTextEmbeddings(text: String) async throws -> [Float] {
        let maxLen = 77
        let tokens = try await CoreMLTokenizerService.shared.tokenize(text: text, modelName: textModelName, maxLength: maxLen)
        
        let inputIdsMulti = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
        let attnMaskMulti = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
        
        for i in 0..<maxLen {
            inputIdsMulti[i] = NSNumber(value: tokens.inputIds[i])
            attnMaskMulti[i] = NSNumber(value: tokens.attentionMask[i])
        }
        
        let model = try getTextModel()
        
        let featureProvider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIdsMulti),
            "attention_mask": MLFeatureValue(multiArray: attnMaskMulti)
        ])
        
        let output = try await model.prediction(from: featureProvider)
        guard let textEmbeds = output.featureValue(for: "text_embeds")?.multiArrayValue else {
            throw CLIPError.inferenceFailed
        }
        
        return toFloatArray(textEmbeds)
    }
    
    private func getImageEmbeddings(image: UIImage) async throws -> [Float] {
        guard let cgImage = image.cgImage else {
            throw CLIPError.invalidImage
        }
        
        // 画像を 224x224 の Float32 [1, 3, 224, 224] にリサイズ・正規化する処理
        // CLIPの平均と標準偏差: mean=[0.48145466, 0.4578275, 0.40821073], std=[0.26862954, 0.26130258, 0.27577711]
        let pixelValues = try preprocessImage(cgImage: cgImage)
        
        let model = try getVisionModel()
        
        let featureProvider = try MLDictionaryFeatureProvider(dictionary: [
            "pixel_values": MLFeatureValue(multiArray: pixelValues)
        ])
        
        let output = try await model.prediction(from: featureProvider)
        guard let imageEmbeds = output.featureValue(for: "image_embeds")?.multiArrayValue else {
            throw CLIPError.inferenceFailed
        }
        
        return toFloatArray(imageEmbeds)
    }
    
    private func preprocessImage(cgImage: CGImage) throws -> MLMultiArray {
        let targetSize = CGSize(width: 224, height: 224)
        
        // コンテキストの作成
        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(targetSize.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw CLIPError.invalidImage }
        
        // リサイズ
        context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        guard let rawRGB = context.data else { throw CLIPError.invalidImage }
        let pixelBuffer = rawRGB.bindMemory(to: UInt8.self, capacity: Int(targetSize.width * targetSize.height * 4))
        
        // [1, 3, 224, 224] のMLMultiArrayを作成
        let multiArray = try MLMultiArray(shape: [1, 3, 224, 224], dataType: .float32)
        
        let mean: [Float] = [0.48145466, 0.4578275, 0.40821073]
        let std: [Float] = [0.26862954, 0.26130258, 0.27577711]
        
        for y in 0..<224 {
            for x in 0..<224 {
                let offset = (y * 224 + x) * 4
                let r = Float(pixelBuffer[offset]) / 255.0
                let g = Float(pixelBuffer[offset + 1]) / 255.0
                let b = Float(pixelBuffer[offset + 2]) / 255.0
                
                // R
                multiArray[[0, 0, NSNumber(value: y), NSNumber(value: x)]] = NSNumber(value: (r - mean[0]) / std[0])
                // G
                multiArray[[0, 1, NSNumber(value: y), NSNumber(value: x)]] = NSNumber(value: (g - mean[1]) / std[1])
                // B
                multiArray[[0, 2, NSNumber(value: y), NSNumber(value: x)]] = NSNumber(value: (b - mean[2]) / std[2])
            }
        }
        
        return multiArray
    }
    
    private func toFloatArray(_ multiArray: MLMultiArray) -> [Float] {
        let count = multiArray.count
        var floats = [Float](repeating: 0, count: count)
        for i in 0..<count {
            floats[i] = multiArray[i].floatValue
        }
        return floats
    }
    
    private func cosineSimilarity(a: [Float], b: [Float]) -> Float {
        guard a.count == b.count, a.count > 0 else { return 0.0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        let count = vDSP_Length(a.count)
        
        vDSP_dotpr(a, 1, b, 1, &dotProduct, count)
        vDSP_svesq(a, 1, &normA, count)
        vDSP_svesq(b, 1, &normB, count)
        
        let denominator = sqrt(normA) * sqrt(normB)
        if denominator == 0 { return 0.0 }
        return dotProduct / denominator
    }
}

enum CLIPError: Error {
    case modelNotLoaded
    case inferenceFailed
    case invalidImage
}
