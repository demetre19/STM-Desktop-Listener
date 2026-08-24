import Cocoa

final class SoundEffects: NSObject, NSSoundDelegate {
    static let shared = SoundEffects()
    private var activeSounds: [NSSound] = []

    func playShutter() {
        if let url = Bundle.main.url(forResource: "camera-shutter", withExtension: "mp3"),
           let sound = NSSound(contentsOf: url, byReference: false) {
            sound.delegate = self
            sound.volume = 0.7
            activeSounds.append(sound)
            sound.play()
            return
        }

        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    func sound(_ sound: NSSound, didFinishPlaying finished: Bool) {
        activeSounds.removeAll { $0 === sound }
    }
}
