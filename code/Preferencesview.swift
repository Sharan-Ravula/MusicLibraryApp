import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var settings: AppSettings

    private let columns = [GridItem(.adaptive(minimum: 70), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Theme")
                .appHeadlineFont()

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(theme.color)
                            .frame(width: 32, height: 32)
                            .overlay {
                                if settings.theme == theme {
                                    Circle()
                                        .stroke(Color.primary, lineWidth: 2)
                                        .padding(-3)
                                }
                            }
                        Text(theme.rawValue)
                            .appCaption2Font()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settings.theme = theme
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
