import AppKit
import SwiftUI
import TrackerCore

@main
struct APPICHoursApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("APPIC Hours", id: "main") {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1280, height: 860)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            Image(systemName: "clock.badge.checkmark")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared?.backupOnQuit() }
    }
}

struct AppCommands: Commands {
    var model: AppModel
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { i, item in
                Button(item.title) { model.section = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
            Divider()
        }
        CommandMenu("Session") {
            ForEach(Array(HourCategory.allCases.enumerated()), id: \.element) { i, c in
                Button("New \(c.label)") {
                    model.section = .log
                    model.logDraft.category = c
                }
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
            }
            Divider()
            Button("Batch Add Sessions…") { model.batchSessions = WhoRef(who: model.logDraft.who) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Client…") { model.section = .clients; model.showNewClient = true }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Batch Add Clients…") { model.showBatchClients = true }
            Button("New Recurring Session…") { model.section = .recurring; model.showNewSlot = true }
            Divider()
            Button("Weekly Recap…") { model.showRecap() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Export to Excel…") { model.section = .summary; model.exportRequest += 1 }
                .keyboardShortcut("e", modifiers: .command)
        }
    }
}

// MARK: - Root

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isReady {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                } detail: {
                    switch model.section ?? .log {
                    case .log: LogView()
                    case .sessions: SessionsView()
                    case .clients: ClientsView()
                    case .supervisors: SupervisorsView()
                    case .calendar: CalendarView()
                    case .recurring: RecurringView()
                    case .summary: SummaryView()
                    case .setup: SetupView()
                    }
                }
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 1080, minHeight: 700)
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 22) }
        .sheet(item: $model.editing) { ref in EditEntrySheet(id: ref.id) }
        .sheet(item: $model.bulkEdit) { ref in BulkEditSheet(ids: ref.ids) }
        .sheet(item: Binding(get: { model.pendingSupervision.map(EditRef.init) },
                             set: { model.pendingSupervision = $0?.id })) { ref in NewSupervisionSheet(supervisorId: ref.id) }
        .sheet(item: $model.batchSessions) { ref in BatchSessionsSheet(preset: ref.who, supervisorId: ref.supervisorId) }
        .sheet(isPresented: $model.showBatchClients) { BatchClientsSheet() }
        .sheet(item: $model.recap, onDismiss: { model.recapDismissed() }) { ref in RecapSheet(friday: ref.id) }
        .onAppear { model.checkRecap() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkRecap()
        }
        .alert("Couldn't save", isPresented: Binding(get: { model.alert != nil },
                                                     set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert ?? "")
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    // Rows are plain buttons: List(selection:) in this NavigationSplitView mapped clicks
    // to a nil selection, so the page never changed.
    var body: some View {
        List {
            Section("Track") {
                row(.log, badge: model.toConfirmCount)
                row(.sessions)
                row(.clients, badge: model.openClients.count + model.openGroups.count)
                row(.supervisors)
                row(.calendar)
                row(.recurring)
            }
            Section("Report") { row(.summary) }
            Section("App") { row(.setup) }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { totals.padding(12) }
    }

    private func row(_ item: SidebarItem, badge: Int = 0) -> some View {
        let selected = (model.section ?? .log) == item
        return Button { model.section = item } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)
                Text(item.title)
                    .fontWeight(selected ? .semibold : .regular)
                Spacer(minLength: 4)
                if badge > 0 {
                    Text("\(badge)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var totals: some View {
        let direct = model.recentDirectMinutes
        return VStack(alignment: .leading, spacing: 6) {
            Text("DIRECT CONTACT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            HoursTicker(minutes: direct, showDelta: true)
            HStack(spacing: 0) {
                Text(hoursText(model.totalMinutes)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(model.totalMinutes)))
                    .animation(.spring(response: 0.8, dampingFraction: 0.82), value: model.totalMinutes)
                Text(" h total logged")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))   // Liquid Glass card in the glass sidebar
    }
}

extension AppModel {
    /// Intervention + assessment minutes, all time.
    var recentDirectMinutes: Int {
        guard let r = repo else { return 0 }
        _ = revision
        let v = try? r.db.scalar("SELECT COALESCE(SUM(minutes),0) FROM entry WHERE planned = 0 AND category IN ('intervention','assessment')")
        return (v as? Int) ?? 0
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let t = model.toast {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                Text(t.message).lineLimit(1)
                if t.canUndo {
                    Button("Undo") { model.undoToast() }.buttonStyle(.bordered).controlSize(.small)
                }
                Button { withAnimation { model.toast = nil } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .glassEffect(in: .capsule)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(t.id)
        }
    }
}

// MARK: - First run

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var path = AppConfig.defaultDataDir.path
    @State private var error: String?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            AppIconView(size: 96)
            VStack(spacing: 8) {
                Text("Welcome to APPIC Hours").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Log practicum hours in seconds. Get AAPI-ready totals any time.")
                    .font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("bolt.fill", .yellow, "Fast logging", "Pick a client, tap a duration, press Return.")
                feature("repeat", .blue, "Recurring sessions", "Confirm your weekly clients with one click.")
                feature("chart.bar.xaxis", .purple, "AAPI summary & Excel export", "Every category, as of any date.")
                feature("lock.fill", .green, "Private by design", "Your data stays in a folder you choose — never inside the app.")
            }
            .frame(width: 460)
            VStack(alignment: .leading, spacing: 8) {
                Text("Where should your data live?").font(.headline)
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                    Text(path).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…", action: choose)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                Text("Holds the database, daily backups and exports. Use pseudonyms only — no names or birthdates.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                if let e = model.openError { Text(e).font(.caption).foregroundStyle(.red) }
            }
            .frame(width: 460)
            Button {
                do { try model.chooseDataFolder(URL(fileURLWithPath: path)) } catch {
                    self.error = error.localizedDescription
                }
            } label: {
                Text("Get Started").frame(width: 200).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func feature(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }

    private func choose() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Use This Folder"
        p.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        if p.runModal() == .OK, let u = p.url { path = u.path; error = nil }
    }
}

struct AppIconView: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.29, green: 0.47, blue: 0.98),
                                              Color(red: 0.42, green: 0.27, blue: 0.86)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: size * 0.08, y: size * 0.04)
    }
}

// MARK: - Menu bar quick log

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AppIconView(size: 26)
                Text("Quick Log").font(.headline)
                Spacer()
                HoursTicker(minutes: model.totalMinutes, font: .caption.weight(.semibold), unit: "h logged", showDelta: true)
                    .font(.caption)
            }
            if !model.isReady {
                Text("Open the tracker to finish setup.").foregroundStyle(.secondary)
            } else {
                if model.toConfirmCount > 0 {
                    Button { show(.log) } label: {
                        HStack {
                            Image(systemName: "repeat").foregroundStyle(.orange)
                            Text("\(model.toConfirmCount) session\(model.toConfirmCount == 1 ? "" : "s") to confirm")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                EntryFormView(draft: $model.quickDraft, mode: .quick)
                Button {
                    var d = model.quickDraft
                    if model.log(&d) { model.quickDraft = d }
                } label: {
                    Label("Log Session", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(model.quickDraft.category.color)
                .controlSize(.large).keyboardShortcut(.defaultAction)
                if let t = model.toast {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(t.message).font(.caption).lineLimit(2)
                        Spacer()
                        if t.canUndo { Button("Undo") { model.undoToast() }.controlSize(.small) }
                    }
                }
            }
            Divider()
            HStack {
                Button("Open Tracker") { show(nil) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 440)
    }

    private func show(_ section: SidebarItem?) {
        if let section { model.section = section }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
