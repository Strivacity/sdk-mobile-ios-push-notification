import Foundation

extension String {
    /// Empty, or whitespace-only.
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
