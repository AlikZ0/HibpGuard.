import Foundation
import Combine

protocol ChecklistStorage {
    func load() throws -> Set<String>
    func save(_ completedIDs: Set<String>) throws
}

struct FileChecklistStorage: ChecklistStorage {
    let url: URL

    init(url: URL) { self.url = url }

    init() throws {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("HibpGuard", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("action-plan.json")
    }

    func load() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: url)))
    }

    func save(_ completedIDs: Set<String>) throws {
        let data = try JSONEncoder().encode(completedIDs.sorted())
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

@MainActor
final class ActionPlanStore: ObservableObject {
    @Published private(set) var completedIDs: Set<String> = []
    @Published private(set) var error: AppError?
    private let storage: (any ChecklistStorage)?

    init(storage: any ChecklistStorage) {
        self.storage = storage
        reload()
    }

    init() {
        do {
            storage = try FileChecklistStorage()
        } catch {
            storage = nil
            self.error = .storage
        }
        reload()
    }

    func reload() {
        guard let storage else { error = .storage; return }
        do {
            let knownIDs = Set(ActionStep.all.map(\.id))
            completedIDs = try storage.load().intersection(knownIDs)
            error = nil
        } catch {
            self.error = .storage
        }
    }

    func toggle(_ id: String) {
        guard ActionStep.all.contains(where: { $0.id == id }) else { return }
        var next = completedIDs
        if !next.insert(id).inserted { next.remove(id) }
        persist(next)
    }

    func reset() { persist([]) }

    private func persist(_ next: Set<String>) {
        guard let storage else { error = .storage; return }
        do {
            try storage.save(next)
            // Change UI only after a successful write.
            completedIDs = next
            error = nil
        } catch {
            self.error = .storage
        }
    }
}
