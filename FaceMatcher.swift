import Foundation
import Vision
import CoreImage

class FaceMatcher {
    static func cosineSimilarity(a: [Float], b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dotProduct: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator == 0 ? 0.0 : dotProduct / denominator
    }

    static func extractFaceFeatureVector(from pixelBuffer: CVPixelBuffer, completion: @escaping ([Float]?) -> Void) {
        let request = VNDetectFaceLandmarksRequest { request, _ in
            guard let results = request.results as? [VNFaceObservation],
                  let face = results.first,
                  let landmarks = face.landmarks?.allPoints else {
                completion(nil)
                return
            }
            let points = landmarks.normalizedPoints
            var vector: [Float] = []
            for point in points {
                vector.append(Float(point.x))
                vector.append(Float(point.y))
            }
            completion(vector)
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}
