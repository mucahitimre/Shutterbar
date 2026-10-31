import Foundation

/// `<kök>/yyyy-MM/Screenshot_yyyy-MM-dd_HH-mm-ss.png`; çakışmada `_2`, `_3`, … eki.
public struct FileNamer: Sendable {
    public var timeZone: TimeZone
    public var prefix: String

    public init(timeZone: TimeZone = .current, prefix: String = "Screenshot") {
        self.timeZone = timeZone
        self.prefix = prefix
    }

    public func folderName(for date: Date) -> String {
        format(date, "yyyy-MM")
    }

    public func baseName(for date: Date) -> String {
        "\(prefix)_\(format(date, "yyyy-MM-dd_HH-mm-ss"))"
    }

    public func fileURL(in root: URL, date: Date, fileExists: (URL) -> Bool) -> URL {
        let folder = root.appendingPathComponent(folderName(for: date), isDirectory: true)
        let base = baseName(for: date)
        var candidate = folder.appendingPathComponent("\(base).png")
        var index = 2
        while fileExists(candidate) {
            candidate = folder.appendingPathComponent("\(base)_\(index).png")
            index += 1
        }
        return candidate
    }

    private func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
