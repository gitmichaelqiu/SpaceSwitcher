import SwiftUI

// MARK: - Settings Components

struct SettingsRow<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content
    let helperText: LocalizedStringKey?
    let warningText: LocalizedStringKey?

    init(
        _ title: LocalizedStringKey, helperText: LocalizedStringKey? = nil,
        warningText: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helperText = helperText
        self.warningText = warningText
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                if let helperText = helperText {
                    HelperInfoButton(text: helperText)
                }

                if let warningText = warningText {
                    WarningInfoButton(text: warningText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey?
    let helperText: LocalizedStringKey?
    let content: Content

    init(
        _ title: LocalizedStringKey? = nil, helperText: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.helperText = helperText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = title {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    if let helperText = helperText {
                        HelperInfoButton(text: helperText)
                    }
                }
                .padding(.leading, 12)
            }

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    )
            )
        }
    }
}

private struct HelperInfoButton: View {
    let text: LocalizedStringKey
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            Text(text)
                .font(.system(size: 12))
                .padding(12)
                .frame(minWidth: 200, maxWidth: 300)
        }
    }
}

private struct WarningInfoButton: View {
    let text: LocalizedStringKey
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange.opacity(0.8))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            Text(text)
                .font(.system(size: 12))
                .padding(12)
                .frame(minWidth: 200, maxWidth: 300)
        }
    }
}

struct SliderSettingsRow<V>: View where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
    let title: LocalizedStringKey
    @Binding var value: V
    let range: ClosedRange<V>
    let defaultValue: V
    let step: V?
    let helperText: LocalizedStringKey?
    let warningText: LocalizedStringKey?
    let valueString: (V) -> String

    init(
        _ title: LocalizedStringKey,
        helperText: LocalizedStringKey? = nil,
        warningText: LocalizedStringKey? = nil,
        value: Binding<V>,
        range: ClosedRange<V>,
        defaultValue: V,
        step: V? = nil,
        valueString: @escaping (V) -> String = { String(format: "%.2f", Double($0)) }
    ) {
        self.title = title
        self.helperText = helperText
        self.warningText = warningText
        self._value = value
        self.range = range
        self.defaultValue = defaultValue
        self.step = step
        self.valueString = valueString
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13))
                    if let helperText = helperText {
                        HelperInfoButton(text: helperText)
                    }
                    if let warningText = warningText {
                        WarningInfoButton(text: warningText)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        value = defaultValue
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
                .disabled(value == defaultValue)
                .opacity(value == defaultValue ? 0 : 1)
            }

            HStack(spacing: 12) {
                if let step = step {
                    Slider(value: $value, in: range, step: V.Stride(step))
                } else {
                    Slider(value: $value, in: range)
                }

                Text(valueString(value))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }
}
