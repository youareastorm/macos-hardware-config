import XCTest
@testable import StudioSwitchCore

final class StatusEvaluationTests: XCTestCase {
    private let profile = Profile(name: "Home", deviceNameMatch: "Apollo Solo", audioDeviceName: "Universal Audio Thunderbolt", uadConsoleSession: "s", useIACDriver: false, daws: [])

    private func result(uadConsoleError: String? = nil, uadMixerError: String? = nil) -> ProfileActivationResult {
        ProfileActivationResult(profile: profile, deviceDetected: true, deviceConfigError: nil, outputRoutingError: nil, channelPairError: nil, uadConsoleError: uadConsoleError, uadMixerError: uadMixerError)
    }

    func test_hasError_isFalseWhenEveryStepSucceeded() {
        XCTAssertFalse(result().hasError)
    }

    func test_hasError_isTrueWhenAnyStepFailed() {
        XCTAssertTrue(result(uadConsoleError: "boom").hasError)
        XCTAssertTrue(result(uadMixerError: "boom").hasError)
    }

    func test_needsAttention_whenAHealthCheckIsNotGreen() {
        let health = [HealthCheckResult(label: "Clock", status: .ok), HealthCheckResult(label: "Canaux de sortie", status: .error("MON"))]

        XCTAssertTrue(StatusEvaluation.needsAttention(health: health, lastActivation: result()))
    }

    func test_needsAttention_whenTheLastActivationFailed() {
        let health = [HealthCheckResult(label: "Clock", status: .ok)]

        XCTAssertTrue(StatusEvaluation.needsAttention(health: health, lastActivation: result(uadConsoleError: "boom")))
    }

    func test_noAttention_whenAllGreenAndLastActivationSucceeded() {
        let health = [HealthCheckResult(label: "Clock", status: .ok)]

        XCTAssertFalse(StatusEvaluation.needsAttention(health: health, lastActivation: result()))
        XCTAssertFalse(StatusEvaluation.needsAttention(health: health, lastActivation: nil))
    }

    func test_warningsAlsoNeedAttention() {
        let health = [HealthCheckResult(label: "Volume moniteur", status: .warning("-28 dB au lieu de -35 dB"))]

        XCTAssertTrue(StatusEvaluation.needsAttention(health: health, lastActivation: nil))
    }
}
