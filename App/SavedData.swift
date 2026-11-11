import Foundation

/// A second copy of everything the page keeps in its browser storage (logs, settings, the API key).
///
/// The page saves to `localStorage`, which lives in WebKit's website data. iOS can clear that data (low disk space,
/// some restores). This file in Application Support is not touched by that, so the page's storage can be put back
/// on the next launch.
final class SavedData {
    static let shared = SavedData(file: SavedData.defaultFile)

    static var defaultFile: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GymPlanner")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("storage.json")
    }

    private let file: URL
    private let queue = DispatchQueue(label: "SavedData")
    private var values: [String: String]
    private var pending: DispatchWorkItem?
    private var lastDailyCopy = Date.distantPast

    init(file: URL) {
        self.file = file
        values = Self.read(file) ?? Self.read(file.appendingPathExtension("previous")) ?? [:]
    }

    private static func read(_ file: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    /// Everything saved, as a JSON object literal for the page's start-up script.
    var json: String {
        queue.sync {
            guard let data = try? JSONEncoder().encode(values), let text = String(data: data, encoding: .utf8) else { return "{}" }
            return text
        }
    }
    var count: Int { queue.sync { values.count } }
    func value(for key: String) -> String? { queue.sync { values[key] } }

    func set(_ key: String, _ value: String) { queue.async { self.values[key] = value; self.schedule() } }
    func remove(_ key: String) { queue.async { self.values[key] = nil; self.schedule() } }
    /// The page's storage as it is right now; replaces the copy.
    func replaceAll(_ all: [String: String]) { queue.async { if self.values != all { self.values = all; self.schedule() } } }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.write() }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    /// Writes now. Called when the app leaves the foreground.
    func flush() { queue.sync { pending?.cancel(); pending = nil; write() } }

    private func write() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        // Once a day keep the previous file, so one bad write can never be the only copy.
        if Date().timeIntervalSince(lastDailyCopy) > 86_400, FileManager.default.fileExists(atPath: file.path) {
            let previous = file.appendingPathExtension("previous")
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.copyItem(at: file, to: previous)
            lastDailyCopy = Date()
        }
        try? data.write(to: file, options: .atomic)
    }
}
