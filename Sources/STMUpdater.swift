import CryptoKit
import Foundation

struct STMSemanticVersion: Comparable, Hashable, CustomStringConvertible {
    private enum PrereleaseIdentifier: Hashable {
        case numeric(String)
        case alphanumeric(String)

        var text: String {
            switch self {
            case let .numeric(value), let .alphanumeric(value): return value
            }
        }
    }

    let major: Int
    let minor: Int
    let patch: Int
    private let prerelease: [PrereleaseIdentifier]
    private let buildMetadata: [String]

    init?(_ value: String) {
        guard !value.isEmpty, value.count <= 128, value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let buildParts = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard !buildParts[0].isEmpty else { return nil }
        let coreAndPrerelease = buildParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = coreAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              let major = Self.parseCoreNumber(core[0]),
              let minor = Self.parseCoreNumber(core[1]),
              let patch = Self.parseCoreNumber(core[2]) else {
            return nil
        }

        var prerelease: [PrereleaseIdentifier] = []
        if coreAndPrerelease.count == 2 {
            let identifiers = coreAndPrerelease[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty else { return nil }
            for identifier in identifiers {
                guard Self.isValidIdentifier(identifier), !identifier.isEmpty else { return nil }
                if identifier.allSatisfy({ $0.isASCII && $0.isNumber }) {
                    guard identifier.count == 1 || identifier.first != "0" else { return nil }
                    prerelease.append(.numeric(String(identifier)))
                } else {
                    prerelease.append(.alphanumeric(String(identifier)))
                }
            }
        }

        var buildMetadata: [String] = []
        if buildParts.count == 2 {
            let identifiers = buildParts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty, identifiers.allSatisfy({ !$0.isEmpty && Self.isValidIdentifier($0) }) else {
                return nil
            }
            buildMetadata = identifiers.map(String.init)
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    static func fromTag(_ tag: String) -> STMSemanticVersion? {
        guard tag.first == "v" else { return nil }
        return STMSemanticVersion(String(tag.dropFirst()))
    }

    var isPrerelease: Bool { !prerelease.isEmpty }

    var description: String {
        var value = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            value += "-" + prerelease.map(\.text).joined(separator: ".")
        }
        if !buildMetadata.isEmpty {
            value += "+" + buildMetadata.joined(separator: ".")
        }
        return value
    }

    static func == (lhs: STMSemanticVersion, rhs: STMSemanticVersion) -> Bool {
        lhs.major == rhs.major &&
            lhs.minor == rhs.minor &&
            lhs.patch == rhs.patch &&
            lhs.prerelease == rhs.prerelease
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }

    static func < (lhs: STMSemanticVersion, rhs: STMSemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) {
            if left == right { continue }
            switch (left, right) {
            case let (.numeric(leftValue), .numeric(rightValue)):
                if leftValue.count != rightValue.count { return leftValue.count < rightValue.count }
                return leftValue < rightValue
            case (.numeric, .alphanumeric):
                return true
            case (.alphanumeric, .numeric):
                return false
            case let (.alphanumeric(leftValue), .alphanumeric(rightValue)):
                return leftValue < rightValue
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func parseCoreNumber(_ value: Substring) -> Int? {
        guard !value.isEmpty,
              value.allSatisfy({ $0.isASCII && $0.isNumber }),
              value.count == 1 || value.first != "0" else {
            return nil
        }
        return Int(value)
    }

    private static func isValidIdentifier(_ value: Substring) -> Bool {
        value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
        }
    }
}


struct STMUpdateAsset: Hashable {
    let name: String
    let downloadURL: URL
    let size: Int64
}

struct STMUpdateRelease: Hashable {
    let version: STMSemanticVersion
    let tagName: String
    let isPrerelease: Bool
    let publishedAt: Date
    let releasePageURL: URL
    let notes: String
    let diskImage: STMUpdateAsset
    let checksumManifest: STMUpdateAsset
}

enum STMUpdateRepository {
    static let owner = "demetre19"
    static let name = "STM-Desktop-Listener-Releases"
    static let releasesAPIURL = URL(
        string: "https://api.github.com/repos/\(owner)/\(name)/releases?per_page=100"
    )!

    static func diskImageName(for version: STMSemanticVersion) -> String {
        "STM-Desktop-Listener-Mac-arm64-v\(version.description).dmg"
    }
}

enum STMUpdateError: LocalizedError, Equatable {
    case invalidInstalledVersion
    case invalidReleaseResponse
    case responseTooLarge
    case requestFailed(Int)
    case insecureRedirect
    case missingChecksum
    case invalidChecksumManifest
    case checksumMismatch
    case invalidDownload
    case downloadSizeMismatch
    case downloadsDirectoryUnavailable
    case tooManyFilenameCollisions

    var errorDescription: String? {
        switch self {
        case .invalidInstalledVersion: return "The installed app version is not valid semantic version text."
        case .invalidReleaseResponse: return "GitHub returned an invalid release response."
        case .responseTooLarge: return "The GitHub response exceeded the allowed size."
        case let .requestFailed(status): return "GitHub returned HTTP \(status)."
        case .insecureRedirect: return "The download attempted to leave HTTPS."
        case .missingChecksum: return "The checksum manifest does not contain the required disk image."
        case .invalidChecksumManifest: return "The checksum manifest is invalid."
        case .checksumMismatch: return "The downloaded disk image failed SHA-256 verification."
        case .invalidDownload: return "The downloaded file is invalid."
        case .downloadSizeMismatch: return "The downloaded file size does not match the GitHub release metadata."
        case .downloadsDirectoryUnavailable: return "The Downloads folder is unavailable."
        case .tooManyFilenameCollisions: return "A collision-free download filename could not be created."
        }
    }
}

enum STMUpdateReleaseParser {
    static let maximumResponseBytes = 2 * 1024 * 1024
    static let maximumReleaseCount = 100
    static let maximumAssetsPerRelease = 100
    static let maximumDiskImageBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let maximumManifestBytes: Int64 = 128 * 1024

    static func parse(_ data: Data) throws -> [STMUpdateRelease] {
        guard data.count <= maximumResponseBytes else {
            throw STMUpdateError.responseTooLarge
        }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw STMUpdateError.invalidReleaseResponse
        }
        guard let objects = root as? [Any], objects.count <= maximumReleaseCount else {
            throw STMUpdateError.invalidReleaseResponse
        }

        let dateFormatter = ISO8601DateFormatter()
        return objects.compactMap { parseRelease($0, dateFormatter: dateFormatter) }.sorted {
            if $0.version != $1.version { return $0.version > $1.version }
            return $0.publishedAt > $1.publishedAt
        }
    }

    private static func parseRelease(_ object: Any, dateFormatter: ISO8601DateFormatter) -> STMUpdateRelease? {
        guard let json = object as? [String: Any], let draft = json["draft"] as? Bool else { return nil }
        guard !draft,
              let tagName = boundedString(json["tag_name"], maximumLength: 129),
              let version = STMSemanticVersion.fromTag(tagName),
              tagName == "v\(version.description)",
              let prerelease = json["prerelease"] as? Bool,
              let publishedText = boundedString(json["published_at"], maximumLength: 64),
              let publishedAt = dateFormatter.date(from: publishedText),
              let pageText = boundedString(json["html_url"], maximumLength: 2_048),
              let pageURL = URL(string: pageText),
              STMUpdateURLValidator.isReleasePage(pageURL, tag: tagName),
              let notes = boundedReleaseNotes(json["body"]),
              let assets = json["assets"] as? [Any],
              assets.count <= maximumAssetsPerRelease else {
            return nil
        }

        let diskImageName = STMUpdateRepository.diskImageName(for: version)
        let diskImages = assets.compactMap {
            parseAsset($0, expectedName: diskImageName, tag: tagName, maximumBytes: maximumDiskImageBytes)
        }
        let manifests = assets.compactMap {
            parseAsset($0, expectedName: "SHA256SUMS.txt", tag: tagName, maximumBytes: maximumManifestBytes)
        }
        guard diskImages.count == 1, manifests.count == 1 else { return nil }

        return STMUpdateRelease(
            version: version,
            tagName: tagName,
            isPrerelease: prerelease,
            publishedAt: publishedAt,
            releasePageURL: pageURL,
            notes: notes,
            diskImage: diskImages[0],
            checksumManifest: manifests[0]
        )
    }

    private static func parseAsset(
        _ object: Any,
        expectedName: String,
        tag: String,
        maximumBytes: Int64
    ) -> STMUpdateAsset? {
        guard let json = object as? [String: Any],
              let name = boundedString(json["name"], maximumLength: 256),
              name == expectedName,
              let sizeValue = json["size"], !(sizeValue is Bool),
              let size = sizeValue as? Int64, size > 0, size <= maximumBytes,
              let urlText = boundedString(json["browser_download_url"], maximumLength: 2_048),
              let url = URL(string: urlText),
              STMUpdateURLValidator.isReleaseAsset(url, tag: tag, filename: expectedName) else {
            return nil
        }
        return STMUpdateAsset(name: name, downloadURL: url, size: size)
    }

    private static func boundedString(_ value: Any?, maximumLength: Int) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value.count <= maximumLength,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return value
    }
    private static func boundedReleaseNotes(_ value: Any?) -> String? {
        guard let value = value as? String, value.count <= 20_000 else { return nil }
        let allowedControls = CharacterSet(charactersIn: "\n\r\t")
        guard !value.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) && !allowedControls.contains($0)
        }) else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


