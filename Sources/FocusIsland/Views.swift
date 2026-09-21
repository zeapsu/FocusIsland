import SwiftUI
import FocusCore

struct SessionActions: View {
    @ObservedObject var model: SessionController
    var compact = false
    var body: some View {
        HStack(spacing: 10) {
            switch model.snapshot.state {
            case .idle:
                Button("Start Focus", action: model.startFocus).buttonStyle(.borderedProminent).accessibilityIdentifier("startFocus")
                Button("Start Break", action: model.startBreak).accessibilityIdentifier("startBreak")
            case .checkpointReached:
                Button("Continue Focus", action: model.continueFocus).buttonStyle(.borderedProminent).accessibilityIdentifier("continueFocus")
                Button("Start Break", action: model.startBreak)
            case .hardStopReached:
                Button("Start Break", action: model.startBreak).buttonStyle(.borderedProminent)
                Button("End Session", action: model.cancel)
            case .onBreak:
                Button("End Break", action: model.cancel)
            case .focusBeforeCheckpoint, .focusAfterCheckpoint:
                Button("Start Break", action: model.startBreak).buttonStyle(.borderedProminent)
                Button("Cancel Focus", action: model.cancel)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(compact ? .small : .regular)
    }
}

struct IslandView: View {
    @ObservedObject var model: SessionController
    @ObservedObject var island: IslandPresentation
    let openMenu: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var headerWidth: CGFloat {
        island.attachedToNotch ? island.notchWidth + island.leadingWing + island.trailingWing : 224
    }
    private var headerOffset: CGFloat {
        island.attachedToNotch ? (island.trailingWing - island.leadingWing) / 2 : 0
    }

    var body: some View {
        let palette = Palette.island(model.settings.theme, scheme: scheme, attached: island.attachedToNotch)
        let surface = Path(IslandGeometry.surfacePath(size: CGSize(width: island.canvasWidth, height: island.canvasHeight),
            headerWidth: headerWidth, headerHeight: island.headerHeight, headerOffset: headerOffset,
            expandedHeight: island.expandedHeight, attached: island.attachedToNotch, expansion: island.expansion))
        ZStack(alignment: .top) {
            // Only this mask morphs. Text and controls retain their final layout throughout.
            palette.background.allowsHitTesting(false)

            header(palette: palette)
                .frame(width: headerWidth + (island.expandedWidth - headerWidth) * island.expansion, height: island.headerHeight)
                .position(x: island.canvasWidth / 2 + headerOffset * (1 - island.expansion), y: island.headerHeight / 2)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("island-summary")

            VStack(alignment: .leading, spacing: 8) {
                Text(model.title).font(.system(size: 15, weight: .semibold))
                Text(model.detail).font(.system(size: 12)).foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if model.snapshot.state != .idle {
                    ProgressView(value: model.progress).tint(palette.accent)
                        .frame(height: 4).clipped().accessibilityLabel("Session progress")
                }
                SessionActions(model: model, compact: true).padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(width: island.expandedWidth, height: island.expandedHeight - island.headerHeight, alignment: .topLeading)
            .foregroundStyle(palette.text)
            .offset(y: island.headerHeight)
            .opacity(min(1, max(0, (island.expansion - 0.5) * 2)))
            .allowsHitTesting(island.expansion >= 0.99)
            .accessibilityHidden(island.expansion < 0.99)
            .accessibilityIdentifier("island-controls")
        }
        .frame(width: island.canvasWidth, height: island.canvasHeight, alignment: .top)
        .mask(surface)
        .tint(palette.accent)
        .preferredColorScheme(model.settings.theme.colorScheme)
        .environment(\.colorScheme, island.attachedToNotch && model.settings.theme == .system ? .dark : model.settings.theme.colorScheme ?? scheme)
        .ignoresSafeArea()
    }

    @ViewBuilder private func header(palette: Palette) -> some View {
        if island.attachedToNotch {
            let expandedWing = (island.expandedWidth - island.notchWidth) / 2
            let leading = island.leadingWing + (expandedWing - island.leadingWing) * island.expansion
            let trailing = island.trailingWing + (expandedWing - island.trailingWing) * island.expansion
            HStack(spacing: 0) {
                Group {
                    if model.clockText.isEmpty {
                        Image(systemName: model.icon).foregroundStyle(palette.accent)
                    } else {
                        Text(model.clockText).font(.system(size: 12, weight: .semibold, design: .monospaced)).monospacedDigit()
                    }
                }.frame(width: leading)
                    .accessibilityLabel("\(model.title), \(model.clockText)")
                Color.clear.frame(width: island.notchWidth)
                Button(action: openMenu) {
                    HStack(spacing: 4) {
                        Image(systemName: model.snapshot.state == .idle ? "play.fill" : model.icon)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                            .frame(width: 8 * island.expansion).opacity(island.expansion)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(model.snapshot.state == .hardStopReached ? palette.warning : palette.accent)
                    .frame(width: trailing, height: island.headerHeight)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Open timer menu").accessibilityIdentifier("islandMenu")
            }.foregroundStyle(palette.text)
        } else {
            HStack(spacing: 8) {
                Image(systemName: model.icon).foregroundStyle(palette.accent)
                Text(model.title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                Text(model.clockText).font(.system(size: 12, weight: .semibold, design: .monospaced)).monospacedDigit()
            }.padding(.horizontal, 14).foregroundStyle(palette.text)
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var model: SessionController
    let openSettings: () -> Void
    let quit: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = Palette.resolve(model.settings.theme, scheme: scheme)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Focus Island", systemImage: model.icon).font(.headline)
                Spacer()
                Text(model.clockText).font(.system(.body, design: .monospaced)).monospacedDigit()
            }
            Text(model.title).font(.title3.weight(.semibold))
            Text(model.detail).font(.callout).foregroundStyle(palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            if model.snapshot.state != .idle { ProgressView(value: model.progress).accessibilityLabel("Session progress") }
            SessionActions(model: model)
            if model.snapshot.state == .checkpointReached {
                Button("End Session", action: model.cancel).buttonStyle(.plain).font(.callout)
            }
            Divider()
            HStack {
                Button("Settings…", action: openSettings).keyboardShortcut(",")
                    .accessibilityIdentifier("openSettings")
                Spacer()
                Button("Quit", action: quit).keyboardShortcut("q")
            }.buttonStyle(.borderless)
        }
        .padding(20).frame(width: 340)
        .foregroundStyle(palette.text).tint(palette.accent).background(palette.background)
        .preferredColorScheme(model.settings.theme.colorScheme)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SessionController
    @ObservedObject var notifications: NotificationManager
    @State private var checkpoint: String
    @State private var hardStop: String
    @State private var breakTime: String
    @State private var saved = false
    @Environment(\.colorScheme) private var scheme

    init(model: SessionController) {
        self.model = model
        notifications = model.notifications
        _checkpoint = State(initialValue: String(model.settings.checkpointMinutes))
        _hardStop = State(initialValue: String(model.settings.hardStopMinutes))
        _breakTime = State(initialValue: String(model.settings.breakMinutes))
    }
    private var draft: TimerSettings? {
        guard let checkpoint = Int(checkpoint), let hardStop = Int(hardStop), let breakTime = Int(breakTime) else { return nil }
        return TimerSettings(checkpointMinutes: checkpoint, hardStopMinutes: hardStop, breakMinutes: breakTime, theme: model.settings.theme)
    }
    private var error: String? { draft?.validationError ?? (draft == nil ? "Enter whole minutes in all three fields." : nil) }

    var body: some View {
        let palette = Palette.resolve(model.settings.theme, scheme: scheme)
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Make room for focus.").font(.title2.weight(.semibold))
                Text("A gentle checkpoint, then a clear time to move.").foregroundStyle(palette.secondaryText)
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                durationRow("Checkpoint", value: $checkpoint, hint: "1–239 minutes")
                durationRow("Hard stop", value: $hardStop, hint: "2–240 minutes")
                durationRow("Break", value: $breakTime, hint: "1–120 minutes")
            }
            HStack {
                Text(error ?? (saved ? "Saved. Active deadlines stay unchanged." : "Focus times apply to the next focus. Break time applies when you start a break."))
                    .font(.caption).foregroundStyle(error == nil ? palette.secondaryText : palette.warning)
                    .accessibilityIdentifier("settings-validation")
                Spacer()
                Button("Save Durations") {
                    if let draft, draft.validationError == nil { model.saveSettings(draft); saved = true }
                }.buttonStyle(.borderedProminent).disabled(error != nil)
            }
            Divider()
            Picker("Theme", selection: Binding(get: { model.settings.theme }, set: { theme in
                var next = model.settings; next.theme = theme; model.saveSettings(next)
            })) {
                ForEach(ThemePreference.allCases, id: \.self) { theme in Text(theme.displayName).tag(theme) }
            }.pickerStyle(.segmented).accessibilityLabel("Theme").accessibilityIdentifier("themePicker")
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Reminders").font(.headline)
                Text(notifications.permissionText).font(.callout).foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("notificationStatus")
                Button(notifications.permissionButtonTitle, action: notifications.handlePermissionAction)
                    .disabled(notifications.isRequestingPermission || notifications.authorizationStatus == nil)
                    .accessibilityIdentifier("notificationPermission")
            }
            if model.isQA { Text("QA mode · 20× timer speed · separate preferences").font(.caption).foregroundStyle(palette.secondaryText) }
        }
        .padding(26).frame(width: 500)
        .foregroundStyle(palette.text).tint(palette.accent).background(palette.background)
        .preferredColorScheme(model.settings.theme.colorScheme)
        .onChange(of: checkpoint) { _, _ in saved = false }
        .onChange(of: hardStop) { _, _ in saved = false }
        .onChange(of: breakTime) { _, _ in saved = false }
    }
    @ViewBuilder private func durationRow(_ label: String, value: Binding<String>, hint: String) -> some View {
        GridRow {
            Text(label)
            TextField(label, text: value).textFieldStyle(.roundedBorder).frame(width: 64).accessibilityLabel(label + " minutes")
            Text(hint).font(.caption).foregroundStyle(Palette.resolve(model.settings.theme, scheme: scheme).secondaryText)
        }
    }
}
