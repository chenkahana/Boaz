import FolioKit
import SwiftUI
import WebKit

/// What an AI sheet shows.
enum AIRequest: Identifiable, Equatable {
    case page(tabID: String, mode: PageAssistantView.Mode)
    case tidyTabs(spaceID: String)
    case tidyTitles(spaceID: String)

    var id: String {
        switch self {
        case .page(let tabID, _): "page-\(tabID)"
        case .tidyTabs(let spaceID): "tabs-\(spaceID)"
        case .tidyTitles(let spaceID): "titles-\(spaceID)"
        }
    }
}

private enum AIRadius {
    #if os(iOS)
    static let card = Theme.Radius.card
    static let row = Theme.Radius.row
    #else
    static let card = MacRadius.card
    static let row = MacRadius.row
    #endif
}

/// Sheet frame: a navigation bar with Close on iPhone, a header with Done on the Mac.
private struct AISheet<Content: View, Actions: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button(role: .close) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { actions() }
                }
        }
        #else
        VStack(spacing: 0) {
            HStack {
                Label(title, systemImage: "sparkles").font(.headline)
                Spacer()
                actions()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            Divider()
            content()
        }
        .frame(minWidth: 460, idealWidth: 520, minHeight: 460, idealHeight: 600)
        #endif
    }
}

/// Explains why Apple Intelligence can't run right now, and how to turn it on (Boaz never changes the setting).
struct AIStatusView: View {
    let status: AIFeatures.Status
    let retry: () -> Void

    var body: some View {
        switch status {
        case .available:
            EmptyView()
        case .notReady:
            ContentUnavailableView {
                Label { Text("Getting ready…") } icon: { ProgressView() }
            } description: {
                Text("Apple Intelligence is still downloading its model. Try again in a few minutes.")
            } actions: {
                Button("Try Again", action: retry)
            }
        case .appleIntelligenceOff:
            ContentUnavailableView {
                Label("Turn On Apple Intelligence", systemImage: "sparkles")
            } description: {
                #if os(iOS)
                Text("Open Settings › Apple Intelligence & Siri and turn on Apple Intelligence. Boaz runs these features on your iPhone; nothing is sent anywhere.")
                #else
                Text("Open System Settings › Apple Intelligence & Siri and turn on Apple Intelligence. Boaz runs these features on your Mac; nothing is sent anywhere.")
                #endif
            } actions: {
                Button("Try Again", action: retry)
            }
        case .unsupportedLanguage:
            ContentUnavailableView("Language Not Supported", systemImage: "character.bubble",
                                   description: Text("Apple Intelligence doesn't support your language yet."))
        case .unsupportedDevice:
            ContentUnavailableView("Not Available", systemImage: "sparkles",
                                   description: Text("This device doesn't support Apple Intelligence."))
        }
    }
}

/// Shows `content` while the model is available, otherwise `AIStatusView`. Rechecks on Try Again.
private struct AvailabilityGate<Content: View>: View {
    @State private var status = AIFeatures.status
    @ViewBuilder var content: () -> Content