enum STMUpdateURLValidator {
    static func isReleasePage(_ url: URL, tag: String) -> Bool {
        isExactGitHubURL(url, pathComponents: [
            STMUpdateRepository.owner,
            STMUpdateRepository.name,
            "releases",
            "tag",
            tag,
        ])
    }

    static func isReleaseAsset(_ url: URL, tag: String, filename: String) -> Bool {
        isExactGitHubURL(url, pathComponents: [
            STMUpdateRepository.owner,
            STMUpdateRepository.name,
            "releases",
            "download",
            tag,
            filename,
        ])
    }

    static func isAllowedTransportURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              url.port == nil,
              url.user == nil,
              url.password == nil else {
            return false
        }
        return host == "api.github.com" ||
            host == "github.com" ||
            host.hasSuffix(".githubusercontent.com")
    }

    private static func isExactGitHubURL(_ url: URL, pathComponents: [String]) -> Bool {
        guard url.absoluteString.count <= 2_048,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "github.com",
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return false
        }

        var expected = URL(string: "https://github.com")!
        for component in pathComponents {
            expected.appendPathComponent(component)
        }
        guard let expectedComponents = URLComponents(url: expected, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.percentEncodedPath == expectedComponents.percentEncodedPath
    }
}

enum STMUpdateReleaseSelector {
    static func latestNewerRelease(
        in releases: [STMUpdateRelease],
        than currentVersion: STMSemanticVersion,
        dismissedVersion: STMSemanticVersion?
    ) -> STMUpdateRelease? {
        releases
            .filter { release in
                guard release.version > currentVersion else { return false }
                guard let dismissedVersion else { return true }
                return release.version > dismissedVersion
            }
            .max { $0.version < $1.version }
    }
}

