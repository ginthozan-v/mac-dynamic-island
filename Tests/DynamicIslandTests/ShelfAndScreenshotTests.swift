import Foundation
import SwiftUI
import Testing
@testable import DynamicIsland

@MainActor
@Suite("Shelf")
struct ShelfStoreTests {
    private let a = URL(fileURLWithPath: "/tmp/a.png")
    private let b = URL(fileURLWithPath: "/tmp/b.pdf")

    @Test func addsFilesOnceInOrder() {
        let shelf = ShelfStore(persistent: false)
        shelf.add([a, b, a])
        #expect(shelf.items.map(\.url) == [a, b])
    }

    @Test func removeAndClear() {
        let shelf = ShelfStore(persistent: false)
        shelf.add([a, b])
        shelf.remove(shelf.items[0])
        #expect(shelf.items.map(\.url) == [b])
        shelf.clear()
        #expect(shelf.items.isEmpty)
    }

    @Test func previewStoresDoNotTouchSavedShelf() {
        let key = "shelf.bookmarks"
        let before = UserDefaults.standard.array(forKey: key) as? [Data]
        let shelf = ShelfStore(persistent: false)
        shelf.add([a])
        #expect(UserDefaults.standard.array(forKey: key) as? [Data] == before)
    }
}

@Suite("Screenshots")
struct ScreenshotMetadataTests {
    @Test func readsCaptureRegionFromExtendedAttribute() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID()).png")
        try Data([0]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let plist = try PropertyListSerialization.data(fromPropertyList: [12, 34, 560, 780], format: .binary, options: 0)
        let status = plist.withUnsafeBytes {
            setxattr(url.path, "com.apple.metadata:kMDItemScreenCaptureGlobalRect", $0.baseAddress, plist.count, 0, 0)
        }
        #expect(status == 0)
        #expect(ScreenshotWatcher.captureRect(of: url) == CGRect(x: 12, y: 34, width: 560, height: 780))
    }

    @Test func returnsNilWithoutMetadata() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plain-\(UUID()).png")
        try Data([0]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ScreenshotWatcher.captureRect(of: url) == nil)
    }
}

@Suite("Notch shape")
struct NotchShapeTests {
    @Test func staysInsideItsFrame() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 40)
        let path = NotchShape(topRadius: 6, bottomRadius: 11).path(in: rect)
        #expect(!path.isEmpty)
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(path.boundingRect))
    }

    @Test func clampsOversizedRadii() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 20)
        let path = NotchShape(topRadius: 100, bottomRadius: 100).path(in: rect)
        #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(path.boundingRect))
    }
}
