@testable import PushNotification
import Testing

struct ValidateDeviceNameTests {
    @Test func lettersDigitsUnderscoreHyphenAndSpacesAreAccepted() throws {
        try validateDeviceName("Dani_s Pixel-7")
    }

    @Test func exactlyTheMinimumLengthIsAccepted() throws {
        try validateDeviceName("a")
    }

    @Test func exactlyTheMaximumLengthIsAccepted() throws {
        try validateDeviceName(String(repeating: "a", count: 64))
    }

    @Test func allWhitespaceIsRefused() {
        #expect(throws: PushNotificationError.self) {
            try validateDeviceName("  ")
        }
    }

    @Test func longerThanTheMaximumLengthIsRefused() {
        #expect(throws: PushNotificationError.self) {
            try validateDeviceName(String(repeating: "a", count: 65))
        }
    }

    @Test func emptyIsRefusedShorterThanTheMinimumLength() {
        #expect(throws: PushNotificationError.self) {
            try validateDeviceName("")
        }
    }

    @Test func surroundingWhitespaceIsNotCounted() throws {
        try validateDeviceName("  " + String(repeating: "a", count: 64) + "\n")
    }

    @Test func emojiCountOnceEach() throws {
        try validateDeviceName(String(repeating: "📱", count: 64))
        #expect(throws: PushNotificationError.self) {
            try validateDeviceName(String(repeating: "📱", count: 65))
        }
    }

    @Test func aLineBreakInsideTheNameIsAccepted() throws {
        try validateDeviceName("Pixel\n7")
    }

    @Test func acceptsSpecialCharacters() throws {
        try validateDeviceName("Someone's Pixel")
        try validateDeviceName("Pixel #7")
        try validateDeviceName("📱 Pixel")
    }
}
