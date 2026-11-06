import XCTest
@testable import Slate

/// Store-level tests for the reading-mode task toggle. `VaultStore` is
/// `@MainActor`, so the whole class runs on the main actor like the app does.
@MainActor
final class VaultStoreTests: XCTestCase {

    private var vault: URL!

    override func setUp() async throws {
        vault = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("slate-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let vault { try? FileManager.default.removeItem(at: vault) }
        vault = nil
    }

    private func makeStore(note text: String, name: String = "Tasks.md") async throws -> (VaultStore, URL) {
        let url = vault.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        let store = VaultStore()
        store.openVault(vault)
        // The scan runs off the main thread; wait for the note list and the
        // automatic first selection to land.
        for _ in 0..<200 where store.selectedNoteID == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(store.selectedNoteID, "vault scan never selected a note")
        return (store, url)
    }

    func testToggleTaskChecksAnOpenBox() async throws {
        let (store, url) = try await makeStore(note: "- [ ] open item\n- [x] done item\n")
        defer { store.closeVault() }

        let lineStart = ("- [ ] open item\n- [x] done item\n" as NSString).range(of: "- [ ]").location
        store.toggleTask(at: lineStart)

        XCTAssertEqual(store.editorText, "- [x] open item\n- [x] done item\n")
        // A click writes through immediately, so the file matches the screen.
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8),
                       "- [x] open item\n- [x] done item\n")
    }

    func testToggleTaskUnchecksADoneBox() async throws {
        let text = "- [ ] open item\n- [x] done item\n"
        let (store, url) = try await makeStore(note: text)
        defer { store.closeVault() }

        store.toggleTask(at: (text as NSString).range(of: "- [x]").location)

        XCTAssertEqual(store.editorText, "- [ ] open item\n- [ ] done item\n")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8),
                       "- [ ] open item\n- [ ] done item\n")
    }

    func testToggleTaskIgnoresLinesWithoutATask() async throws {
        let text = "just prose\n\n- [ ] open item\n"
        let (store, _) = try await makeStore(note: text)
        defer { store.closeVault() }

        store.toggleTask(at: 0)
        XCTAssertEqual(store.editorText, text)
    }

    func testToggleTaskSurvivesASelectionChange() async throws {
        // The rendered page asks for a toggle on the note it rendered; if the
        // user has already clicked elsewhere the store must not edit the wrong
        // file. Guarding on the current buffer is what keeps that safe.
        let (store, url) = try await makeStore(note: "- [ ] only task\n")
        defer { store.closeVault() }

        store.toggleTask(at: 0)
        store.selectedNoteID = nil
        store.toggleTask(at: 0)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "- [x] only task\n")
    }
}
