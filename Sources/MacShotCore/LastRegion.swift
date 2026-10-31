import CoreGraphics
import Foundation

/// Son başarılı region capture. Rect display-local, sol-üst orijinli, point.
public struct LastRegion: Codable, Equatable, Sendable {
    public var displayUUID: String
    public var rect: CGRect
    public var displaySize: CGSize
    public var date: Date

    public init(displayUUID: String, rect: CGRect, displaySize: CGSize, date: Date) {
        self.displayUUID = displayUUID
        self.rect = rect
        self.displaySize = displaySize
        self.date = date
    }

    /// Kararı verirken bilinmesi gereken bağlı ekran bilgisi.
    public struct Display: Equatable, Sendable {
        public var uuid: String
        public var pointSize: CGSize

        public init(uuid: String, pointSize: CGSize) {
            self.uuid = uuid
            self.pointSize = pointSize
        }
    }

    public enum Resolution: Equatable, Sendable {
        /// Ekran bağlı ve rect sınır içinde: doğrudan kesilebilir.
        case valid(Display)
        /// Ekran bağlı değil ya da rect artık sığmıyor: overlay + HUD.
        case invalid
    }

    /// R3.4: UUID eşleşmeli, rect güncel ekran sınırına sığmalı.
    public func resolve(in displays: [Display]) -> Resolution {
        guard let display = displays.first(where: { $0.uuid == displayUUID }),
              CaptureGeometry.fits(rect, in: display.pointSize),
              !CaptureGeometry.isClick(rect)
        else { return .invalid }
        return .valid(display)
    }
}

/// UserDefaults içinde JSON. Yalnız region capture yazar; tam ekran capture'lar dokunmaz (R3.1).
public struct LastRegionStore: Sendable {
    public static let key = "lastRegion"
    private let suiteName: String?

    /// - Parameter suiteName: testler için ayrı UserDefaults; `nil` = standard.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load() -> LastRegion? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(LastRegion.self, from: data)
    }

    public enum CaptureKind: Sendable {
        case region(LastRegion)
        /// Space / ~: last region'ı değiştirmez.
        case fullScreen
    }

    public func record(_ kind: CaptureKind) {
        if case .region(let region) = kind {
            save(region)
        }
    }

    public func save(_ region: LastRegion) {
        guard let data = try? JSONEncoder().encode(region) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
