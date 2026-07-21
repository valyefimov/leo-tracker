import SwiftUI

struct ContentView: View {
    @StateObject private var store = TrackerStore()
    @State private var selection = "Tracker"
    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var entryToDelete: TimeEntry?
    @State private var entryToEdit: TimeEntry?
    @State private var editTask = ""
    @State private var editStartedAt = Date()
    @State private var editEndedAt = Date()

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(LeoTheme.green)
                        Image(systemName: "timer").foregroundStyle(.white).font(.title3.bold())
                    }.frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("LEO").font(.headline.bold())
                        Text("TIME TRACKER").font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.bottom, 18)

                navItem("Tracker", icon: "stopwatch.fill")
                navItem("Reports", icon: "chart.bar.xaxis")
                Spacer()
                Label("Data stays on this Mac", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
            }
            .padding(18)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            Group { selection == "Tracker" ? AnyView(tracker) : AnyView(reports) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .alert("Leo Tracker", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .overlay(alignment: .top) {
            if let message = store.autoStopMessage {
                Text(message).font(.callout.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.orange.opacity(0.92), in: Capsule()).foregroundStyle(.white).padding(.top, 12)
                    .onTapGesture { store.autoStopMessage = nil }
                    .pointingHandCursor()
            }
        }
        .sheet(isPresented: $showingNewProject) {
            VStack(alignment: .leading, spacing: 18) {
                Text("New Project").font(.title2.bold())
                TextField("Project name", text: $newProjectName).textFieldStyle(.roundedBorder).onSubmit { createProject() }
                HStack {
                    Spacer()
                    Button("Cancel") { showingNewProject = false }
                        .pointingHandCursor()
                    Button("Create") { createProject() }
                        .buttonStyle(.borderedProminent)
                        .tint(LeoTheme.green)
                        .pointingHandCursor()
                }
            }.padding(24).frame(width: 360)
        }
        .alert("Delete session?", isPresented: Binding(get: { entryToDelete != nil }, set: { if !$0 { entryToDelete = nil } })) {
            Button("Delete", role: .destructive) { if let entryToDelete { store.delete(entry: entryToDelete) }; entryToDelete = nil }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: { Text("This session will be permanently removed.") }
        .sheet(item: $entryToEdit) { entry in
            VStack(alignment: .leading, spacing: 18) {
                Text("Edit Session").font(.title2.bold())
                TextField("Session name", text: $editTask, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                DatePicker("Start", selection: $editStartedAt, displayedComponents: [.date, .hourAndMinute])
                    .pointingHandCursor()
                if entry.endedAt != nil {
                    DatePicker("End", selection: $editEndedAt, displayedComponents: [.date, .hourAndMinute])
                        .pointingHandCursor()
                } else {
                    Text("Active session: only the start time can be edited.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { entryToEdit = nil }
                        .pointingHandCursor()
                    Button("Save") {
                        store.update(entry: entry, task: editTask, startedAt: editStartedAt, endedAt: entry.endedAt == nil ? nil : editEndedAt)
                        entryToEdit = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LeoTheme.green)
                    .pointingHandCursor()
                }
            }
            .padding(24)
            .frame(width: 420)
        }
    }

    private var tracker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Time Tracker").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Focus on the task — Leo records the rest.").foregroundStyle(.secondary)
                }
                Card {
                    VStack(spacing: 22) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 7) {
                                Label(store.isTracking ? "TRACKING NOW" : "READY TO TRACK", systemImage: store.isTracking ? "circle.fill" : "circle")
                                    .font(.caption.bold()).foregroundStyle(store.isTracking ? LeoTheme.green : .secondary)
                                Text(store.elapsed.clockText).font(.system(size: 50, weight: .semibold, design: .rounded)).monospacedDigit()
                            }
                            Spacer()
                            Button(action: store.toggleTracking) {
                                Image(systemName: store.isTracking ? "stop.fill" : "play.fill")
                                    .font(.title2.bold()).frame(width: 58, height: 58)
                                    .foregroundStyle(.white).background(store.isTracking ? Color.red : LeoTheme.green, in: Circle())
                            }.buttonStyle(.plain).help(store.isTracking ? "Stop" : "Start").pointingHandCursor()
                        }
                        HStack(spacing: 10) {
                            Picker("Project", selection: $store.selectedProjectID) { ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) } }
                                .labelsHidden().frame(maxWidth: 230).disabled(store.isTracking).pointingHandCursor(!store.isTracking)
                            Button("New Project", systemImage: "plus") { newProjectName = ""; showingNewProject = true }.disabled(store.isTracking).pointingHandCursor(!store.isTracking)
                        }
                        TextField("What are you working on?", text: $store.task, axis: .vertical)
                            .textFieldStyle(.plain).font(.title3).padding(15)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                            .disabled(store.isTracking).onSubmit { if !store.isTracking { store.start() } }
                        HStack {
                            Label(store.autoStopDescription, systemImage: "moon.zzz")
                            Spacer()
                            Picker("Auto stop", selection: $store.autoStopMinutes) {
                                Text("Off").tag(0)
                                Text("1 min").tag(1)
                                Text("5 min").tag(5)
                                Text("10 min").tag(10)
                                Text("15 min").tag(15)
                                Text("30 min").tag(30)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 100)
                            .pointingHandCursor()
                            Text("Today: \(store.entries.filter { Calendar.current.isDateInToday($0.startedAt) }.reduce(0) { $0 + $1.duration }.shortText)").fontWeight(.semibold)
                        }.font(.callout).foregroundStyle(.secondary)
                    }
                }
                sessionsList(entries: store.entries)
            }.padding(34).frame(maxWidth: 880)
        }
    }

    private var reports: some View {
        let reportEntries = store.reportEntries
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Reports").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Review time and export data for billing.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu("Export", systemImage: "square.and.arrow.up") {
                        Button("CSV") { store.exportCSV(entries: reportEntries) }
                    }.buttonStyle(.borderedProminent).tint(LeoTheme.green).pointingHandCursor()
                }
                HStack(spacing: 12) {
                    Picker("Project", selection: $store.reportProjectID) {
                        ForEach(store.projects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    .frame(maxWidth: 260)
                    .pointingHandCursor()
                    Picker("Period", selection: $store.range) { ForEach(ReportRange.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).frame(maxWidth: 520).pointingHandCursor()
                }
                HStack(spacing: 16) {
                    metric("Total time", value: store.totalReportDuration.shortText, icon: "clock.fill")
                    metric("Hours", value: store.totalReportDuration.hoursText, icon: "calendar.badge.clock")
                    metric("Sessions", value: "\(reportEntries.count)", icon: "checkmark.circle.fill")
                    metric("Average", value: (reportEntries.isEmpty ? 0 : store.totalReportDuration / Double(reportEntries.count)).shortText, icon: "chart.line.uptrend.xyaxis")
                }
                ReportCalendar(days: reportCalendarDays, totals: dailyDurations)
                sessionsList(entries: reportEntries)
            }.padding(34).frame(maxWidth: 980)
        }
    }

    private func sessionsList(entries: [TimeEntry]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sessions").font(.headline).padding(.bottom, 12)
                if entries.isEmpty {
                    ContentUnavailableView("No sessions yet", systemImage: "clock.badge.questionmark", description: Text("Start your first work session."))
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ForEach(Array(entries.prefix(20).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        HStack(spacing: 14) {
                            Circle().fill(entry.endedAt == nil ? LeoTheme.green : LeoTheme.green.opacity(0.16)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.task).fontWeight(.medium).lineLimit(1)
                                Text("\(entry.project) · \(entry.startedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }
                            .textSelection(.enabled)
                            Spacer()
                            Text(entry.duration.shortText).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                                .textSelection(.enabled)
                            Button("Edit", systemImage: "pencil") { beginEditing(entry) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Edit session time")
                                .pointingHandCursor()
                            if entry.endedAt != nil {
                                Button("Continue", systemImage: "play.fill") { store.continueSession(from: entry) }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .disabled(store.isTracking)
                                    .help("Continue with the same session name")
                                    .pointingHandCursor(!store.isTracking)
                                Button("Delete", systemImage: "trash", role: .destructive) { entryToDelete = entry }.labelStyle(.iconOnly).buttonStyle(.borderless).help("Delete session")
                                    .pointingHandCursor()
                            }
                        }.padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private func navItem(_ title: String, icon: String) -> some View {
        Button { selection = title } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(selection == title ? LeoTheme.green : .clear, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(selection == title ? .white : .primary)
        }.buttonStyle(.plain).pointingHandCursor()
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        Card { HStack { Image(systemName: icon).foregroundStyle(LeoTheme.green).font(.title2); VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title2.bold()).monospacedDigit() }; Spacer() } }.frame(maxWidth: .infinity)
    }

    private func createProject() {
        store.createProject(named: newProjectName)
        showingNewProject = false
    }

    private func beginEditing(_ entry: TimeEntry) {
        editTask = entry.task
        editStartedAt = entry.startedAt
        editEndedAt = entry.endedAt ?? Date()
        entryToEdit = entry
    }

    private var dailyDurations: [Date: TimeInterval] {
        Dictionary(grouping: store.reportEntries, by: { Calendar.current.startOfDay(for: $0.startedAt) })
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
    }

    private var reportCalendarDays: [Date] {
        let calendar = Calendar.current
        let today = Date()
        switch store.range {
        case .today:
            return [calendar.startOfDay(for: today)]
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
            return days(from: interval.start, to: calendar.date(byAdding: .day, value: 6, to: interval.start) ?? interval.start)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: today),
                  let end = calendar.date(byAdding: .day, value: -1, to: interval.end)
            else { return [] }
            return days(from: interval.start, to: end)
        case .all:
            guard let first = store.reportEntries.map(\.startedAt).min(),
                  let last = store.reportEntries.map(\.startedAt).max()
            else { return [] }
            return days(from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: last))
        }
    }

    private func days(from start: Date, to end: Date) -> [Date] {
        var result: [Date] = []
        var day = Calendar.current.startOfDay(for: start)
        let endDay = Calendar.current.startOfDay(for: end)
        while day <= endDay {
            result.append(day)
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}

private struct ReportCalendar: View {
    let days: [Date]
    let totals: [Date: TimeInterval]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Calendar").font(.headline)
                    Spacer()
                    Text("Hours by day").font(.caption).foregroundStyle(.secondary)
                }
                if days.isEmpty {
                    Text("No time in this period.").foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(days, id: \.self) { day in
                            let total = totals[Calendar.current.startOfDay(for: day)] ?? 0
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(day.formatted(.dateTime.day()))
                                    .font(.headline)
                                Text(total > 0 ? total.hoursText : "—")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(total > 0 ? LeoTheme.deepGreen : .secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                            .padding(10)
                            .background(total > 0 ? LeoTheme.green.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
    }
}
