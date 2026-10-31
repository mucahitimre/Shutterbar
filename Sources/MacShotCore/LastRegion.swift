import CoreGraphics
import Foundation

/// The last successful region capture. Rect is display-local, top-left origin, points.
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

    /// Connected display info needed to make the decision.
    public struct Display: Equatable, Sendable {
        public var uuid: String
        public var pointSize: CGSize

        public init(uuid: String, pointSize: CGSize) {
            self.uuid = uuid
            self.pointSize = pointSize
        }
    }

    public enum Resolution: Equatable, Sendable {
        /// Display is connected and the rect is in bounds: can be cropped directly.
        case valid(Display)
        /// Display is not connected or the rect no longer fits: overlay + HUD.
        case invalid
    }

    /// R3.4: the UUID must match and the rect must fit the current display bounds.
    public func resolve(in displays: [Display]) -> Resolution {
        guard let display = displays.first(where: { $0.uuid == displayUUID }),
              CaptureGeometry.fits(rect, in: display.pointSize),
              !CaptureGeometry.isClick(rect)
        else { return .invalid }
        return .valid(display)
    }
}

/// JSON in UserDefaults. Only region captures write it; full-screen captures leave it alone (R3.1).
public struct LastRegionStore: Sendable {
    public static let key = "lastRegion"
    private let suiteName: String?

    /// - Parameter suiteName: separate UserDefaults for tests; `nil` = standard.
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
        /// Space / ~: does not change the last region.
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
