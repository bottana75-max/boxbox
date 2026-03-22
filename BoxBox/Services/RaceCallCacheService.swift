import Foundation
import CryptoKit

struct RaceCallCacheEntry: Codable, Identifiable {
    let id: String
    let round: Int
    let weekendPhase: String
    let contextFingerprint: String
    let call: RaceCall
    let createdAt: Date

    init(round: Int, weekendPhase: String, contextFingerprint: String, call: RaceCall, createdAt: Date = Date()) {
        self.id = Self.makeID(round: round, weekendPhase: weekendPhase, contextFingerprint: contextFingerprint)
        self.round = round
        self.weekendPhase = weekendPhase
        self.contextFingerprint = contextFingerprint
        self.call = call
        self.createdAt = createdAt
    }

    static func makeID(round: Int, weekendPhase: String, contextFingerprint: String) -> String {
        "\(round)|\(weekendPhase)|\(contextFingerprint)"
    }
}

struct RaceCallCacheLookup {
    let exact: RaceCallCacheEntry?
    let latestForRacePhase: RaceCallCacheEntry?
}

final class RaceCallCacheService {
    static let shared = RaceCallCacheService()

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.bottana.racecall.racecall-cache", qos: .utility)
    private let maxEntries = 48

    private init(fileManager: FileManager = .default) {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let appDirectory = baseDirectory.appendingPathComponent("RaceCall", isDirectory: true)
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        self.fileURL = appDirectory.appendingPathComponent("race-call-cache.json")
    }

    func fingerprint(for context: RaceCallContext) throws -> String {
        let data = try encoder.encode(context)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func lookup(round: Int, weekendPhase: String, contextFingerprint: String) -> RaceCallCacheLookup {
        let entries = loadEntries()
        let exactID = RaceCallCacheEntry.makeID(round: round, weekendPhase: weekendPhase, contextFingerprint: contextFingerprint)
        let exact = entries.first(where: { $0.id == exactID })
        let latest = entries
            .filter { $0.round == round && $0.weekendPhase == weekendPhase }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        return RaceCallCacheLookup(exact: exact, latestForRacePhase: latest)
    }

    func save(call: RaceCall, for context: RaceCallContext) throws {
        let fingerprint = try fingerprint(for: context)
        let entry = RaceCallCacheEntry(round: context.round, weekendPhase: context.weekendPhase, contextFingerprint: fingerprint, call: call)
        var entries = loadEntries().filter { $0.id != entry.id }
        entries.insert(entry, at: 0)
        entries = Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(maxEntries))
        try persist(entries)
    }

    private func loadEntries() -> [RaceCallCacheEntry] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
            return (try? decoder.decode([RaceCallCacheEntry].self, from: data)) ?? []
        }
    }

    private func persist(_ entries: [RaceCallCacheEntry]) throws {
        let data = try encoder.encode(entries)
        try queue.sync {
            try data.write(to: fileURL, options: .atomic)
        }
    }
}
