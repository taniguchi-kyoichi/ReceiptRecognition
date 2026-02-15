import Foundation
import UIKit

/// Saved receipt metadata
struct ReceiptMetadata: Codable, Identifiable, Sendable {
    let id: String
    let capturedAt: Date
    let ocrConfidence: Float
    let rectangleDetected: Bool
}

/// A saved receipt with its data
struct SavedReceipt: Identifiable, Sendable {
    let id: String
    let metadata: ReceiptMetadata
    let directoryURL: URL

    /// File prefix derived from directory name (e.g. "20260215_140609_a1b2c3d4")
    var filePrefix: String { directoryURL.lastPathComponent }

    var imageURL: URL { directoryURL.appendingPathComponent("\(filePrefix)_image.jpg") }
    var ocrTextURL: URL { directoryURL.appendingPathComponent("\(filePrefix)_ocr.txt") }
    var metaURL: URL { directoryURL.appendingPathComponent("\(filePrefix)_meta.json") }
    var receiptYAMLURL: URL { directoryURL.appendingPathComponent("\(filePrefix)_receipt.yml") }
}

/// Storage backend type
enum StorageBackend: String {
    case iCloud = "iCloud Documents"
    case local = "Local Documents"
}

/// Manages saving and loading receipts to iCloud Drive or local storage
actor ReceiptStore {
    static let shared = ReceiptStore()

    private let fileManager = FileManager.default
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let iCloudContainerID = "iCloud.com.kyoichi.ReceiptRecognition"

    /// Cached storage root URL (resolved once at first access)
    private var cachedRootURL: URL?
    private var resolvedBackend: StorageBackend?

    private init() {}

    // MARK: - Storage Location

    private func resolveStorageRoot() -> URL {
        if let cached = cachedRootURL {
            return cached
        }

        guard fileManager.ubiquityIdentityToken != nil else {
            let url = localDocumentsReceiptsURL
            cachedRootURL = url
            resolvedBackend = .local
            print("[ReceiptStore] iCloud not signed in. Using local: \(url.path)")
            return url
        }

        if let containerURL = fileManager.url(forUbiquityContainerIdentifier: Self.iCloudContainerID) {
            let documentsURL = containerURL.appendingPathComponent("Documents")
            let receiptsURL = documentsURL.appendingPathComponent("Receipts")

            if !fileManager.fileExists(atPath: documentsURL.path) {
                try? fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            }

            cachedRootURL = receiptsURL
            resolvedBackend = .iCloud
            print("[ReceiptStore] iCloud container found. Using: \(receiptsURL.path)")
            return receiptsURL
        }

        let url = localDocumentsReceiptsURL
        cachedRootURL = url
        resolvedBackend = .local
        print("[ReceiptStore] iCloud signed in but container unavailable. Using local: \(url.path)")
        return url
    }

    private var localDocumentsReceiptsURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("Receipts")
    }

    var currentBackend: StorageBackend {
        _ = resolveStorageRoot()
        return resolvedBackend ?? .local
    }

    // MARK: - Save

    func save(imageData: Data, ocrText: String, ocrConfidence: Float, rectangleDetected: Bool, receiptYAML: String? = nil) throws -> SavedReceipt {
        let rootURL = resolveStorageRoot()
        let now = Date()
        let shortID = UUID().uuidString.prefix(8).lowercased()

        // Build file prefix: 20260215_140609_a1b2c3d4
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateStr = dateFormatter.string(from: now)
        let filePrefix = "\(dateStr)_\(shortID)"

        // Month directory
        dateFormatter.dateFormat = "yyyy-MM"
        let monthDir = dateFormatter.string(from: now)

        // Receipt directory: Receipts/2026-02/20260215_140609_a1b2c3d4/
        let directoryURL = rootURL
            .appendingPathComponent(monthDir)
            .appendingPathComponent(filePrefix)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        // File paths with prefix
        let imageURL = directoryURL.appendingPathComponent("\(filePrefix)_image.jpg")
        let ocrURL = directoryURL.appendingPathComponent("\(filePrefix)_ocr.txt")
        let metaURL = directoryURL.appendingPathComponent("\(filePrefix)_meta.json")

        // Save resized image (max 1200px)
        let resizedData = resizeImage(data: imageData, maxDimension: 1200)

        // Save metadata
        let metadata = ReceiptMetadata(
            id: shortID,
            capturedAt: now,
            ocrConfidence: ocrConfidence,
            rectangleDetected: rectangleDetected
        )
        let metaData = try jsonEncoder.encode(metadata)

        // Receipt YAML (optional)
        let yamlURL = directoryURL.appendingPathComponent("\(filePrefix)_receipt.yml")

        if resolvedBackend == .iCloud {
            try coordinatedWrite(data: resizedData, to: imageURL)
            try coordinatedWrite(data: ocrText.data(using: .utf8)!, to: ocrURL)
            try coordinatedWrite(data: metaData, to: metaURL)
            if let yaml = receiptYAML, let yamlData = yaml.data(using: .utf8) {
                try coordinatedWrite(data: yamlData, to: yamlURL)
            }
        } else {
            try resizedData.write(to: imageURL)
            try ocrText.write(to: ocrURL, atomically: true, encoding: .utf8)
            try metaData.write(to: metaURL)
            if let yaml = receiptYAML {
                try yaml.write(to: yamlURL, atomically: true, encoding: .utf8)
            }
        }

        print("[ReceiptStore] Saved: \(filePrefix)")

        return SavedReceipt(id: shortID, metadata: metadata, directoryURL: directoryURL)
    }

    // MARK: - Update YAML

    func saveYAML(_ yaml: String, for receipt: SavedReceipt) throws {
        let url = receipt.receiptYAMLURL
        if resolvedBackend == .iCloud {
            try coordinatedWrite(data: yaml.data(using: .utf8)!, to: url)
        } else {
            try yaml.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Coordinated Write (for iCloud)

    private func coordinatedWrite(data: Data, to url: URL) throws {
        var coordinatorError: NSError?
        var writeError: Error?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { newURL in
            do {
                try data.write(to: newURL)
            } catch {
                writeError = error
            }
        }

        if let error = coordinatorError { throw error }
        if let error = writeError { throw error }
    }

    // MARK: - Load

    func loadAll() throws -> [SavedReceipt] {
        let rootURL = resolveStorageRoot()

        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }

        var receipts: [SavedReceipt] = []

        let monthDirs = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }

        for monthDir in monthDirs {
            let receiptDirs = try fileManager.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: nil)
                .filter { $0.hasDirectoryPath }

            for receiptDir in receiptDirs {
                guard let metadata = loadMetadata(from: receiptDir) else { continue }

                receipts.append(SavedReceipt(
                    id: metadata.id,
                    metadata: metadata,
                    directoryURL: receiptDir
                ))
            }
        }

        return receipts.sorted { $0.metadata.capturedAt > $1.metadata.capturedAt }
    }

    private func loadMetadata(from directoryURL: URL) -> ReceiptMetadata? {
        let prefix = directoryURL.lastPathComponent
        let metaURL = directoryURL.appendingPathComponent("\(prefix)_meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let metadata = try? jsonDecoder.decode(ReceiptMetadata.self, from: data) else {
            return nil
        }
        return metadata
    }

    func count() throws -> Int {
        try loadAll().count
    }

    // MARK: - Duplicate Detection

    func findDuplicates(ocrText: String) throws -> [SavedReceipt] {
        let existingReceipts = try loadAll()
        guard !existingReceipts.isEmpty else { return [] }

        let today = Calendar.current.startOfDay(for: Date())
        let newStoreName = extractStoreName(from: ocrText)

        return existingReceipts.filter { receipt in
            let receiptDay = Calendar.current.startOfDay(for: receipt.metadata.capturedAt)
            guard receiptDay == today else { return false }

            guard let existingOCR = try? String(contentsOf: receipt.ocrTextURL, encoding: .utf8) else {
                return false
            }
            let existingStore = extractStoreName(from: existingOCR)

            guard !newStoreName.isEmpty, !existingStore.isEmpty else { return false }

            return newStoreName.contains(existingStore)
                || existingStore.contains(newStoreName)
                || similarity(newStoreName, existingStore) > 0.6
        }
    }

    private func extractStoreName(from ocrText: String) -> String {
        ocrText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        let aBigrams = Set(zip(a, a.dropFirst()).map { String([$0, $1]) })
        let bBigrams = Set(zip(b, b.dropFirst()).map { String([$0, $1]) })
        guard !aBigrams.isEmpty || !bBigrams.isEmpty else { return 0 }
        let intersection = aBigrams.intersection(bBigrams).count
        return Double(2 * intersection) / Double(aBigrams.count + bBigrams.count)
    }

    // MARK: - Delete

    func delete(_ receipt: SavedReceipt) throws {
        try fileManager.removeItem(at: receipt.directoryURL)
    }

    // MARK: - Image Resize

    private func resizeImage(data: Data, maxDimension: CGFloat) -> Data {
        guard let image = UIImage(data: data) else { return data }

        let size = image.size
        guard max(size.width, size.height) > maxDimension else {
            return image.jpegData(compressionQuality: 0.8) ?? data
        }

        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: 0.8) ?? data
    }
}
