import Foundation
import Testing
@testable import WorldClock

@MainActor
struct UpdateServiceTests {
    private let key = Data(repeating: 42, count: 32).base64EncodedString()

    @Test func appBundleEnablesBothRequiredSignatureChecks() throws {
        let info = try #require(Bundle(for: UpdateService.self).infoDictionary)
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
    }

    @Test func acceptsHTTPSFeedWithPublicKey() {
        #expect(UpdateService.hasValidConfiguration([
            "SUPublicEDKey": key, "SUFeedURL": "https://example.com/appcast.xml"
        ]))
    }

    @Test func rejectsMissingAndMalformedKeys() {
        for invalidKey in ["", "$(SPARKLE_PUBLIC_KEY)", "not-base64", Data(repeating: 42, count: 31).base64EncodedString()] {
            #expect(!UpdateService.hasValidConfiguration([
                "SUPublicEDKey": invalidKey, "SUFeedURL": "https://example.com/appcast.xml"
            ]))
        }
        #expect(!UpdateService.hasValidConfiguration([:]))
    }

    @Test func rejectsUnsafeFeeds() {
        for feed in ["http://example.com/appcast.xml", "file:///tmp/appcast.xml", "https:", "https://user:password@example.com/appcast.xml"] {
            #expect(!UpdateService.hasValidConfiguration(["SUPublicEDKey": key, "SUFeedURL": feed]))
        }
    }

    @Test func sourceBuildDoesNotStartUpdateChecks() throws {
        let suite = "UpdateServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = UpdateService(defaults: defaults)
        service.start(bundle: Bundle(for: UpdateTestBundleToken.self))
        #expect(!service.isConfigured)
        #expect(!service.canPresentUpdate)
        #expect(!service.automaticallyChecksForUpdates)
        #expect(!service.notificationsEnabled)
        #expect(service.statusMessage == "This build is not configured for updates. Use the signed release in Applications to check for updates.")
    }
}

private final class UpdateTestBundleToken: NSObject {}