    var body: some View {
        if status == .available {
            content()
        } else {
            AIStatusView(status: status) { status = AIFeatures.status }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct OnDeviceFootnote: View {
    var body: some View {
        Label("Apple Intelligence, on this device", systemImage: "lock.shield")
            .font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - Page

/// Summarize and Ask for one page, in one sheet.
struct PageAssistantView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case summary = "Summary", ask = "Ask"
        var id: Self { self }
    }

    @State private var assistant: PageAssistant
    @State private var mode: Mode
    @State private var question = ""
    @FocusState private var questionFocused: Bool

    init(page: WebPage, mode: Mode) {
        _assistant = State(initialValue: PageAssistant(page: page))
        _mode = State(initialValue: mode)
    }

    var body: some View {
        AISheet(title: mode == .summary ? "Summarize Page" : "Ask This Page") {
            AvailabilityGate {
                VStack(spacing: 0) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    switch mode {
                    case .summary: summaryPane
                    case .ask: askPane
                    }
                }
                .task(id: mode) {
                    switch mode {
                    case .summary:
                        if assistant.summary == nil && assistant.summaryError == nil { await assistant.summarize() }
                    case .ask:
                        assistant.prepareToAsk()
                        questionFocused = true
                    }
                }
            }
        } actions: {
            if mode == .summary {
                Button("Summarize Again", systemImage: "arrow.clockwise") { Task { await assistant.summarize() } }
                    .disabled(assistant.isSummarizing)
                    .help("Summarize Again")
            }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !assistant.title.isEmpty {
                Text(assistant.title).font(.headline).lineLimit(2)
            }
            if !assistant.host.isEmpty {
                Text(assistant.host).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pageHeader
                if let summary = assistant.summary {
                    VStack(alignment: .leading, spacing: 12) {
                        if let gist = summary.gist {
                            Text(gist).font(.body.weight(.semibold))
                        }
                        ForEach(Array((summary.points ?? []).enumerated()), id: \.offset) { _, point in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(.tint)
                                Text(point)
                            }
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: AIRadius.card))
                    .animation(.smooth, value: summary.points?.count)
                    .accessibilityElement(children: .combine)
                }
                if assistant.isSummarizing && assistant.summary?.gist == nil {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Reading the page…").foregroundStyle(.secondary)
                    }
                }
                if let error = assistant.summaryError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
                if assistant.coversStartOnly {
                    Label("This page is long, so the summary covers only its beginning.", systemImage: "text.append")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                OnDeviceFootnote()
            }
            .padding(16)
        }
    }

    private var askPane: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        pageHeader
                        if assistant.turns.isEmpty {
                            Text("Ask anything about this page. Answers come only from its text.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(assistant.turns) { turn in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(turn.question).font(.body.weight(.semibold))
                                if let error = turn.error {
                                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                                } else if turn.answer.isEmpty {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text(turn.answer).textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: AIRadius.row))
                            .id(turn.id)
                        }
                        if let notice = assistant.notice {
                            Text(notice).font(.footnote).foregroundStyle(.secondary)
                        }
                        if assistant.coversStartOnly {
                            Label("This page is long, so answers come from its beginning only.", systemImage: "text.append")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        OnDeviceFootnote()
                    }
                    .padding(16)
                }
                .onChange(of: assistant.turns.last?.answer) {
                    if let id = assistant.turns.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            HStack(spacing: 8) {
                TextField("Ask about this page", text: $question)
                    .textFieldStyle(.plain)
                    .focused($questionFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).frame(width: 36, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || assistant.isAnswering)
                .accessibilityLabel("Ask")
            }
            .padding(12)
        }
    }

    private func send() {
        let text = question
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !assistant.isAnswering else { return }
        question = ""
        Task { await assistant.ask(text) }
    }
}

// MARK: - Tidy Tabs

/// Previews the model's folders for a space's Today tabs; Create Folders applies them.
struct TidyTabsView: View {
    @Environment(\.dismiss) private var dismiss
    let tabs: [SidebarItem]
    let apply: (TabTidier.Plan) -> Void
    @State private var plan: TabTidier.Plan?
    @State private var error: String?

