import SwiftUI

struct SettingsRow<Content: View>: View {
    let title: LocalizedStringKey?
    let helperText: LocalizedStringKey?
    let content: Content

    init(_ title: LocalizedStringKey?, helperText: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.helperText = helperText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if let _title = title {
                    Text(_title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
                
                content
                    .frame(alignment: .trailing)
            }
            
            if let _helper = helperText {
                Text(_helper)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
    }
}

struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    let helperText: LocalizedStringKey?
    let content: Content

    init(_ title: LocalizedStringKey, helperText: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.helperText = helperText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .padding(.leading, 4)
                
                if let _helper = helperText {
                    Text(_helper)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.regularMaterial) // blur overlay
                    )
            )
        }
    }

    private var backgroundColor: Color {
        let nsColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.20, alpha: 1.0)
            } else {
                return NSColor(calibratedWhite: 1.00, alpha: 1.0)
            }
        }
        return Color(nsColor: nsColor)
    }
}
