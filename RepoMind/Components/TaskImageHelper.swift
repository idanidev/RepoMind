import UIKit

// MARK: - TaskImageHelper
// Shared logic for loading and resizing task images, used by both
// TaskCardEnhanced (KanbanColumnView) and ListTaskCard (KanbanListView).

enum TaskImageHelper {

    /// Returns the full-resolution UIImage for a task, reading from
    /// in-memory `imageData` first, then from disk via `imagePath`.
    static func fullImage(from task: TaskItem) -> UIImage? {
        if let data = task.imageData, let img = UIImage(data: data) {
            return img
        }
        if let path = task.imagePath,
           let data = FileManager.default.contents(atPath: path),
           let img = UIImage(data: data) {
            return img
        }
        return nil
    }

    /// Asynchronously loads and scales a thumbnail off the main thread.
    /// Safe to call from `Task.detached` — no actor isolation.
    static func loadThumbnail(from task: TaskItem, size: CGSize) async -> UIImage? {
        let data = task.imageData
        let path = task.imagePath

        return await Task.detached(priority: .utility) { () -> UIImage? in
            let source: UIImage?
            if let d = data {
                source = UIImage(data: d)
            } else if let p = path, let d = FileManager.default.contents(atPath: p) {
                source = UIImage(data: d)
            } else {
                source = nil
            }
            guard let img = source else { return nil }
            return UIGraphicsImageRenderer(size: size).image { _ in
                img.draw(in: CGRect(origin: .zero, size: size))
            }
        }.value
    }
}