enum STMUpdateCheckPolicy {
    static let dailyInterval: TimeInterval = 24 * 60 * 60

    static func isAutomaticCheckDue(lastSuccessfulCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastSuccessfulCheck else { return true }
        return now.timeIntervalSince(lastSuccessfulCheck) >= dailyInterval
    }
}

protocol STMUpdateTransport {
    func fetchData(from url: URL, maximumBytes: Int64) async throws -> Data
    func downloadFile(from url: URL, maximumBytes: Int64) async throws -> URL
}

final class STMURLSessionUpdateTransport: STMUpdateTransport {
    func fetchData(from url: URL, maximumBytes: Int64) async throws -> Data {
        let fileURL = try await downloadFile(from: url, maximumBytes: maximumBytes)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    func downloadFile(from url: URL, maximumBytes: Int64) async throws -> URL {
        guard STMUpdateURLValidator.isAllowedTransportURL(url), maximumBytes > 0 else {
            throw STMUpdateError.invalidDownload
        }
        return try await STMBoundedDownload(maximumBytes: maximumBytes).start(url: url)
    }
}

private final class STMBoundedDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let maximumBytes: Int64
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var finished = false

    init(maximumBytes: Int64) {
        self.maximumBytes = maximumBytes
    }

    func start(url: URL) async throws -> URL {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 30 * 60
            configuration.httpAdditionalHeaders = [
                "Accept": "application/vnd.github+json",
                "User-Agent": "STM-Desktop-Listener-Updater",
                "X-GitHub-Api-Version": "2022-11-28",
            ]
            let delegateQueue = OperationQueue()
            delegateQueue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)

