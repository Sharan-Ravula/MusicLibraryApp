import SwiftUI

/// A base SF Symbol with a small "+" badge in the bottom-right corner —
/// used for actions like "New Playlist" or "Add Songs" where no built-in
/// "symbol.badge.plus" variant exists for that particular base symbol.
struct BadgedIcon: View {
    let systemImage: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))

            // "plus.circle.fill" draws its own solid circle behind the plus,
            // which is what actually separates it from the base icon —
            // that's why the small offset alone wasn't enough before.
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .offset(x: 6, y: 6)
        }
        .frame(width: 22, height: 22)
    }
}
