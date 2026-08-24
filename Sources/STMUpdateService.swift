import Foundation

enum STMUpdateCheckMode: Equatable {
    case automatic
    case manual
}

enum STMUpdateCheckResult {
    case notDue
    case upToDate
    case updateAvailable(STMUpdateRelease)
}

final class STMUpdateService {
    static let maximumReleaseResponseBytes: Int64 = Int64(STMUpdateReleaseParser.maximumResponseBytes)

    private let transport: STMUpdateTransport

    init(transport: STMUpdateTransport = STMURLSessionUpdateTransport()) {
        self.transport = transport
    }

    func check(
        currentVersionString: String,
        mode: STMUpdateCheckMode,
        now: Date = Date()
    ) async throws -> STMUpdateCheckResult {
        guard let currentVersion = STMSemanticVersion(currentVersionString) else {
            throw STMUpdateError.invalidInstalledVersion
        }
        if mode == .automatic,
           !STMUpdateCheckPolicy.isAutomaticCheckDue(
               lastSuccessfulCheck: ConfigStore.lastSuccessfulUpdateCheck(),
               now: now
           ) {
            return .notDue
        }

        let data = try await transport.fetchData(
            from: STMUpdateRepository.releasesAPIURL,
            maximumBytes: Self.maximumReleaseResponseBytes
        )
        let releases = try STMUpdateReleaseParser.parse(data)
        try ConfigStore.recordSuccessfulUpdateCheck(at: now)
        let dismissed = ConfigStore.dismissedUpdateVersion().flatMap(STMSemanticVersion.init)
        if let release = STMUpdateReleaseSelector.latestNewerRelease(
            in: releases,
            than: currentVersion,
            dismissedVersion: dismissed
        ) {
            return .updateAvailable(release)
        }
        return .upToDate
    }

    func dismiss(version: STMSemanticVersion) throws {
        try ConfigStore.setDismissedUpdateVersion(version.description)
    }

    func download(
        _ release: STMUpdateRelease,
        downloadsDirectory: URL? = nil
    ) async throws -> URL {
        let manifest = try await transport.fetchData(
            from: release.checksumManifest.downloadURL,
            maximumBytes: release.checksumManifest.size
        )
        guard Int64(manifest.count) == release.checksumManifest.size else {
            throw STMUpdateError.downloadSizeMismatch
        }
        _ = try STMUpdateChecksumVerifier.expectedChecksum(
            in: manifest,
            filename: release.diskImage.name
        )

        let temporaryURL = try await transport.downloadFile(
            from: release.diskImage.downloadURL,
            maximumBytes: release.diskImage.size
        )
        var shouldDeleteTemporaryFile = true
        defer {
            if shouldDeleteTemporaryFile { try? FileManager.default.removeItem(at: temporaryURL) }
        }

        let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let fileSize = values.fileSize else {
            throw STMUpdateError.invalidDownload
        }
        guard Int64(fileSize) == release.diskImage.size else {
            throw STMUpdateError.downloadSizeMismatch
        }
        try STMUpdateChecksumVerifier.verify(
            fileURL: temporaryURL,
            manifestData: manifest,
            filename: release.diskImage.name
        )
        let destination = try STMUpdateDownloadStore.moveToDownloads(
            temporaryURL,
            filename: release.diskImage.name,
            downloadsDirectory: downloadsDirectory
        )
        shouldDeleteTemporaryFile = false
        return destination
    }
}
