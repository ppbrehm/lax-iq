import SwiftUI
import UniformTypeIdentifiers

struct ScheduleScreen: View {
    @EnvironmentObject var appState: AppState
    var isReadOnly: Bool = false
    @State private var showAddGameForm = false
    @State private var showImportInstructions = false
    @State private var showImportPicker = false
    @State private var showOverwriteChoice = false
    @State private var pendingImportRows: [(String, String, String, String, String)] = []

    @State private var year = ""
    @State private var month = ""
    @State private var day = ""
    @State private var opponent = ""
    @State private var location = "home"

    private func scheduleRow(_ game: Game) -> some View {
        let isHome = game.location == "home"
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(shortDate(game.date)).font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isHome ? .blue : .orange)
                Text(isHome ? game.opponent : "@ \(game.opponent)")
                    .font(.system(size: 16))
            }
            Spacer()
            GameStatusBadge(game: game)
        }
    }

    var body: some View {
        Group {
            if appState.games.isEmpty {
                Text("No games scheduled yet. Add games using the buttons below.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                // In Settings (management mode, isReadOnly == false) this is a plain
                // display — add/upload only, no drilling into a game's stats. The
                // Home screen's read-only Schedule keeps the existing tap-to-view-stats
                // behavior.
                List(appState.games) { game in
                    if isReadOnly {
                        NavigationLink(value: GameStatsRoute(gameId: game.id, backLabel: "← Back to Schedule", readOnly: true)) {
                            scheduleRow(game)
                        }
                    } else {
                        scheduleRow(game)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isReadOnly {
                HStack(spacing: 10) {
                    Button {
                        showImportInstructions = true
                    } label: {
                        Text("📁 Upload Schedule")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(red: 0, green: 0.48, blue: 1))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0, green: 0.48, blue: 1), lineWidth: 1.5))
                    }

                    Button {
                        showAddGameForm = true
                    } label: {
                        Text("+ Add New Game")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 0, green: 0.48, blue: 1))
                            .cornerRadius(14)
                    }
                }
                .padding()
                .background(.bar)
            }
        }
        .navigationTitle("Schedule")
        .navigationDestination(for: GameStatsRoute.self) { route in
            GameStatsScreen(gameId: route.gameId, backLabel: route.backLabel, readOnly: route.readOnly)
        }
        .task { await appState.loadGames() }
        .sheet(isPresented: $showAddGameForm) {
            addGameSheet
        }
        .sheet(isPresented: $showImportInstructions) {
            importInstructionsSheet
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            handleImport(result)
        }
        .confirmationDialog(
            "You already have \(appState.games.count) game\(appState.games.count == 1 ? "" : "s") on this schedule. How should the uploaded file be applied?",
            isPresented: $showOverwriteChoice,
            titleVisibility: .visible
        ) {
            Button("Combine with Current Schedule") {
                Task { await appState.importGames(rows: pendingImportRows, overwrite: false) }
            }
            Button("Replace Entire Schedule", role: .destructive) {
                Task { await appState.importGames(rows: pendingImportRows, overwrite: true) }
            }
            Button("Cancel", role: .cancel) { pendingImportRows = [] }
        }
        .alert("Error", isPresented: Binding(
            get: { !appState.errorMessage.isEmpty },
            set: { if !$0 { appState.errorMessage = "" } }
        )) {
            Button("OK") { appState.errorMessage = "" }
        } message: {
            Text(appState.errorMessage)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let text = try String(contentsOf: url, encoding: .utf8)
            let rows = CSVImport.dataRows(text, headerKeywords: ["year", "month", "opponent"])

            let parsedGames: [(String, String, String, String, String)] = rows.compactMap { parts in
                guard parts.count >= 4 else { return nil }
                let location = parts.count > 4 ? parts[4].lowercased() : "home"
                return (parts[0], parts[1], parts[2], parts[3], location)
            }

            guard !parsedGames.isEmpty else {
                appState.errorMessage = "No valid games found in CSV."
                return
            }

            pendingImportRows = parsedGames
            if appState.games.isEmpty {
                Task { await appState.importGames(rows: parsedGames, overwrite: false) }
            } else {
                showOverwriteChoice = true
            }
        } catch {
            appState.errorMessage = "Error importing schedule: \(error.localizedDescription)"
        }
    }

    private var importInstructionsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your CSV file needs one game per line, in this order:")
                        .font(.system(size: 15))

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text("year, month, day, opponent, location")
                            .font(.system(.body, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(10)
                    .background(Color(white: 0.95))
                    .cornerRadius(8)

                    Text("Example:")
                        .font(.system(size: 15, weight: .semibold))

                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("2026, 3, 15, North High School, home")
                            Text("2026, 3, 22, South Academy, away")
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .background(Color(white: 0.95))
                    .cornerRadius(8)

                    Text("Before you continue, save that CSV file somewhere in your iPhone's **Files** app (e.g. On My iPhone, or iCloud Drive) — that's where the next screen will look for it.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .padding()
            }
            .navigationTitle("Upload Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showImportInstructions = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Choose File") {
                        showImportInstructions = false
                        showImportPicker = true
                    }
                }
            }
        }
    }

    private var addGameSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Year", text: $year).keyboardType(.numberPad)
                        TextField("Month", text: $month).keyboardType(.numberPad)
                        TextField("Day", text: $day).keyboardType(.numberPad)
                    }
                    TextField("Opponent (e.g. North HS)", text: $opponent)
                }
                Section("Location") {
                    Picker("Location", selection: $location) {
                        Text("Home").tag("home")
                        Text("Away").tag("away")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Add New Game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddGameForm = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await appState.createGame(year: year, month: month, day: day, opponent: opponent, location: location)
                            year = ""; month = ""; day = ""; opponent = ""; location = "home"
                            showAddGameForm = false
                        }
                    }
                }
            }
        }
    }
}
