import SwiftUI

struct ContentView: View {
    @StateObject private var store = TrackerStore()
    @State private var selection = "Tracker"
    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var entryToDelete: TimeEntry?

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
            }
        }
        .sheet(isPresented: $showingNewProject) {
            VStack(alignment: .leading, spacing: 18) {
                Text("New Project").font(.title2.bold())
                TextField("Project name", text: $newProjectName).textFieldStyle(.roundedBorder).onSubmit { createProject() }
                HStack { Spacer(); Button("Cancel") { showingNewProject = false }; Button("Create") { createProject() }.buttonStyle(.borderedProminent).tint(LeoTheme.green) }
            }.padding(24).frame(width: 360)
        }
        .alert("Delete session?", isPresented: Binding(get: { entryToDelete != nil }, set: { if !$0 { entryToDelete = nil } })) {
            Button("Delete", role: .destructive) { if let entryToDelete { store.delete(entry: entryToDelete) }; entryToDelete = nil }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: { Text("This session will be permanently removed.") }
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
                            }.buttonStyle(.plain).help(store.isTracking ? "Stop" : "Start")
                        }
                        HStack(spacing: 10) {
                            Picker("Project", selection: $store.selectedProjectID) { ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) } }
                                .labelsHidden().frame(maxWidth: 230).disabled(store.isTracking)
                            Button("New Project", systemImage: "plus") { newProjectName = ""; showingNewProject = true }.disabled(store.isTracking)
                        }
                        TextField("What are you working on?", text: $store.task, axis: .vertical)
                            .textFieldStyle(.plain).font(.title3).padding(15)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                            .disabled(store.isTracking).onSubmit { if !store.isTracking { store.start() } }
                        HStack {
                            Label("Auto-stops after 5 minutes inactive", systemImage: "moon.zzz")
                            Spacer()
                            Text("Today: \(store.entries.filter { Calendar.current.isDateInToday($0.startedAt) }.reduce(0) { $0 + $1.duration }.shortText)").fontWeight(.semibold)
                        }.font(.callout).foregroundStyle(.secondary)
                    }
                }
                latestEntries
            }.padding(34).frame(maxWidth: 880)
        }
    }

    private var reports: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Reports").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Review time and export data for billing.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu("Export", systemImage: "square.and.arrow.up") {
                        Button("CSV") { store.exportCSV() }
                    }.buttonStyle(.borderedProminent).tint(LeoTheme.green)
                }
                Picker("Period", selection: $store.range) { ForEach(ReportRange.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(maxWidth: 520)
                HStack(spacing: 16) {
                    metric("Total time", value: store.totalDuration.shortText, icon: "clock.fill")
                    metric("Sessions", value: "\(store.entries.count)", icon: "checkmark.circle.fill")
                    metric("Average", value: (store.entries.isEmpty ? 0 : store.totalDuration / Double(store.entries.count)).shortText, icon: "chart.line.uptrend.xyaxis")
                }
                latestEntries
            }.padding(34).frame(maxWidth: 980)
        }
    }

    private var latestEntries: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sessions").font(.headline).padding(.bottom, 12)
                if store.entries.isEmpty {
                    ContentUnavailableView("No sessions yet", systemImage: "clock.badge.questionmark", description: Text("Start your first work session."))
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ForEach(Array(store.entries.prefix(20).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        HStack(spacing: 14) {
                            Circle().fill(entry.endedAt == nil ? LeoTheme.green : LeoTheme.green.opacity(0.16)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.task).fontWeight(.medium).lineLimit(1)
                                Text("\(entry.project) · \(entry.startedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.duration.shortText).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                            if entry.endedAt != nil { Button("Delete", systemImage: "trash", role: .destructive) { entryToDelete = entry }.labelStyle(.iconOnly).buttonStyle(.borderless).help("Delete session") }
                        }.padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private func navItem(_ title: String, icon: String) -> some View {
        Button { selection = title } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(selection == title ? LeoTheme.green.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(selection == title ? LeoTheme.deepGreen : .primary)
        }.buttonStyle(.plain)
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        Card { HStack { Image(systemName: icon).foregroundStyle(LeoTheme.green).font(.title2); VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title2.bold()).monospacedDigit() }; Spacer() } }.frame(maxWidth: .infinity)
    }

    private func createProject() {
        store.createProject(named: newProjectName)
        showingNewProject = false
    }
}
