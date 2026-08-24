# STM Desktop Listener GitHub Updates PRD

## PRD

### Status

Draft for owner review. This document defines the product requirements only. Implementation planning begins only after the exact approval keyword `APPROVE PRD`.

### Product overview

STM Desktop Listener began as a companion to SEO Time Machines and has become an independent Mac toolbelt that anyone can use. Its source repository will remain the private source of truth, while a separate public GitHub repository will distribute precompiled releases to users who should never need to compile the app.

The first updater release will notify users when a newer published version exists. It will offer two user-controlled paths:

1. Open the exact GitHub Release page.
2. Download the release DMG directly, verify its checksum, and reveal it in Finder.

The app will not silently replace itself in this phase.

### Objectives

- Make GitHub the authoritative source for source code, versions, release notes, and downloadable packages.
- Give non-technical users a stable public link to a precompiled macOS app.
- Remove Xcode, Command Line Tools, Git, and local compilation from the ordinary installation journey.
- Notify installed users about every newer published release, including prereleases.
- Keep private source and public binary distribution clearly separated.
- Make every published artifact traceable to one version tag and one source commit.
- Verify downloaded files before presenting them to the user.

### Non-goals for the first updater release

- Silent or forced installation.
- Replacing the running app automatically.
- Background installation requiring administrator privileges.
- Delta updates or binary patching.
- Rollback automation.
- Intel support while the bundled ONNX Runtime remains arm64-only.
- Apple notarization in the initial ad hoc-signed release phase.
- Hosting update metadata on a separate server.

### Target audience

#### Primary users

Mac users who want STM Desktop Listener as a ready-to-install utility and do not want to compile software.

#### Maintainers

The repository owner or an authorized maintainer who publishes a version tag after the source has passed release verification.

### Platform and compatibility

- Native Swift and AppKit application.
- macOS 14 or later.
- Apple silicon in the initial public release channel.
- Full Xcode is not required by end users.
- End users install a precompiled DMG or ZIP from the public GitHub Releases repository.

### Repository model

#### Private source repository

Recommended repository: `demetre19/STM-Desktop-Listener`

Responsibilities:

- Canonical source code.
- Version value and release configuration.
- Build and packaging scripts.
- GitHub Actions release workflow.
- Tests and release verification.
- No locally generated `dist/` artifacts committed to normal source history.
- No private workstation paths, personal email addresses, credentials, or private project instructions.

#### Public releases repository

Recommended repository: `demetre19/STM-Desktop-Listener-Releases`

Responsibilities:

- Public GitHub Releases.
- Precompiled versioned DMG and ZIP assets.
- SHA-256 checksum manifest.
- User-facing release notes.
- Stable latest-release download route.
- No private application source or credentials.

The public repository may contain a minimal README that explains installation, Gatekeeper handling for the initial ad hoc-signed phase, supported macOS versions, current architecture, and links back to public documentation that is safe to expose.

### Source-of-truth release flow

```text
Maintainer updates version in private source repository
                    |
                    v
Focused tests and native build pass
                    |
                    v
Maintainer pushes version tag, for example v0.1.4
                    |
                    v
Private GitHub Actions workflow checks out that exact tag
                    |
                    v
Build arm64 native app -> package DMG and ZIP
                    |
                    v
Generate SHA-256 manifest and release metadata
                    |
                    v
Publish matching release in public downloads repository
                    |
          +---------+----------+
          |                    |
          v                    v
New users download       Installed apps detect
precompiled package      the newer release
```

### Versioning requirements

- Use semantic version identifiers such as `0.1.4`.
- Git tags use the corresponding `v0.1.4` form.
- `CFBundleShortVersionString`, release tag, asset filenames, release metadata, and displayed version must agree.
- `CFBundleVersion` must increase for every shipped build.
- A tag is immutable. Corrected artifacts require a new version rather than replacing files under an existing tag.
- Version comparison must be deterministic and must not use plain alphabetical string ordering.

