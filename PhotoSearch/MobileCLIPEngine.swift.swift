//
//  MobileCLIPEngine.swift.swift
//  PhotoSearch
//
//  Created by G.K.LEE on 11/14/25.
//

import Foundation
import UIKit
import CoreML
import CoreImage

// MARK: - Errors

enum MobileCLIPEngineError: Error {
    case invalidImage
    case pixelBufferCreationFailed
}

// MARK: - Protocol

protocol MobileCLIPEngineProtocol {
    func load() async
    func embedText(_ text: String) async throws -> [Float]
    func embedImage(pixelBuffer: CVPixelBuffer) async throws -> [Float]
    func embedImage(uiImage: UIImage) async throws -> [Float]
}

// MARK: - Engine

final class MobileCLIPEngine: MobileCLIPEngineProtocol {

    private let encoder: CLIPEncoder
    private let ciContext: CIContext

    // 공유 토크나이저 (원래 ZSImageClassification 패턴 그대로)
    private static let tokenizerFactory = AsyncFactory {
        CLIPTokenizer()
    }

    init(encoder: CLIPEncoder, ciContext: CIContext = CIContext()) {
        self.encoder = encoder
        self.ciContext = ciContext
    }

    // 모델/토크나이저 선로딩
    func load() async {
        async let _ = Self.tokenizerFactory.get()
        async let _ = encoder.load()
        //_ = await ()
    }

    // MARK: - Text

    func embedText(_ text: String) async throws -> [Float] {
        let tokenizer = await Self.tokenizerFactory.get()

        // 1. 토큰 ID (길이 77) 생성
        let inputIds = tokenizer.encode_full(text: text) // [Int], contextLength = 77

        // 2. MLMultiArray [1, 77] int32 생성
        let shape: [NSNumber] = [1, 77]
        let inputArray = try MLMultiArray(shape: shape, dataType: .int32)
        for (index, element) in inputIds.enumerated() {
            inputArray[index] = NSNumber(value: element)
        }

        // 3. 텍스트 인코더 실행
        let embeddingArray = try await encoder.encode(text: inputArray)

        // 4. Float 벡터로 변환
        let vector = embeddingArray.withUnsafeBufferPointer(ofType: Float.self) { ptr in
            Array(ptr)
        }

        return EmbeddingUtils.l2Normalize(vector)
    }

    // MARK: - Image
    func embedImage(pixelBuffer: CVPixelBuffer) async throws -> [Float] {
        // 1. CVPixelBuffer → CIImage
        var image: CIImage? = CIImage(cvPixelBuffer: pixelBuffer)
        image = image?.cropToSquare()
        image = image?.resize(size: encoder.targetImageSize)

        guard let finalImage = image else {
            throw MobileCLIPEngineError.invalidImage
        }

        // 2. 출력용 CVPixelBuffer 생성
        let extent = finalImage.extent
        let pixelFormat = kCVPixelFormatType_32ARGB
        var output: CVPixelBuffer?
        CVPixelBufferCreate(
            nil,
            Int(extent.width),
            Int(extent.height),
            pixelFormat,
            nil,
            &output
        )

        guard let outBuffer = output else {
            throw MobileCLIPEngineError.pixelBufferCreationFailed
        }

        // 3. CIImage → CVPixelBuffer 렌더
        ciContext.render(finalImage, to: outBuffer)

        // 4. 이미지 인코더 실행
        let embeddingArray = try await encoder.encode(image: outBuffer)

        // 5. Float 벡터로 변환
        let vector = embeddingArray.withUnsafeBufferPointer(ofType: Float.self) { ptr in
            Array(ptr)
        }

        return EmbeddingUtils.l2Normalize(vector)
    }
    
    // 샘플용: UIImage에서 바로 임베딩
    func embedImage(uiImage: UIImage) async throws -> [Float] {
        guard let cgImage = uiImage.cgImage else {
            throw MobileCLIPEngineError.invalidImage
        }

        var image: CIImage? = CIImage(cgImage: cgImage)
        image = image?.cropToSquare()
        image = image?.resize(size: encoder.targetImageSize)

        guard let finalImage = image else {
            throw MobileCLIPEngineError.invalidImage
        }

        let extent = finalImage.extent
        let pixelFormat = kCVPixelFormatType_32ARGB
        var output: CVPixelBuffer?
        CVPixelBufferCreate(
            nil,
            Int(extent.width),
            Int(extent.height),
            pixelFormat,
            nil,
            &output
        )

        guard let outBuffer = output else {
            throw MobileCLIPEngineError.pixelBufferCreationFailed
        }

        ciContext.render(finalImage, to: outBuffer)

        let embeddingArray = try await encoder.encode(image: outBuffer)
        let vector = embeddingArray.withUnsafeBufferPointer(ofType: Float.self) { ptr in
            Array(ptr)
        }

        return EmbeddingUtils.l2Normalize(vector)
    }
}

extension MLMultiArray {
    func withUnsafeBufferPointer<T, R>(
        ofType: T.Type,
        _ body: (UnsafeBufferPointer<T>) -> R
    ) -> R {
        let count = self.count
        return self.dataPointer.withMemoryRebound(to: T.self, capacity: count) { ptr in
            let buffer = UnsafeBufferPointer(start: ptr, count: count)
            return body(buffer)
        }
    }
}

enum EmbeddingUtils {
    static func l2Normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let dot: Float = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let magA: Float = sqrt(a.reduce(0) { $0 + $1 * $1 })
        let magB: Float = sqrt(b.reduce(0) { $0 + $1 * $1 })
        return dot / (magA * magB)
    }
}
