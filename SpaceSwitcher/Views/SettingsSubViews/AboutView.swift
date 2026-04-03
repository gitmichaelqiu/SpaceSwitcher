import SwiftUI

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

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // MARK: - App Header
                VStack(spacing: 16) {
                    if let nsImage = NSApplication.shared.applicationIconImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 128, height: 128)
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
                    }

                    VStack(spacing: 6) {
                        Text(appName)
                            .font(.system(size: 32, weight: .bold))
                            .tracking(-0.5)

                        Text("Version \(appVersion)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 40)

                Text("A powerful companion for macOS Desktops, allowing you to automate app visibility and dock configurations across different spaces.")
                    .font(.system(size: 14))
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary.opacity(0.8))
                    .padding(.horizontal, 40)
                    .frame(maxWidth: 540)

                Divider()
                    .padding(.horizontal, 60)
                    .opacity(0.5)

                // MARK: - More Apps Section
                VStack(spacing: 24) {
                    Text("Related Projects")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    HStack(alignment: .top, spacing: 24) {
                        // DesktopRenamer
                        OtherAppCard(
                            imageName: "DesktopRenamerIcon",
                            appName: "DesktopRenamer",
                            description: "The core API for renaming and managing spaces on macOS.",
                            url: "https://github.com/gitmichaelqiu/DesktopRenamer"
                        )
                        
                        // OptClicker
                        OtherAppCard(
                            imageName: "OptClickerIcon",
                            appName: "OptClicker",
                            description: "Enhance your workflow with Option-key based right-clicking.",
                            url: "https://github.com/gitmichaelqiu/OptClicker"
                        )
                    }
                    .padding(.horizontal)
                }

                Divider()
                    .padding(.horizontal, 60)
                    .opacity(0.5)

                // MARK: - Footer
                VStack(spacing: 12) {
                    Link(destination: URL(string: "https://github.com/gitmichaelqiu/SpaceSwitcher")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("GitHub Repository")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 4) {
                        Text("Made with ❤️ by Michael Yicheng Qiu")
                            .font(.system(size: 12, weight: .medium))
                        Text("© \(currentYear) Michael Yicheng Qiu. All rights reserved.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct OtherAppCard: View {
    let imageName: String
    let appName: String
    let description: String
    let url: String
    
    @State private var isHovering = false
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.03))
                        .frame(width: 64, height: 64)
                    
                    if let nsImage = NSImage(named: imageName) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                
                // Text Content
                VStack(spacing: 4) {
                    Text(appName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(height: 44, alignment: .top)
                }
            }
            .padding(16)
            .frame(width: 170)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(isHovering ? 0.6 : 0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isHovering ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.05), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 8 : 4, x: 0, y: 2)
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
