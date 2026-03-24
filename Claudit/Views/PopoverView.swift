import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PopoverView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0
    @State private var contentHeight: CGFloat = 0

    private var appDelegate: AppDelegate {
        AppDelegate.shared
    }

    private var maxHeight: CGFloat {
        guard let screen = NSScreen.main else { return 500 }
        return screen.visibleFrame.height - 16
    }

    private var popoverHeight: CGFloat {
        if contentHeight <= 0 { return 380 }
        return min(contentHeight, maxHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if appState.profileManager.hasMultipleProfiles {
                    ProfilePopoverPicker()
                }
                Picker("View", selection: $selectedTab) {
                    Text("Usage").tag(0)
                    Text("Quota").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 16)

            ScrollView(.vertical) {
                Group {
                    switch selectedTab {
                    case 0:
                        UsageView()
                    case 1:
                        QuotaView()
                    default:
                        EmptyView()
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)

            Divider()
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                if let status = appState.claudeStatus {
                    Circle()
                        .fill(status.indicator.color)
                        .frame(width: 6, height: 6)
                        .help(status.description)
                        .onTapGesture {
                            if let url = URL(string: "https://status.anthropic.com") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                }
                if let rate = appState.burnRate {
                    Text("~\(ClauditFormatter.costDetail(rate))/day")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let lastUpdate = appState.lastUsageUpdate {
                    Text(lastUpdate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if !appDelegate.isPopoverDetached {
                    Button {
                        appDelegate.detachPopover()
                    } label: {
                        Image(systemName: "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Detach as floating window")
                }
                Button {
                    appDelegate.showDashboard()
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dashboard")
                Button {
                    appState.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")

                Button {
                    appDelegate.showSettings()
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit Claudit")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 300, height: popoverHeight)
        .background(
            // Mirror the main layout without ScrollView to measure true content height
            VStack(spacing: 0) {
                HStack {
                    if appState.profileManager.hasMultipleProfiles {
                        Text("P")
                            .font(.caption)
                            .hidden()
                    }
                    Picker("", selection: .constant(selectedTab)) {
                        Text("Usage").tag(0)
                        Text("Quota").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider().padding(.horizontal, 16)

                Group {
                    switch selectedTab {
                    case 0: UsageView()
                    case 1: QuotaView()
                    default: EmptyView()
                    }
                }

                Divider().padding(.horizontal, 16)

                HStack(spacing: 12) {
                    Text(" ").font(.caption2)
                    Spacer()
                    ForEach(0..<4, id: \.self) { _ in
                        Image(systemName: "circle")
                            .font(.system(size: 11))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(width: 300)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                }
            )
        )
        .onPreferenceChange(ContentHeightKey.self) { measuredHeight in
            guard measuredHeight > 0 else { return }
            contentHeight = measuredHeight
            let height = min(measuredHeight, maxHeight)
            DispatchQueue.main.async {
                (AppDelegate.shared)?.popover?.contentSize = NSSize(width: 300, height: height)
            }
        }
    }
}
