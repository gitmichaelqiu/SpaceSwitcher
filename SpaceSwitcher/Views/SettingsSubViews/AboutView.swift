import SwiftUI
import AppKit

struct AboutView: View {
    var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "SpaceSwitcher"
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var currentYear: String {
        let year = Calendar.current.component(.year, from: Date())
        return String(year)
    }
    
    // Placeholder text following OptClicker's pattern (replace with actual localized string/description)
    var descriptionPlaceholder: String {
        "SpaceSwitcher is a macOS utility that automatically show/hide/minize apps when switching to a specific desktop."
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                if let nsImage = NSApplication.shared.applicationIconImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: min(geometry.size.width * 0.6, 160),
                            height: min(geometry.size.width * 0.6, 160)
                        )
                        .padding(.bottom, 8)
                }

                VStack(spacing: 4) {
                    Text(appName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("v\(appVersion)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Divider()
                    .padding(.vertical, 8)
                
                Text(descriptionPlaceholder)
                    .multilineTextAlignment(.center)
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        maxWidth: min(geometry.size.width * 0.8, 480),
                        alignment: .center
                    )

                Spacer()

                VStack(spacing: 8) {
                    // Update the destination URL
                    Link("GitHub Repository",
                         destination: URL(string: "https://github.com/gitmichaelqiu/SpaceSwitcher")!)
                    .font(.body)
                    .foregroundColor(.blue)

                    Text("© \(currentYear) Michael Y. Qiu")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, max(16, geometry.size.width * 0.05))
            }
            .padding(.horizontal, max(24, geometry.size.width * 0.08))
            .padding(.vertical, max(24, geometry.size.height * 0.05))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
