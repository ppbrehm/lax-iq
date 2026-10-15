import SwiftUI
import UniformTypeIdentifiers

private enum RosterManageSortColumn: Hashable {
    case number, name, position
}

private struct RosterHeaderWidth: ViewModifier {
    let width: CGFloat?

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width, alignment: .leading)
        } else {
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RosterScreen: View {
    @EnvironmentObject var appState: AppState
    var isReadOnly: Bool = false
    @State private var showAddPlayerForm = false
    @State private var showImportInstructions = false
    @State private var showImportPicker = false
    @State private var showOverwriteChoice = false
    @State private var pendingImportRows: [(String, String, String, String)] = []

    @State private var number = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var position = ""

    @State private var sortColumn: RosterManageSortColumn = .number
    @State private var sortAscending = true

    private var sortedRoster: [RosterPlayer] {
        appState.roster.sorted { a, b in
            let result = isLess(a, b)
            return sortAscending ? result : !result
        }
    }

    private func isLess(_ a: RosterPlayer, _ b: RosterPlayer) -> Bool {
        switch sortColumn {
        case .number:
            return (Int(a.number ?? "") ?? Int.max) < (Int(b.number ?? "") ?? Int.max)
        case .name:
            let an = a.lastName.lowercased(), bn = b.lastName.lowercased()
            if an != bn { return an < bn }
            return a.firstName.lowercased() < b.firstName.lowercased()
        case .position:
            let ap = (a.position ?? "").lowercased(), bp = (b.position ?? "").lowercased()
            return ap < bp
        }
    }

    private func toggleSort(_ column: RosterManageSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }

    var body: some View {
        Group {
            if appState.roster.isEmpty {
                Text("No players in the roster yet. Add players using the buttons below.")
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                // A simple management list (Settings only) — no drilling into a
                // player's season stats here, just add/remove/import. The table's
                // rounded corners stay fixed in place; only the rows scroll inside.
                List {
                    Section {
                        ForEach(sortedRoster) { player in
                            rosterRow(player)
                        }
                        .onDelete(perform: isReadOnly ? nil : { indexSet in
                            for index in indexSet {
                                let player = sortedRoster[index]
                                Task { await appState.removeRosterPlayer(id: player.id) }
                            }
                        })
                    } header: {
                        rosterHeaderRow
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(white: 0.98))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15)))
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isReadOnly {
                HStack(spacing: 10) {
                    Button {
                        showImportInstructions = true
                    } label: {
                        Text("📁 Upload Roster")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(red: 0, green: 0.48, blue: 1))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0, green: 0.48, blue: 1), lineWidth: 1.5))
                    }

                    Button {
                        showAddPlayerForm = true
                    } label: {
                        Text("+ Add Player")
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
        .navigationTitle("Team Roster")
        .task { await appState.loadRoster() }
        .sheet(isPresented: $showAddPlayerForm) {
            addPlayerSheet
        }
        .sheet(isPresented: $showImportInstructions) {
            importInstructionsSheet
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            handleImport(result)
        }
        .confirmationDialog(
            "You already have \(appState.roster.count) player\(appState.roster.count == 1 ? "" : "s") on this roster. How should the uploaded file be applied?",
            isPresented: $showOverwriteChoice,
            titleVisibility: .visible
        ) {
            Button("Combine with Current Roster") {
                Task { await appState.importRoster(rows: pendingImportRows, overwrite: false) }
            }
            Button("Replace Entire Roster", role: .destructive) {
                Task { await appState.importRoster(rows: pendingImportRows, overwrite: true) }
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

    private let numberColumnWidth: CGFloat = 50
    private let nameColumnWidth: CGFloat = 150

    private func rosterRow(_ player: RosterPlayer) -> some View {
        HStack {
            Text(player.number.map { "#\($0)" } ?? "—")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: numberColumnWidth, alignment: .leading)
            Text("\(player.lastName), \(player.firstName)")
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .frame(width: nameColumnWidth, alignment: .leading)
            Text(player.position?.isEmpty == false ? player.position! : "—")
                .font(.system(size: 13))
                .frame(width: 130, alignment: .leading)
            Spacer(minLength: 0)
        }
        .foregroundColor(.black)
    }

    @ViewBuilder
    private func rosterSortHeaderButton(_ title: String, column: RosterManageSortColumn, width: CGFloat? = nil) -> some View {
        Button {
            toggleSort(column)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .modifier(RosterHeaderWidth(width: width))
        }
        .buttonStyle(.plain)
    }

    private var rosterHeaderRow: some View {
        HStack {
            rosterSortHeaderButton("#", column: .number, width: numberColumnWidth)
            rosterSortHeaderButton("Player", column: .name, width: nameColumnWidth)
            rosterSortHeaderButton("Position", column: .position, width: 130)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.secondary)
        .textCase(nil)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let text = try String(contentsOf: url, encoding: .utf8)
            let rows = CSVImport.dataRows(text, headerKeywords: ["number", "name"])

            let players: [(String, String, String, String)] = rows.compactMap { parts in
                guard parts.count >= 3 else { return nil }
                return (parts[0], parts[1], parts[2], parts.count > 3 ? parts[3] : "")
            }

            guard !players.isEmpty else {
                appState.errorMessage = "No valid players found in CSV."
                return
            }

            pendingImportRows = players
            if appState.roster.isEmpty {
                Task { await appState.importRoster(rows: players, overwrite: false) }
            } else {
                showOverwriteChoice = true
            }
        } catch {
            appState.errorMessage = "Error importing roster: \(error.localizedDescription)"
        }
    }

    private var importInstructionsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your CSV file needs one player per line, in this order:")
                        .font(.system(size: 15))

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text("number, last name, first name, position")
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
                            Text("12, Smith, John, Attack")
                            Text("7, Johnson, Sarah, Midfield")
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
            .navigationTitle("Upload Roster")
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

    private var addPlayerSheet: some View {
        NavigationStack {
            Form {
                TextField("Jersey Number (e.g. 12)", text: $number)
                    .keyboardType(.numberPad)
                TextField("Last Name (e.g. Smith)", text: $lastName)
                TextField("First Name (e.g. John)", text: $firstName)
                TextField("Position (e.g. Attack, Midfield)", text: $position)
            }
            .navigationTitle("Add New Player")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddPlayerForm = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await appState.addRosterPlayer(
                                number: number, firstName: firstName,
                                lastName: lastName, position: position
                            )
                            number = ""; firstName = ""; lastName = ""; position = ""
                            showAddPlayerForm = false
                        }
                    }
                }
            }
        }
    }
}
