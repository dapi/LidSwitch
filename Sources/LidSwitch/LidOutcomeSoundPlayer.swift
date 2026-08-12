import AppKit
import LidSwitchDaemonProtocol

final class LidOutcomeSoundPlayer: NSObject, NSSoundDelegate {
    private var currentSound: NSSound?
    private var completion: (() -> Void)?

    func play(policy: DaemonLidPolicy, completion: (() -> Void)? = nil) {
        currentSound?.stop()
        self.completion = nil

        let name = policy == .work ? "Glass" : "Funk"
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            completion?()
            return
        }
        currentSound = sound
        sound.delegate = self
        self.completion = completion
        if !sound.play() {
            finish()
        }
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        guard sound === currentSound else { return }
        finish()
    }

    private func finish() {
        let callback = completion
        completion = nil
        currentSound = nil
        callback?()
    }
}
