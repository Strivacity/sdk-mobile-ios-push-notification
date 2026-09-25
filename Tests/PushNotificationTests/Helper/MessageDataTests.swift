@testable import PushNotification
import Testing

/// Exercises `MessageData.from(userInfo:)`.
struct MessageDataTests {
    @Test func fromReturnsASingleEntryDictionaryWhenUserInfoCarriesThePushKey() {
        let userInfo: [AnyHashable: Any] = [PushEnvelope.key: "envelope-json"]

        #expect(MessageData.from(userInfo: userInfo) == [PushEnvelope.key: "envelope-json"])
    }

    @Test func fromReturnsNilWhenThereIsNoUserInfoAtAll() {
        #expect(MessageData.from(userInfo: [:]) == nil)
    }

    @Test func fromReturnsNilWhenUserInfoExistsButThePushKeyIsAbsent() {
        let userInfo: [AnyHashable: Any] = ["some.other.key": "value"]

        #expect(MessageData.from(userInfo: userInfo) == nil)
    }

    @Test func fromExcludesOtherUnrelatedEntriesFromTheReturnedDictionary() {
        let userInfo: [AnyHashable: Any] = [
            PushEnvelope.key: "envelope-json",
            "gcm.n.e": "1",
            "collapse_key": "do_not_collapse",
        ]

        #expect(MessageData.from(userInfo: userInfo) == [PushEnvelope.key: "envelope-json"])
    }
}
