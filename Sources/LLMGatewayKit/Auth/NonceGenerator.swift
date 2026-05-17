import CryptoKit
import Foundation
import Security

public enum NonceGenerator {
    public struct Pair: Equatable, Sendable {
        public let raw: String
        public let hashedSHA256: String

        public init(raw: String, hashedSHA256: String) {
            self.raw = raw
            self.hashedSHA256 = hashedSHA256
        }
    }

    public static func makePair(length: Int = 32) -> Pair {
        let raw = randomNonce(length: length)
        return Pair(raw: raw, hashedSHA256: sha256(raw))
    }

    public static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func randomNonce(length: Int) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
            }
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }
}