            lock.lock()
            self.continuation = continuation
            self.session = session
            lock.unlock()

            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(STMUpdateURLValidator.isAllowedTransportURL) == true ? request : nil)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > maximumBytes || totalBytesExpectedToWrite > maximumBytes {
            downloadTask.cancel()
            finish(.failure(STMUpdateError.responseTooLarge))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              response.statusCode == 200 else {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            finish(.failure(STMUpdateError.requestFailed(status)))
            return
        }
        guard let finalURL = response.url,
              STMUpdateURLValidator.isAllowedTransportURL(finalURL) else {
            finish(.failure(STMUpdateError.insecureRedirect))
            return
        }

        do {
            let values = try location.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let fileSize = values.fileSize, fileSize >= 0 else {
                throw STMUpdateError.invalidDownload
            }
            guard Int64(fileSize) <= maximumBytes else { throw STMUpdateError.responseTooLarge }

            let stagedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("stm-update-\(UUID().uuidString)", isDirectory: false)
            try FileManager.default.moveItem(at: location, to: stagedURL)
            finish(.success(stagedURL))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        lock.unlock()

        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
}

enum STMUpdateChecksumVerifier {
    static func expectedChecksum(
        in manifestData: Data,
        filename: String,
        maximumBytes: Int = Int(STMUpdateReleaseParser.maximumManifestBytes)
    ) throws -> String {
        guard manifestData.count <= maximumBytes,
              let manifest = String(data: manifestData, encoding: .utf8),
              !manifest.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw STMUpdateError.invalidChecksumManifest
        }

        var checksum: String?
        for rawLine in manifest.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard line.count >= 66 else { throw STMUpdateError.invalidChecksumManifest }
            let hashEnd = line.index(line.startIndex, offsetBy: 64)
            let hash = String(line[..<hashEnd]).lowercased()
            guard hash.count == 64,
                  hash.unicodeScalars.allSatisfy({
                      (48...57).contains($0.value) || (97...102).contains($0.value)
                  }) else {
                throw STMUpdateError.invalidChecksumManifest
            }

            var remainder = line[hashEnd...]
            guard let separator = remainder.first, separator == " " || separator == "\t" else {
                throw STMUpdateError.invalidChecksumManifest
            }
            remainder = remainder.drop(while: { $0 == " " || $0 == "\t" })
            if remainder.first == "*" { remainder = remainder.dropFirst() }
            let listedName = String(remainder)
            guard !listedName.isEmpty,
                  listedName == URL(fileURLWithPath: listedName).lastPathComponent else {
                throw STMUpdateError.invalidChecksumManifest
            }
            if listedName == filename {
                guard checksum == nil else { throw STMUpdateError.invalidChecksumManifest }
                checksum = hash
            }
        }

        guard let checksum else { throw STMUpdateError.missingChecksum }
        return checksum
    }

    static func verify(fileURL: URL, manifestData: Data, filename: String) throws {
        let expected = try expectedChecksum(in: manifestData, filename: filename)
        let actual = try sha256(of: fileURL)
        guard actual == expected else {
            try? FileManager.default.removeItem(at: fileURL)
            throw STMUpdateError.checksumMismatch
        }
    }

    private static func sha256(of fileURL: URL) throws -> String {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw STMUpdateError.invalidDownload }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum STMUpdateDownloadStore {
    static func moveToDownloads(
        _ sourceURL: URL,
        filename: String,
        downloadsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard sourceURL.isFileURL,
              filename == URL(fileURLWithPath: filename).lastPathComponent,
              !filename.isEmpty else {
            throw STMUpdateError.invalidDownload
        }
        let sourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard sourceValues.isRegularFile == true else { throw STMUpdateError.invalidDownload }
        guard let downloadsDirectory = downloadsDirectory ?? fileManager.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            throw STMUpdateError.downloadsDirectoryUnavailable
        }
        try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

        let nameURL = URL(fileURLWithPath: filename)
        let pathExtension = nameURL.pathExtension
        let stem = nameURL.deletingPathExtension().lastPathComponent
        for collisionIndex in 0..<10_000 {
            let candidateName: String
            if collisionIndex == 0 {
                candidateName = filename
            } else if pathExtension.isEmpty {
                candidateName = "\(stem) (\(collisionIndex + 1))"
            } else {
                candidateName = "\(stem) (\(collisionIndex + 1)).\(pathExtension)"
            }
            let candidate = downloadsDirectory.appendingPathComponent(candidateName, isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) { continue }
            do {
                try fileManager.moveItem(at: sourceURL, to: candidate)
                return candidate
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw STMUpdateError.tooManyFilenameCollisions
    }
}

