import CoreGraphics
import Foundation
import ShutterbarCore
import Testing

struct LastRegionTests {
    let region = LastRegion(
        displayUUID: "AAAA-1",
        rect: CGRect(x: 100, y: 50, width: 300, height: 200),
        displaySize: CGSize(width: 1512, height: 982),
        date: Date(timeIntervalSince1970: 1_800_000_000)
    )

    func makeStore() -> (LastRegionStore, String) {
        let suite = "LastRegionTests.\(UUID().uuidString)"
        return (LastRegionStore(suiteName: suite), suite)
    }

    @Test func encodeDecodeRoundTrip() throws {
        let data = try JSONEncoder().encode(region)
        #expect(try JSONDecoder().decode(LastRegion.self, from: data) == region)
    }

    @Test func storeSavesAndLoads() {
        let (store, suite) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(store.load() == nil)
        store.save(region)
        #expect(store.load() == region)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func fullScreenDoesNotUpdate() {
        let (store, suite) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        store.record(.region(region))
        store.record(.fullScreen)
        #expect(store.load() == region)
    }

    @Test func matchingUUIDIsValid() {
        let displays = [
            LastRegion.Display(uuid: "BBBB-2", pointSize: CGSize(width: 1920, height: 1080)),
            LastRegion.Display(uuid: "AAAA-1", pointSize: CGSize(width: 1512, height: 982)),
        ]
        #expect(region.resolve(in: displays) == .valid(displays[1]))
    }

    @Test func missingDisplayFallsBack() {
        let displays = [LastRegion.Display(uuid: "BBBB-2", pointSize: CGSize(width: 1920, height: 1080))]
        #expect(region.resolve(in: displays) == .invalid)
        #expect(region.resolve(in: []) == .invalid)
    }

    @Test func outOfBoundsFallsBack() {
        // Resolution shrank: the rect no longer fits.
        let displays = [LastRegion.Display(uuid: "AAAA-1", pointSize: CGSize(width: 350, height: 600))]
        #expect(region.resolve(in: displays) == .invalid)
    }

    @Test func corruptDataLoadsNil() {
        let suite = "LastRegionTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        UserDefaults(suiteName: suite)?.set(Data("x".utf8), forKey: LastRegionStore.key)
        #expect(LastRegionStore(suiteName: suite).load() == nil)
    }
}
