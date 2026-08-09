import SwiftUI
import Combine

@MainActor
final class UIState: ObservableObject {
    @Published var showQueue = false
    /// True while a text field (e.g. the song search box) has keyboard
    /// focus. The app's global Play/Pause (Space) and Next/Previous
    /// (⌘←/⌘→) shortcuts are disabled while this is true, since those are
    /// also standard text-editing keys (typing a space, moving the cursor)
    /// and would otherwise hijack input meant for the field.
    @Published var isTextInputActive = false
}
