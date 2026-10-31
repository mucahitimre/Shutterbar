import Foundation
import MacShotCore
import Testing

struct FileNamerTests {
    let istanbul = TimeZone(identifier: "Europe/Istanbul")!
    let root = URL(fileURLWithPath: "/tmp/shots", isDirectory: true)

    func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test func nameAndFolderUseLocalTime24h() {
        let namer = FileNamer(timeZone: istanbul)
        let d = date("2026-10-31T13:05:09Z") // Istanbul UTC+3 → 16:05:09
        let url = namer.fileURL(in: root, date: d) { _ in false }
        #expect(url.path == "/tmp/shots/2026-10/Screenshot_2026-10-31_16-05-09.png")
    }

    @Test func collisionAddsSuffix() {
        let namer = FileNamer(timeZone: istanbul)
        let d = date("2026-10-31T13:05:09Z")
        let taken: Set<String> = [
            "/tmp/shots/2026-10/Screenshot_2026-10-31_16-05-09.png",
            "/tmp/shots/2026-10/Screenshot_2026-10-31_16-05-09_2.png",
        ]
        let url = namer.fileURL(in: root, date: d) { taken.contains($0.path) }
        #expect(url.lastPathComponent == "Screenshot_2026-10-31_16-05-09_3.png")
    }

    @Test func monthAndYearBoundaryFollowsTimeZone() {
        let namer = FileNamer(timeZone: istanbul)
        // Still 2026 in UTC, 2027-01-01 01:30 in Istanbul
        let d = date("2026-12-31T22:30:00Z")
        #expect(namer.folderName(for: d) == "2027-01")
        #expect(namer.baseName(for: d) == "Screenshot_2027-01-01_01-30-00")
        let utc = FileNamer(timeZone: TimeZone(identifier: "UTC")!)
        #expect(utc.folderName(for: d) == "2026-12")
    }
}
