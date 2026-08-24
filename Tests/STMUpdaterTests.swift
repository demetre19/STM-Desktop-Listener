import Darwin
import Foundation

@main
struct STMUpdaterTests {
    private static var checks = 0

    static func main() throws {
        try testSemanticVersionOrdering()
        try testDraftExclusionAndReleaseOrdering()
        try testURLAndAssetRejection()
        try testChecksumVerification()
        testDailyEligibility()
        try testDismissedVersionSelection()
        try testCollisionSafeMove()
        print("STMUpdaterTests: all \(checks) checks passed")
    }

    private static func testSemanticVersionOrdering() throws {
        let ordered = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
            "1.0.1",
            "2.0.0",
        ].compactMap(STMSemanticVersion.init)
        expect(ordered.count == 10, "strict semantic-version fixtures parse")
        for pair in zip(ordered, ordered.dropFirst()) {
            expect(pair.0 < pair.1, "semantic-version precedence orders \(pair.0) before \(pair.1)")
        }
        expect(
            STMSemanticVersion("1.2.3+build.1") == STMSemanticVersion("1.2.3+build.2"),
            "build metadata does not change semantic precedence"
        )
        for invalid in ["1", "1.2", "01.2.3", "1.02.3", "1.2.03", "1.2.3-01", "1.2.3-", "v1.2.3", "1.2.3+", "1.2.3 beta"] {
            expect(STMSemanticVersion(invalid) == nil, "invalid semantic version is rejected: \(invalid)")
        }
    }

    private static func testDraftExclusionAndReleaseOrdering() throws {
        let json: [Any] = [
            releaseJSON(version: "9.0.0", draft: true),
            releaseJSON(version: "1.5.0", prerelease: false),
            releaseJSON(version: "2.0.0-beta.1", prerelease: true),
        ]
        let releases = try STMUpdateReleaseParser.parse(JSONSerialization.data(withJSONObject: json))
        expect(releases.count == 2, "draft releases are excluded")
        expect(releases.map(\.version.description) == ["2.0.0-beta.1", "1.5.0"], "stable and prerelease releases use semantic ordering")
        expect(releases[0].isPrerelease, "GitHub prerelease channel is preserved")
        expect(
            releases[0].releasePageURL.absoluteString == "https://github.com/demetre19/STM-Desktop-Listener-Releases/releases/tag/v2.0.0-beta.1",
            "the exact validated release page is exposed"
        )
        expect(releases[0].notes == "Faster capture and safer update checks.", "bounded release notes are retained for the update prompt")
    }

    private static func testURLAndAssetRejection() throws {
        expect(
            STMUpdateURLValidator.isReleasePage(
                URL(string: "https://github.com/demetre19/STM-Desktop-Listener-Releases/releases/tag/v1.2.3")!,
                tag: "v1.2.3"
            ),
            "canonical repository release page is accepted"
        )
        let invalidPages = [
            "http://github.com/demetre19/STM-Desktop-Listener-Releases/releases/tag/v1.2.3",
            "https://github.com.evil.example/demetre19/STM-Desktop-Listener-Releases/releases/tag/v1.2.3",
            "https://user@github.com/demetre19/STM-Desktop-Listener-Releases/releases/tag/v1.2.3",
            "https://github.com/demetre19/Other/releases/tag/v1.2.3",
            "https://github.com/demetre19/STM-Desktop-Listener-Releases/releases/tag/v1.2.3?download=1",
        ]
        for value in invalidPages {
            expect(!STMUpdateURLValidator.isReleasePage(URL(string: value)!, tag: "v1.2.3"), "noncanonical release URL is rejected: \(value)")
        }
        expect(
            STMUpdateURLValidator.isAllowedTransportURL(URL(string: "https://release-assets.githubusercontent.com/download.dmg")!),
            "GitHub-controlled release asset redirects are accepted"
        )
        expect(
            !STMUpdateURLValidator.isAllowedTransportURL(URL(string: "https://githubusercontent.com.evil.example/download.dmg")!),
            "lookalike transport hosts are rejected"
        )
        expect(
            !STMUpdateURLValidator.isReleaseAsset(
                URL(string: "https://github.com/attacker/STM-Desktop-Listener-Releases/releases/download/v1.2.3/STM-Desktop-Listener-Mac-arm64-v1.2.3.dmg")!,
                tag: "v1.2.3",
                filename: "STM-Desktop-Listener-Mac-arm64-v1.2.3.dmg"
            ),
            "asset URLs from another repository are rejected"
        )

        var wrongRepository = releaseJSON(version: "1.2.3")
        wrongRepository["html_url"] = "https://github.com/attacker/STM-Desktop-Listener-Releases/releases/tag/v1.2.3"
        try expect(try parsedCount(wrongRepository) == 0, "wrong release-page repository is rejected")

        var insecureAsset = releaseJSON(version: "1.2.3")
        var insecureAssets = insecureAsset["assets"] as! [[String: Any]]
        insecureAssets[0]["browser_download_url"] = "http://github.com/demetre19/STM-Desktop-Listener-Releases/releases/download/v1.2.3/STM-Desktop-Listener-Mac-arm64-v1.2.3.dmg"
        insecureAsset["assets"] = insecureAssets
        try expect(try parsedCount(insecureAsset) == 0, "non-HTTPS asset is rejected")

        var wrongAssetName = releaseJSON(version: "1.2.3")
        var wrongNameAssets = wrongAssetName["assets"] as! [[String: Any]]
        wrongNameAssets[0]["name"] = "STM-Desktop-Listener-Mac-v1.2.3.dmg"
        wrongAssetName["assets"] = wrongNameAssets
        try expect(try parsedCount(wrongAssetName) == 0, "non-exact arm64 DMG name is rejected")

        var duplicateAsset = releaseJSON(version: "1.2.3")
        var duplicateAssets = duplicateAsset["assets"] as! [[String: Any]]
        duplicateAssets.append(duplicateAssets[0])
        duplicateAsset["assets"] = duplicateAssets
        try expect(try parsedCount(duplicateAsset) == 0, "duplicate exact assets are rejected as ambiguous")

        var oversizedAsset = releaseJSON(version: "1.2.3")
        var oversizedAssets = oversizedAsset["assets"] as! [[String: Any]]
        oversizedAssets[0]["size"] = STMUpdateReleaseParser.maximumDiskImageBytes + 1
        oversizedAsset["assets"] = oversizedAssets
        try expect(try parsedCount(oversizedAsset) == 0, "oversized DMG metadata is rejected")
    }

    private static func testChecksumVerification() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let filename = "STM-Desktop-Listener-Mac-arm64-v1.2.3.dmg"
        let validFile = directory.appendingPathComponent("valid.dmg")
        try Data("hello world".utf8).write(to: validFile)
        let expectedHash = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
        let manifest = Data("\(expectedHash)  \(filename)\n".utf8)
        try STMUpdateChecksumVerifier.verify(fileURL: validFile, manifestData: manifest, filename: filename)
        expect(FileManager.default.fileExists(atPath: validFile.path), "matching checksum preserves verified download")

        let mismatchedFile = directory.appendingPathComponent("mismatch.dmg")
        try Data("tampered".utf8).write(to: mismatchedFile)
        expectThrows(.checksumMismatch, "checksum mismatch is reported") {
            try STMUpdateChecksumVerifier.verify(fileURL: mismatchedFile, manifestData: manifest, filename: filename)
        }
        expect(!FileManager.default.fileExists(atPath: mismatchedFile.path), "checksum mismatch deletes the untrusted file")

        let duplicateManifest = Data("\(expectedHash)  \(filename)\n\(expectedHash)  \(filename)\n".utf8)
        expectThrows(.invalidChecksumManifest, "duplicate checksum entries are rejected") {
            _ = try STMUpdateChecksumVerifier.expectedChecksum(in: duplicateManifest, filename: filename)
        }
        let traversalManifest = Data("\(expectedHash)  ../\(filename)\n".utf8)
        expectThrows(.invalidChecksumManifest, "checksum path traversal is rejected") {
            _ = try STMUpdateChecksumVerifier.expectedChecksum(in: traversalManifest, filename: filename)
        }
    }

    private static func testDailyEligibility() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        expect(STMUpdateCheckPolicy.isAutomaticCheckDue(lastSuccessfulCheck: nil, now: now), "first automatic check is due")
        expect(
            !STMUpdateCheckPolicy.isAutomaticCheckDue(lastSuccessfulCheck: now.addingTimeInterval(-86_399), now: now),
            "automatic check is not due before 24 hours"
        )
        expect(
            STMUpdateCheckPolicy.isAutomaticCheckDue(lastSuccessfulCheck: now.addingTimeInterval(-86_400), now: now),
            "automatic check is due exactly at 24 hours"
        )
        expect(
            !STMUpdateCheckPolicy.isAutomaticCheckDue(lastSuccessfulCheck: now.addingTimeInterval(60), now: now),
            "a future persisted check time cannot trigger an immediate retry"
        )
    }

    private static func testDismissedVersionSelection() throws {
        let releases = try STMUpdateReleaseParser.parse(JSONSerialization.data(withJSONObject: [
            releaseJSON(version: "1.1.0"),
            releaseJSON(version: "1.2.0-beta.1", prerelease: true),
            releaseJSON(version: "2.0.0"),
        ]))
        let current = STMSemanticVersion("1.0.0")!
        let latest = STMUpdateReleaseSelector.latestNewerRelease(in: releases, than: current, dismissedVersion: nil)
        expect(latest?.version.description == "2.0.0", "latest eligible release is selected")
        let afterDismissal = STMUpdateReleaseSelector.latestNewerRelease(
            in: releases,
            than: current,
            dismissedVersion: STMSemanticVersion("2.0.0")
        )
        expect(afterDismissal == nil, "dismissal suppresses the dismissed release and all older releases")
        let newerReleases = try STMUpdateReleaseParser.parse(JSONSerialization.data(withJSONObject: [
            releaseJSON(version: "2.0.0"),
            releaseJSON(version: "2.0.1"),
        ]))
        let afterNewRelease = STMUpdateReleaseSelector.latestNewerRelease(
            in: newerReleases,
            than: current,
            dismissedVersion: STMSemanticVersion("2.0.0")
        )
        expect(afterNewRelease?.version.description == "2.0.1", "a newer release becomes eligible after dismissal")
    }

    private static func testCollisionSafeMove() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let filename = "STM-Desktop-Listener-Mac-arm64-v1.2.3.dmg"
        try Data("first".utf8).write(to: downloads.appendingPathComponent(filename))
        try Data("second".utf8).write(to: downloads.appendingPathComponent("STM-Desktop-Listener-Mac-arm64-v1.2.3 (2).dmg"))
        let source = root.appendingPathComponent("incoming.dmg")
        try Data("new".utf8).write(to: source)

        let destination = try STMUpdateDownloadStore.moveToDownloads(
            source,
            filename: filename,
            downloadsDirectory: downloads
        )
        expect(destination.lastPathComponent == "STM-Desktop-Listener-Mac-arm64-v1.2.3 (3).dmg", "download collisions receive the next suffix")
        try expect((try Data(contentsOf: destination)) == Data("new".utf8), "collision-safe move preserves incoming file")
        try expect((try Data(contentsOf: downloads.appendingPathComponent(filename))) == Data("first".utf8), "collision-safe move never overwrites an existing download")
    }

    private static func releaseJSON(version: String, draft: Bool = false, prerelease: Bool = false) -> [String: Any] {
        let tag = "v\(version)"
        let dmgName = "STM-Desktop-Listener-Mac-arm64-v\(version).dmg"
        let base = "https://github.com/demetre19/STM-Desktop-Listener-Releases"
        return [
            "tag_name": tag,
            "html_url": "\(base)/releases/tag/\(tag)",
            "draft": draft,
            "prerelease": prerelease,
            "published_at": "2026-08-24T12:00:00Z",
            "body": "Faster capture and safer update checks.",
            "assets": [
                [
                    "name": dmgName,
                    "browser_download_url": "\(base)/releases/download/\(tag)/\(dmgName)",
                    "size": 123,
                ],
                [
                    "name": "SHA256SUMS.txt",
                    "browser_download_url": "\(base)/releases/download/\(tag)/SHA256SUMS.txt",
                    "size": 128,
                ],
            ],
        ]
    }

    private static func parsedCount(_ release: [String: Any]) throws -> Int {
        try STMUpdateReleaseParser.parse(JSONSerialization.data(withJSONObject: [release])).count
    }

    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stm-updater-tests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            fail("could not create temporary directory: \(error)")
        }
        return url
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        checks += 1
        let passed = try condition()
        if !passed { fail(message) }
    }

    private static func expectThrows(_ expected: STMUpdateError, _ message: String, operation: () throws -> Void) {
        checks += 1
        do {
            try operation()
            fail("\(message): expected \(expected)")
        } catch let error as STMUpdateError {
            if error != expected { fail("\(message): expected \(expected), got \(error)") }
        } catch {
            fail("\(message): expected STMUpdateError, got \(error)")
        }
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(EXIT_FAILURE)
    }
}
