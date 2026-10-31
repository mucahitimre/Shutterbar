import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import MacShotCore

extension KeyboardShortcuts.Name {
    // Name değişmez bir değer tipi; KeyboardShortcuts Sendable işaretlemiyor.
    nonisolated(unsafe) static let captureRegion = Self("captureRegion", default: .init(.x, modifiers: [.command, .shift]))
    nonisolated(unsafe) static let captureLastRegion = Self("captureLastRegion", default: .init(.five, modifiers: [.option, .shift]))
}

enum HotkeyAction: CaseIterable, Hashable {
    case region
    case lastRegion

    var name: KeyboardShortcuts.Name {
        switch self {
        case .region: .captureRegion
        case .lastRegion: .captureLastRegion
        }
    }

    /// Kayıt başarısız olursa önerilen, her macOS sürümünde çalışan kısayol.
    var fallback: KeyboardShortcuts.Shortcut {
        switch self {
        case .region: .init(.four, modifiers: [.control, .shift])
        case .lastRegion: .init(.five, modifiers: [.control, .shift])
        }
    }

    var title: String {
        switch self {
        case .region: "Capture region"
        case .lastRegion: "Capture last region"
        }
    }
}

@MainActor
final class HotkeyManager: ObservableObject {
    /// Sistemde kaydı başarısız olan kısayollar.
    @Published private(set) var failures: Set<HotkeyAction> = []

    private let onTrigger: (HotkeyAction) -> Void
    private var observer: NSObjectProtocol?

    init(onTrigger: @escaping (HotkeyAction) -> Void) {
        self.onTrigger = onTrigger
    }

    func start() {
        for action in HotkeyAction.allCases {
            KeyboardShortcuts.onKeyDown(for: action.name) { [weak self] in
                self?.onTrigger(action)
            }
        }
        // KeyboardShortcuts bu bildirimi public yapmıyor; adı kaynak koddan.
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.verify() }
        }
        verify()
    }

    func verify() {
        var failed: Set<HotkeyAction> = []
        for action in HotkeyAction.allCases {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: action.name) else { continue }
            let status = HotkeyProbe.register(shortcut)
            if !HotkeyRegistration.isUsable(status: status) {
                Log.hotkey.error("Kısayol kaydedilemedi: \(action.title, privacy: .public) \(shortcut.description, privacy: .public) status=\(status)")
                failed.insert(action)
            }
        }
        failures = failed
    }

    func useFallback(for action: HotkeyAction) {
        KeyboardShortcuts.setShortcut(action.fallback, for: action.name)
        verify()
    }
}

enum HotkeyProbe {
    private static let signature: OSType = 0x4D53_5052 // 'MSPR'

    /// Kombinasyonu geçici olarak kaydedip geri alır; Carbon durum kodunu döndürür.
    static func register(_ shortcut: KeyboardShortcuts.Shortcut) -> Int32 {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.carbonKeyCode),
            UInt32(shortcut.carbonModifiers),
            EventHotKeyID(signature: signature, id: 1),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            UnregisterEventHotKey(ref)
        }
        return status
    }
}
