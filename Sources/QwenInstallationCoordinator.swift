import Foundation

struct QwenInstallationProgress: Sendable {
    let fraction: Double
    let message: String

    init(fraction: Double, message: String) {
        self.fraction = min(max(fraction, 0), 1)
        self.message = message
    }
}

extension Notification.Name {
    static let qwenInstallationStateChanged = Notification.Name("com.seotimemachines.stm.qwen-installation-state-changed")
}

@MainActor
final class QwenInstallationCoordinator {
    struct State {
        let isRunning: Bool
        let fraction: Double
        let message: String
        let errorMessage: String?
    }

    static let shared = QwenInstallationCoordinator()

    private(set) var state: State
    private var task: Task<Void, Never>?

    private init() {
        let isReady = QwenRuntimeManager.isInstalled && QwenModelManager.resolvedModelURL() != nil
        state = State(
            isRunning: false,
            fraction: isReady ? 1 : 0,
            message: QwenModelManager.statusText(),
            errorMessage: nil
        )
    }

    func start() {
        guard task == nil else {
            publish()
            return
        }

        update(State(
            isRunning: true,
            fraction: 0,
            message: "Preparing Qwen3-ASR installation…",
            errorMessage: nil
        ))

        let progressHandler: @Sendable (QwenInstallationProgress) -> Void = { progress in
            Task { @MainActor in
                QwenInstallationCoordinator.shared.receive(progress)
            }
        }

        task = Task { @MainActor in
            do {
                _ = try await QwenModelManager.install(progress: progressHandler)
                task = nil
                Logger.log("qwen installation complete model=Qwen3-ASR-0.6B-8bit")
                update(State(
                    isRunning: false,
                    fraction: 1,
                    message: QwenModelManager.statusText(),
                    errorMessage: nil
                ))
                STMNotifier.show(
                    title: "Qwen3-ASR Local Backup Ready",
                    body: "The local model finished downloading and is ready to select in Voice AI settings. Cloudflare remains preferred."
                )
            } catch {
                task = nil
                let message = error.localizedDescription
                update(State(
                    isRunning: false,
                    fraction: 0,
                    message: QwenModelManager.statusText(),
                    errorMessage: message
                ))
                Logger.log("qwen installation failed: \(message)")
                STMNotifier.show(
                    title: "Qwen3-ASR Installation Failed",
                    body: message
                )
            }
        }
    }

    private func receive(_ progress: QwenInstallationProgress) {
        guard task != nil else { return }
        update(State(
            isRunning: true,
            fraction: progress.fraction,
            message: progress.message,
            errorMessage: nil
        ))
    }

    private func update(_ newState: State) {
        state = newState
        publish()
    }

    private func publish() {
        NotificationCenter.default.post(name: .qwenInstallationStateChanged, object: self)
    }
}
