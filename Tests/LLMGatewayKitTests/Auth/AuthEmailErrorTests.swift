import XCTest
@testable import LLMGatewayKit

final class AuthEmailErrorTests: XCTestCase {
    func test_authProvider_email_rawValue() {
        XCTAssertEqual(AuthProvider.email.rawValue, "email")
        XCTAssertTrue(AuthProvider.allCases.contains(.email))
    }

    func test_emailErrors_haveDescriptions() {
        let cases: [AuthError] = [
            .emailCodeInvalid,
            .emailCodeExpired,
            .emailTooManyAttempts,
            .invalidEmail,
            .emailRateLimited,
        ]
        for error in cases {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
        XCTAssertNotEqual(AuthError.emailCodeInvalid, AuthError.emailCodeExpired)
    }
}