### Public release assets

Every public release must contain:

- `STM-Desktop-Listener-Mac-arm64-v<version>.dmg`
- `STM-Desktop-Listener-Mac-arm64-v<version>.zip`
- `SHA256SUMS.txt`
- Release notes with user-visible changes.
- Minimum macOS version and architecture.
- Signing and notarization status.
- Installation instructions appropriate to that signing status.

Optional future assets may include a universal package only after every linked native dependency supports both arm64 and x86_64.

### GitHub Actions release requirements

A version tag in the private source repository triggers the release workflow.

The workflow must:

1. Check out the exact tag.
2. Confirm the source version matches the tag.
3. Build the native app from repository source and reviewed vendored dependencies.
4. Run the focused release tests defined by the repository.
5. Package versioned DMG and ZIP assets.
6. Verify the app architecture and bundle identity.
7. Verify no raw credentials, personal email addresses, or user-specific absolute paths appear in source-controlled release content or embedded app strings.
8. Generate SHA-256 checksums after packaging.
9. Create the matching public GitHub Release.
10. Upload assets and release notes without committing generated packages to source history.
11. Fail without publishing a partial release if any required gate fails.

The workflow must use a narrowly scoped GitHub credential that can create releases only in the public downloads repository. Secrets must remain in GitHub Actions secrets and must never appear in workflow logs or artifacts.

### Release channels

The app checks all publicly published GitHub Releases:

- Stable releases are eligible.
- GitHub prereleases are eligible.
- Draft releases are ignored because they are not public.
- The newest eligible version greater than the installed version is offered.
- The notification must clearly label prerelease versions so users understand they may be less stable.

There is no stable-only preference in the initial requirement because the owner selected all published channels.

### Update discovery

The app must provide:

- One quiet automatic check no more than once every 24 hours.
- A manual **Check for Updates** action in the Tools tab.
- No startup delay while the network request runs.
- A short timeout and a clean failure path when GitHub is unavailable.
- No authentication requirement for the public releases repository.
- Local persistence of the last successful check time and the last version dismissed by the user.

The GitHub API response is untrusted external input. The app must validate required fields and allow only expected HTTPS GitHub URLs belonging to the configured public repository.

### Update notification experience

When a newer release exists, the app shows:

- Installed version.
- Available version.
- Stable or prerelease label.
- Release title and concise release notes.
- Package architecture and minimum macOS version.
- Signing and notarization status.
- **Download DMG** primary action.
- **Open Release Page** secondary action.
- **Later** action.

The notification must not claim that an update is installed, installing, or safe to run before the relevant verification has completed.

If no newer release exists, a manual check shows **STM Desktop Listener is up to date**. Automatic checks remain quiet when no update exists or a transient network error occurs.

### Direct DMG download

When the user chooses **Download DMG**, the app must:

1. Select the asset whose version and architecture match the release and current Mac.
2. Download through HTTPS into a temporary app-owned location.
3. Enforce a bounded maximum download size.
4. Download or retrieve the release checksum manifest.
5. Calculate the local SHA-256 hash.
6. Compare the calculated hash with the exact expected asset hash.
7. Delete the temporary file and show a clear failure if verification does not match.
8. Move a verified DMG into the user's Downloads folder using its versioned filename.
9. Reveal the verified DMG in Finder.
10. Leave installation under the user's control.

Redirects must remain on approved HTTPS GitHub asset hosts. Existing files must not be overwritten silently.

### Open Release Page

**Open Release Page** opens the exact selected version in the default browser. It must not open a generic repository page when an exact release URL is available.

This path remains available if direct downloading fails.

### Initial signing policy

The initial public packages may be ad hoc signed because that is the selected first phase.

Requirements:

