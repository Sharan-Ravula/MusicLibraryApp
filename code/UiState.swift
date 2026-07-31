import SwiftUI
import Combine

@MainActor
final class UIState: ObservableObject {
    @Published var showQueue = false
}
