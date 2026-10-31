import MacShotCore
import Testing

struct HotkeyRegistrationTests {
    @Test func successAndAlreadyRegisteredAreUsable() {
        #expect(HotkeyRegistration.isUsable(status: 0))
        #expect(HotkeyRegistration.isUsable(status: HotkeyRegistration.alreadyRegistered))
    }

    @Test func sequoiaRestrictionIsNotUsable() {
        #expect(!HotkeyRegistration.isUsable(status: HotkeyRegistration.sequoiaOptionRestriction))
        #expect(!HotkeyRegistration.isUsable(status: -50))
    }
}