- Release notes and installation instructions must say clearly that the app is ad hoc signed and not Apple-notarized.
- The app must not present the package as Apple-verified.
- Gatekeeper handling must use the least risky documented user action and must not encourage globally disabling Gatekeeper.
- Checksums verify download integrity but do not replace code-signing identity or notarization.
- In-app self-installation and silent updates remain prohibited while releases are ad hoc signed.

Recommended follow-up: move to Developer ID Application signing and Apple notarization before broad public promotion or any automatic installation feature.

### Security and privacy requirements

- No update request may include app credentials, transcription tokens, machine paths, user identity, or configuration contents.
- The public update check uses only public GitHub release metadata.
- Only HTTPS is permitted.
- Repository owner, repository name, release URL, asset URL, filename, version, size, and checksum are validated before use.
- Downloaded content is treated as untrusted until SHA-256 verification succeeds.
- Temporary failed downloads are removed.
- Update failures must not affect dictation, screenshot, power, or other app features.
- GitHub workflow logs must not print release credentials.
- Public release files must be scanned for embedded personal paths and credentials before upload.
- The source repository must continue using a GitHub no-reply commit address.

### Conceptual data model

#### UpdatePreferences

- `automaticChecksEnabled: Bool`, default `true`
- `lastSuccessfulCheckAt: Date?`
- `lastDismissedVersion: String?`
- `publicRepositoryOwner: String`, fixed release configuration
- `publicRepositoryName: String`, fixed release configuration

#### ReleaseRecord

- `version: SemanticVersion`
- `tagName: String`
- `title: String`
- `notes: String`
- `isPrerelease: Bool`
- `publishedAt: Date`
- `releasePageURL: URL`
- `minimumMacOSVersion: String`
- `architecture: String`
- `assets: [ReleaseAsset]`

#### ReleaseAsset

- `name: String`
- `downloadURL: URL`
- `sizeBytes: Int64`
- `contentType: String`
- `sha256: String`

### Availability and GitHub limits

- Update checks must respect unauthenticated GitHub API rate limits.
- A 24-hour automatic interval keeps ordinary usage far below expected limits.
- The app must cache only the minimal metadata required for check timing and dismissal behavior.
- GitHub outage or rate limiting must degrade to a quiet retry later, while a manual check shows an actionable message.
- Release downloads use GitHub-hosted assets and do not require a separate hosting bill.

### Costs

Potential costs include:

- GitHub Actions minutes and artifact storage, subject to the account and private-repository plan.
- GitHub Release asset storage and bandwidth under GitHub's applicable terms and limits.
- Apple Developer Program membership when Developer ID signing and notarization are adopted.
- No separate update server is required for the first release.

### User-facing documentation

The main README and public releases README must provide:

- A prominent latest-download link.
- A clear statement that users download a precompiled app and do not compile it.
- Supported macOS and architecture.
- DMG as the recommended format and ZIP as the alternative.
- Initial ad hoc-signing and Gatekeeper instructions.
- Checksum verification instructions for advanced users.
- Release-history link.
- A short explanation of in-app update notifications.

Recommended stable routes:

- Releases page: `https://github.com/demetre19/STM-Desktop-Listener-Releases/releases`
- Latest release: `https://github.com/demetre19/STM-Desktop-Listener-Releases/releases/latest`

A direct asset URL may change with each version, so the README should link to the latest release page unless a maintained redirect is introduced.

### Acceptance criteria

#### Public downloads

- A user without repository access can open the public releases page.
- The user can download a versioned DMG or ZIP without GitHub authentication.
- The public repository does not expose private source, credentials, personal paths, or personal email addresses.

#### Reproducible tagged release

- Pushing an approved version tag builds from that exact private source commit.
- A version mismatch or failed verification prevents publication.
- The public release contains DMG, ZIP, checksum manifest, architecture, compatibility, signing status, and release notes.
- Generated packages are not committed to the private source branch.

#### Daily update check

- The app checks at most once in 24 hours unless the user starts a manual check.
- The check does not delay app launch or menu use.
- Stable releases and prereleases are both considered.
- Draft releases are ignored.

