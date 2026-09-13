import CryptoKit
import DeviceCheck
import Foundation

/// Proof that a request came from the real Arch, on a real Apple device.
///
/// **This is what a CAPTCHA would have been, done properly.** A CAPTCHA proves
/// "probably a human at a browser" and is beaten by solving farms for about a
/// dollar per thousand. App Attest proves the request came from an unmodified copy
/// of *this* binary on genuine Apple hardware, with a key Apple itself vouches for.
/// A signup farm cannot produce that without buying iPhones and running this app.
///
/// It does **not** prove a real person, and it does **not** survive reinstalling —
/// the key is per-installation and is gone when the app is deleted. So it is no use
/// for recognising a banned user coming back; that is `DeviceCheck`'s two bits and
/// the Apple `userID`.
///
/// ## The exchange
///
/// 1. Server issues a one-time challenge and remembers it
/// 2. `attest(challenge:)` here → `keyID` and an attestation object
/// 3. Server verifies the object against Apple's App Attest root, checks the
///    challenge matches, checks the app id, and stores the public key against
///    `keyID`
/// 4. Every later request carries `assert(keyID:over:)` over the request body, and
///    the server checks the signature and that the counter went up
///
/// **None of the security is here.** The client cannot vouch for itself — every
/// check that matters is step 3 and step 4, on the server. This file only produces
/// the material.
enum Attestation {

    enum Failure: Error {
        /// Simulators, and Macs running iPad apps. Not an error the reader caused.
        case unsupported
        case apple(Error)
        case noData
    }

    /// False on the simulator, so the app needs a path that does not simply stop —
    /// see `isEnforced`.
    static var isSupported: Bool { DCAppAttestService.shared.isSupported }

    /// Whether a build should refuse to continue without attestation.
    ///
    /// Off in debug so the app is usable on a simulator, on everywhere else. The
    /// server enforces it regardless of what this says — a client deciding whether
    /// it needs to prove itself is not a security control.
    static var isEnforced: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    /// One-time, at signup. The `keyID` goes to the server and is kept for the life
    /// of the install.
    static func attest(challenge: Data) async throws -> (keyID: String, attestation: Data) {
        guard isSupported else { throw Failure.unsupported }
        let service = DCAppAttestService.shared

        let keyID: String = try await withCheckedThrowingContinuation { continuation in
            service.generateKey { keyID, error in
                if let error { return continuation.resume(throwing: Failure.apple(error)) }
                guard let keyID else { return continuation.resume(throwing: Failure.noData) }
                continuation.resume(returning: keyID)
            }
        }

        let attestation: Data = try await withCheckedThrowingContinuation { continuation in
            service.attestKey(keyID, clientDataHash: hash(challenge)) { attestation, error in
                if let error { return continuation.resume(throwing: Failure.apple(error)) }
                guard let attestation else { return continuation.resume(throwing: Failure.noData) }
                continuation.resume(returning: attestation)
            }
        }

        return (keyID, attestation)
    }

    /// Every request after the first.
    ///
    /// Sign over the challenge *and* the body together, so an assertion lifted from
    /// one request cannot be replayed onto another.
    static func assert(keyID: String, over body: Data, challenge: Data) async throws -> Data {
        guard isSupported else { throw Failure.unsupported }
        let service = DCAppAttestService.shared
        let clientData = challenge + body

        return try await withCheckedThrowingContinuation { continuation in
            service.generateAssertion(keyID, clientDataHash: hash(clientData)) { assertion, error in
                if let error { return continuation.resume(throwing: Failure.apple(error)) }
                guard let assertion else { return continuation.resume(throwing: Failure.noData) }
                continuation.resume(returning: assertion)
            }
        }
    }

    private static func hash(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}

/// The two bits Apple keeps for this device, across deleting the app.
///
/// **Both are read and written by the server, not here.** Apple's API for them is a
/// server-to-server call authenticated with your team key; the device only ever
/// generates the token that identifies itself. Putting the logic on the client
/// would mean a banned user could simply not run it.
///
/// How the bits are spent:
///
/// - **`bit1` — banned.** A hard block at signup.
/// - **`bit0` — this device has made an account before.** A *soft* signal: flag for
///   review, rate-limit. Never a refusal. Households share iPads and people
///   legitimately start again, and a hard block here buys almost nothing while
///   generating false positives forever.
///
/// The device is corroboration; the wall is the Apple `userID`. A phone changes
/// hands and an Apple ID mostly does not.
enum DeviceIdentity {
    /// Sent with a signup so the server can read and set this device's bits.
    static func token() async throws -> Data {
        guard DCDevice.current.isSupported else { throw Attestation.Failure.unsupported }
        return try await withCheckedThrowingContinuation { continuation in
            DCDevice.current.generateToken { token, error in
                if let error { return continuation.resume(throwing: Attestation.Failure.apple(error)) }
                guard let token else { return continuation.resume(throwing: Attestation.Failure.noData) }
                continuation.resume(returning: token)
            }
        }
    }
}
