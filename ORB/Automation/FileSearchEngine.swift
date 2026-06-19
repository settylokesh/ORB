//
//  FileSearchEngine.swift
//  ORB
//
//  Spotlight file search via NSMetadataQuery (kMDItemDisplayName).
//

import Foundation

@MainActor
final class FileSearchEngine: NSObject {
    private var query: NSMetadataQuery?
    private var continuation: CheckedContinuation<[URL], Never>?

    /// Returns up to `limit` matching file URLs, best matches first.
    func search(name: String, limit: Int = 5) async -> [URL] {
        await withCheckedContinuation { (cont: CheckedContinuation<[URL], Never>) in
            self.continuation = cont
            let q = NSMetadataQuery()
            q.searchScopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]
            q.predicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", name)
            q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
            self.query = q
            NotificationCenter.default.addObserver(self, selector: #selector(self.finished),
                                                   name: .NSMetadataQueryDidFinishGathering, object: q)
            q.start()

            // Safety timeout so we never hang the pipeline.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.finish(limit: limit)
            }
        }
    }

    @objc private func finished() { finish(limit: 5) }

    private func finish(limit: Int) {
        guard let q = query, let cont = continuation else { return }
        q.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
        var urls: [URL] = []
        for i in 0..<min(q.resultCount, limit) {
            if let item = q.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                urls.append(URL(fileURLWithPath: path))
            }
        }
        continuation = nil
        query = nil
        cont.resume(returning: urls)
    }
}