#### Notification

- A newer version produces one clear notification with installed and available versions.
- A prerelease is visibly labelled.
- **Later** dismisses the prompt without changing the installed app.
- No notification appears when the installed version is equal to or newer than the latest eligible release.

#### Direct download

- The correct arm64 DMG downloads to a temporary location.
- A valid checksum moves the DMG to Downloads and reveals it in Finder.
- A checksum mismatch deletes the file and blocks installation guidance.
- Network failure leaves the existing app unaffected.

#### Release-page handoff

- The exact version's public GitHub Release opens in the default browser.
- The user can still use this path when direct download fails.

#### Privacy

- Update requests contain no credentials or personal information.
- Public source and release scans contain no user-specific absolute paths or personal author email.
- Release workflow secrets do not appear in logs or artifacts.

### Development phases

#### Phase 1: Public release foundation

- Create the public downloads repository.
- Define asset names and release metadata.
- Add tagged GitHub Actions build and cross-repository publishing.
- Publish a precompiled ad hoc-signed test release with checksums.
- Add latest-download links and installation guidance.

#### Phase 2: Notify and download

- Add GitHub release discovery.
- Add daily and manual checks.
- Add stable and prerelease comparison.
- Add update notification UI.
- Add release-page and verified direct-DMG actions.

#### Phase 3: Trust hardening

- Add Developer ID signing and Apple notarization.
- Update public trust messaging.
- Verify Gatekeeper opens the downloaded app normally.

#### Future phase: User-approved in-app installation

This phase requires a separate approved PRD revision covering signed update manifests, replacement safety, privilege boundaries, relaunch, rollback, interrupted installation recovery, and downgrade prevention.

### Technical challenges and mitigations

#### Private-to-public publishing

Challenge: the private workflow needs limited write access to another repository.

Mitigation: use a narrowly scoped fine-grained GitHub token or GitHub App credential restricted to release creation in the public downloads repository.

#### Ad hoc signing

Challenge: Gatekeeper friction may concern users and prevents a trustworthy self-install flow.

Mitigation: disclose the limitation, keep installation user-controlled, verify checksums, and prioritize Developer ID notarization as the next trust milestone.

#### Version comparison

Challenge: prerelease identifiers and semantic versions can be ordered incorrectly by string comparison.

Mitigation: define and test one semantic-version comparison contract before integration.

#### Release metadata integrity

Challenge: normal GitHub asset metadata does not provide the app with an expected SHA-256 value automatically.

Mitigation: publish a deterministic checksum manifest and bind each expected checksum to an exact versioned filename.

#### GitHub availability

Challenge: network failures or rate limits could make checks unreliable.

Mitigation: use a bounded timeout, daily interval, cached check timestamp, manual retry, and no impact on core app behavior.

### Open decisions for owner review

These do not block review of the PRD, but they must be resolved before implementation planning:

1. Confirm the public repository name `STM-Desktop-Listener-Releases`.
2. Confirm whether automatic daily update checks can be disabled in Settings.
3. Confirm the maximum accepted DMG download size.
4. Confirm how long a dismissed version remains suppressed: until the next version, for 24 hours, or until manual check.
5. Confirm whether GitHub prereleases should use stronger warning copy than a label alone.
6. Confirm whether the first public release should be described as beta while it remains ad hoc signed.
7. Confirm the exact public installation instructions for Gatekeeper after testing them on a clean macOS account.
8. Confirm whether the public releases repository should expose issues or disable them.
9. Confirm release-note ownership and minimum required content.
10. Confirm the future trigger for moving from ad hoc signing to Developer ID notarization.

### Implementation orchestration boundary

After the owner replies with the exact keyword `APPROVE PRD`, the next stage will inspect the current source and release scripts, prove the GitHub API and cross-repository release path programmatically, define implementation lanes and verification gates, and perform an access-readiness check. No updater implementation or release automation should begin before that approval.
