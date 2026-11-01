import ServiceManagement
import SwiftUI

/// The popover shown when clicking the menu bar item, modelled on
/// claude.ai's Settings → Usage page.
struct UsagePanel: View {
    let store: UsageStore
    @AppStorage("menuBarDisplay") private var display: MenuBarDisplay = .session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)

            if let usage = store.usage {
                Text(Formatting.paceSummary(for: usage))
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                Divider()

                limits(usage)
                    .padding(.vertical, 4)
            } else if store.error == nil {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }

            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            }

            Divider()

            footer
                .padding(.top, 10)
        }
        .padding(16)
        .frame(width: 440)
        .onAppear { store.refresh(ifOlderThan: 15) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Your usage")
                .font(.system(size: 14, weight: .semibold))
            if let plan = Formatting.planName(store.plan) {
                Text(plan)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                    .animation(
                        store.isLoading ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                        value: store.isLoading)
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .disabled(store.isLoading)
        }
    }

    @ViewBuilder
    private func limits(_ usage: UsageResponse) -> some View {
        if let session = usage.fiveHour {
            LimitRow(title: "Current session", window: session)
        }
        if let week = usage.sevenDay {
            LimitRow(title: "This week", window: week)
        }
        if let opus = usage.sevenDayOpus {
            LimitRow(title: "This week · Opus", window: opus)
        }
        if let sonnet = usage.sevenDaySonnet {
            LimitRow(title: "This week · Sonnet", window: sonnet)
        }
        if let extra = usage.extraUsage, extra.isEnabled, let utilization = extra.utilization {
            LimitRow(title: "Extra usage", subtitle: "Monthly spend limit", percent: utilization)
        }
    }

    private var footer: some View {
        HStack {
            if let lastUpdated = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text("Updated \(Self.relative(lastUpdated, now: context.date))")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Picker("Show in menu bar", selection: $display) {
                    ForEach(MenuBarDisplay.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                LaunchAtLoginToggle()
                Divider()
                Button("Open usage on claude.ai") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                }
                Divider()
                Button("Quit Claude Usage") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private static func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 30 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

private struct LimitRow: View {
    let title: String
    let subtitle: String?
    let percent: Double

    init(title: String, window: UsageWindow) {
        self.init(title: title, subtitle: Formatting.resetDescription(window.resetsAt), percent: window.utilization)
    }

    init(title: String, subtitle: String?, percent: Double) {
        self.title = title
        self.subtitle = subtitle
        self.percent = percent
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, alignment: .leading)

            UsageBar(fraction: percent / 100)
                .frame(height: 5)

            Text("\(Formatting.percent(percent)) used")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct UsageBar: View {
    let fraction: Double

    private var tint: Color {
        switch fraction {
        case ..<0.8: Color(red: 0.16, green: 0.47, blue: 0.85)
        case ..<0.95: .orange
        default: .red
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { isEnabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Launch at login change failed: \(error)")
                }
                isEnabled = SMAppService.mainApp.status == .enabled
            }
        ))
    }
}
