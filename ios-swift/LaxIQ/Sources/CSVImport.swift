import Foundation

enum CSVImport {
    static func parseLines(_ text: String) -> [[String]] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return lines.filter { !$0.isEmpty }.map { line in
            line.split(separator: ",").map { part in
                part.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
    }

    // Skips a header row if the first line looks like one (contains a known keyword).
    static func dataRows(_ text: String, headerKeywords: [String]) -> [[String]] {
        var rows = parseLines(text)
        if let first = rows.first,
           headerKeywords.contains(where: { keyword in first.contains { $0.lowercased().contains(keyword) } }) {
            rows.removeFirst()
        }
        return rows
    }
}
