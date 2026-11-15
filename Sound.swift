import AppKit
import AVFoundation

// наборы звуков в Sounds/<имя>: key1…key12, space, enter, backspace; генерируются Tools/synth.py
enum SoundPack: String, CaseIterable {
    case clack = "Clack", bright = "Bright", deep = "Deep", crisp = "Crisp", ring = "Ring", soft = "Soft"

    static var current: SoundPack {
        SoundPack(rawValue: UserDefaults.standard.string(forKey: "keySoundPack") ?? "") ?? .clack
    }
}

// звук механической клавиатуры
final class KeySound {
    static let shared = KeySound()

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var keys: [AVAudioPCMBuffer] = []
    private var special: [String: AVAudioPCMBuffer] = [:]
    private var loaded: SoundPack?
    private var next = 0
    private var monitor: Any?
    // все файлы приведены к моно 44.1 кГц, поэтому формат общий
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "keySound") as? Bool ?? true
    }

    private init() {
        // несколько плееров, чтобы быстрые нажатия не обрывали друг друга
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        try? engine.start()
    }

    private func buffer(_ pack: SoundPack, _ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds/\(pack.rawValue)"),
              let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil else { return nil }
        return buf
    }

    private func load(_ pack: SoundPack) {
        keys = (1...12).compactMap { buffer(pack, "key\($0)") }
        special = [:]
        for name in ["space", "enter", "backspace"] { special[name] = buffer(pack, name) }
        loaded = pack
    }

    // слушает все нажатия в окне приложения
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            // после обработки нажатия, чтобы выбор набора цифрой сразу звучал новым звуком
            if !e.isARepeat && Self.enabled { DispatchQueue.main.async { self?.play(e.keyCode) } }
            return e
        }
    }

    func play(_ keyCode: UInt16 = 0) {
        let pack = SoundPack.current
        if loaded != pack { load(pack) }
        let name = [49: "space", 36: "enter", 76: "enter", 51: "backspace"][Int(keyCode)]
        guard let buf = name.flatMap({ special[$0] }) ?? keys.randomElement(), !players.isEmpty else { return }
        if !engine.isRunning { try? engine.start() }
        let p = players[next]
        next = (next + 1) % players.count
        p.stop()
        p.scheduleBuffer(buf)
        p.play()
    }
}
