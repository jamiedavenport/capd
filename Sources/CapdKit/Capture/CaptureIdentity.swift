import CryptoKit
import Foundation

enum CaptureIdentity {
    static func contentHash(for url: URL) -> String {
        contentHash(for: Data(URLNormalizer.normalize(url).utf8))
    }

    static func contentHash(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
