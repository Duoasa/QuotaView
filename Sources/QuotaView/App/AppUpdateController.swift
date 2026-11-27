import Foundation
import Security
import Sparkle

enum AppUpdateAvailability: Equatable {
    case available
    case debugBuild
    case notApplicationBundle
    case unexpectedBundleIdentifier
    case untrustedSignature
    case invalidConfiguration
}

struct AppUpdateEnvironment: Equatable {
    private static let officialSigningTeamIdentifier = "BUUH229D5Q"

    let isDebugBuild: Bool
    let isApplicationBundle: Bool
    let bundleIdentifier: String?
    let expectedBundleIdentifier: String
    let signingTeamIdentifier: String?
    let expectedSigningTeamIdentifier: String?
    let feedURLString: String?
    let publicEDKey: String?

    var availability: AppUpdateAvailability {
        if isDebugBuild {
            return .debugBuild
        }
        guard isApplicationBundle else {
            return .notApplicationBundle
        }
        guard bundleIdentifier == expectedBundleIdentifier else {
            return .unexpectedBundleIdentifier
        }
        guard
            let expectedSigningTeamIdentifier,
            !expectedSigningTeamIdentifier.isEmpty,
            signingTeamIdentifier == expectedSigningTeamIdentifier
        else {
            return .untrustedSignature
        }
        guard
            let feedURLString,
            let feedURL = URL(string: feedURLString),
            feedURL.scheme?.lowercased() == "https",
            let publicEDKey,
            !publicEDKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            return .invalidConfiguration
        }
        return .available
    }

    static func current(bundle: Bundle = .main) -> Self {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif

        return Self(
            isDebugBuild: isDebugBuild,
            isApplicationBundle:
                bundle.bundleURL.pathExtension.lowercased() == "app",
            bundleIdentifier: bundle.bundleIdentifier,
            expectedBundleIdentifier: "com.quotaview.menubar",
            signingTeamIdentifier: signingTeamIdentifier(
                for: bundle.bundleURL
            ),
            expectedSigningTeamIdentifier: officialSigningTeamIdentifier,
            feedURLString: bundle.object(
                forInfoDictionaryKey: "SUFeedURL"
            ) as? String,
            publicEDKey: bundle.object(
                forInfoDictionaryKey: "SUPublicEDKey"
            ) as? String
        )
    }

    private static func signingTeamIdentifier(
        for bundleURL: URL
    ) -> String? {
        var staticCode: SecStaticCode?
        let creationStatus = SecStaticCodeCreateWithPath(
            bundleURL as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard creationStatus == errSecSuccess, let staticCode else {
            return nil
        }

        var signingInformation: CFDictionary?
        let informationStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard
            informationStatus == errSecSuccess,
            let information = signingInformation as? [String: Any]
        else {
            return nil
        }

        return information[kSecCodeInfoTeamIdentifier as String]
            as? String
    }
}

@MainActor
final class AppUpdateController: ObservableObject {
    @Published private(set) var availability: AppUpdateAvailability
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false

    private let standardUpdaterController:
        SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?
    private var automaticChecksObservation: NSKeyValueObservation?
    private var hasStarted = false

    init(environment: AppUpdateEnvironment? = nil) {
        let resolvedEnvironment = environment ?? .current()
        let resolvedAvailability = resolvedEnvironment.availability
        availability = resolvedAvailability

        guard resolvedAvailability == .available else {
            standardUpdaterController = nil
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        standardUpdaterController = controller
    }

    func start() {
        guard
            !hasStarted,
            availability == .available,
            let controller = standardUpdaterController
        else {
            return
        }
        hasStarted = true
        controller.startUpdater()

        let updater = controller.updater
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates =
            updater.automaticallyChecksForUpdates

        canCheckObservation = updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = value
            }
        }
        automaticChecksObservation = updater.observe(
            \.automaticallyChecksForUpdates,
            options: [.initial, .new]
        ) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor [weak self] in
                self?.automaticallyChecksForUpdates = value
            }
        }
    }

    func checkForUpdates() {
        guard
            availability == .available,
            let updater = standardUpdaterController?.updater,
            updater.canCheckForUpdates
        else {
            return
        }
        updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        guard
            availability == .available,
            let updater = standardUpdaterController?.updater
        else {
            return
        }
        updater.automaticallyChecksForUpdates = isEnabled
        automaticallyChecksForUpdates = isEnabled
    }
}