    var body: some View {
        AISheet(title: "Tidy Tabs") {
            AvailabilityGate {
                Group {
                    if tabs.count < TabTidier.minimumTabs {
                        ContentUnavailableView("Not Enough Tabs", systemImage: "square.stack",
                                               description: Text("Tidy Tabs needs at least \(TabTidier.minimumTabs) tabs in Today."))
                    } else if let error {
                        ContentUnavailableView {
                            Label("Couldn't Tidy Tabs", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Try Again") { Task { await load() } }
                        }
                    } else if let plan {
                        preview(plan)
                    } else {
                        ProgressView("Sorting \(tabs.count) tabs…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .task { if plan == nil && tabs.count >= TabTidier.minimumTabs { await load() } }
            }
        } actions: {
            Button("Create Folders") {
                if let plan { apply(plan) }
                dismiss()
            }
            .disabled(plan?.groups.isEmpty ?? true)
        }
    }

    private func load() async {
        error = nil
        do {
            let plan = try await TabTidier.groups(for: tabs)
            if plan.groups.isEmpty { throw TabTidier.Failure.nothingToGroup }
            self.plan = plan
        } catch {
            self.error = (error as? TabTidier.Failure)?.localizedDescription ?? AIFeatures.message(for: error)
        }
    }

    private func preview(_ plan: TabTidier.Plan) -> some View {
        List {
            ForEach(plan.groups.indices, id: \.self) { index in
                Section {
                    ForEach(plan.groups[index].tabs) { TabLine(tab: $0) }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        TextField("Folder name", text: Binding(
                            get: { self.plan?.groups[index].name ?? "" },
                            set: { self.plan?.groups[index].name = $0 }))
                        .textFieldStyle(.plain)
                        .font(.headline)
                    }
                    .textCase(nil)
                }
            }
            if !plan.leftovers.isEmpty {
                Section("Stays in Today") {
                    ForEach(plan.leftovers) { TabLine(tab: $0) }
                }
            }
            Section {
                OnDeviceFootnote()
            } footer: {
                Text("Boaz creates \(plan.groups.count) folder\(plan.groups.count == 1 ? "" : "s") in Today and moves these tabs in. Rename a folder by editing its name.")
            }
        }
    }
}

private struct TabLine: View {
    let tab: SidebarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(tab.title ?? tab.url?.host() ?? "Tab").lineLimit(1)
            if let host = tab.url?.host() {
                Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tidy Tab Titles

/// Previews short titles for a space's pinned tabs; Apply renames the checked ones.
struct TidyTitlesView: View {
    @Environment(\.dismiss) private var dismiss
    let tabs: [SidebarItem]
    let apply: ([TabTidier.TitleChange]) -> Void
    @State private var changes: [TabTidier.TitleChange]?
    @State private var error: String?

    private var candidates: [SidebarItem] { TabTidier.messyTitled(tabs) }

    var body: some View {
        AISheet(title: "Tidy Tab Titles") {
            AvailabilityGate {
                Group {
                    if candidates.isEmpty {
                        ContentUnavailableView("Titles Look Tidy", systemImage: "checkmark.circle",
                                               description: Text(tabs.isEmpty ? "This space has no pinned tabs."
                                                                 : "Your pinned tabs already have short, clear titles."))
                    } else if let error {
                        ContentUnavailableView {
                            Label("Couldn't Tidy Titles", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Try Again") { Task { await load() } }
                        }
                    } else if changes != nil {
                        preview
                    } else {
                        ProgressView("Reading \(candidates.count) title\(candidates.count == 1 ? "" : "s")…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .task { if changes == nil && !candidates.isEmpty { await load() } }
            }
        } actions: {
            Button("Apply") {
                apply(changes?.filter(\.isIncluded) ?? [])
                dismiss()
            }
            .disabled(!(changes?.contains(where: \.isIncluded) ?? false))
        }
    }

    private func load() async {
        error = nil
        do {
            let changes = try await TabTidier.titles(for: candidates)
            if changes.isEmpty { throw TabTidier.Failure.nothingToRename }
            self.changes = changes
        } catch {
            self.error = (error as? TabTidier.Failure)?.localizedDescription ?? AIFeatures.message(for: error)
        }
    }

    private var preview: some View {
        List {
            Section {
                ForEach(Binding(get: { changes ?? [] }, set: { changes = $0 })) { $change in
                    Toggle(isOn: $change.isIncluded) {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Title", text: $change.title).textFieldStyle(.plain).font(.body.weight(.medium))
                            Text(change.tab.title ?? change.tab.url?.host() ?? "")
                                .font(.caption).foregroundStyle(.secondary).strikethrough().lineLimit(1)
                        }
                    }
                }
            } footer: {
                Text("Only pinned tabs are renamed: Today tabs take their title from the page, so a new name wouldn't last.")
            }
            Section { OnDeviceFootnote() }
        }
    }
}

// MARK: - Settings

/// "Show AI features" for each app's settings. Hidden on devices that can't run Apple Intelligence.
struct AISettingsSection: View {
    @AppStorage(AIFeatures.preferenceKey) private var showAIFeatures = true

    var body: some View {
        if AIFeatures.status != .unsupportedDevice {
            Section {
                Toggle("Show AI features", isOn: $showAIFeatures)
            } header: {
                Text("Apple Intelligence")
            } footer: {
                #if os(iOS)
                Text("Summarize and ask about pages, and tidy your tabs. Runs on your iPhone with Apple Intelligence; nothing is sent to a server.")
                #else
                Text("Summarize and ask about pages, and tidy your tabs. Runs on your Mac with Apple Intelligence; nothing is sent to a server.")
                #endif
            }
        }
    }
}
