import Foundation

enum SourceDocumentStore {
    private static var sourcesURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Environment.appGroupIdentifier
        )?.appendingPathComponent("Sources", isDirectory: true)
    }

    static func save(data: Data, for itemId: String) {
        guard let dir = sourcesURL else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(itemId).pdf")
        try? data.write(to: url)
    }

    static func url(for itemId: String) -> URL? {
        guard let dir = sourcesURL else { return nil }
        let url = dir.appendingPathComponent("\(itemId).pdf")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func exists(for itemId: String) -> Bool {
        url(for: itemId) != nil
    }
}
