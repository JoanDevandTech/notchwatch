import XCTest
import NotchwatchCore
@testable import DynamicNotch

@MainActor
final class IncidentsProfileStoreTests: XCTestCase {

    private func makeStore(directory: URL? = nil, keychain: FakeKeychain? = nil) -> (IncidentsProfileStore, URL, FakeKeychain) {
        let keychain = keychain ?? FakeKeychain()
        let url = directory ?? IncidentsTestFactory.makeTemporaryDirectory()
        let store = IncidentsProfileStore(directoryURL: url, keychain: keychain)
        TestLifetime.retain(store)
        return (store, url, keychain)
    }

    func testStartsEmptyWhenNothingIsSaved() {
        let (store, url, _) = makeStore()

        XCTAssertEqual(store.profile, .empty)
        XCTAssertEqual(store.profileURL, url.appendingPathComponent("profile.json"))
        XCTAssertEqual(store.seenStoreURL, url.appendingPathComponent("seen.json"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.profileURL.path))
    }

    func testProfileChangesRoundTripThroughDisk() {
        let (store, url, _) = makeStore()
        let collection = WatchedCollection(id: "src/a", name: "Alpha", style: CollectionStyle(symbol: "flame.fill", colorHex: "#E78580"))
        var profile = store.profile
        profile.sources = [.asana(IncidentsTestFactory.makeConfig(collection: collection))]
        profile.sound.muted = true
        profile.behavior.hotKey = .optionCommandI
        profile.appearance.priorityColors[.urgente] = "#FF0000"

        store.profile = profile

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.profileURL.path))
        let (reloaded, _, _) = makeStore(directory: url)
        XCTAssertEqual(reloaded.profile, profile)
        XCTAssertEqual(reloaded.profile.collection(id: "src/a")?.style.symbol, "flame.fill")
    }

    func testExportAndImportKeepTheProfile() throws {
        let (store, _, _) = makeStore()
        store.profile.behavior.pollInterval = 45
        store.profile.sound.volume = 0.3

        let data = try store.export()
        let (other, _, _) = makeStore()
        try other.importProfile(data)

        XCTAssertEqual(other.profile, store.profile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.profileURL.path))
    }

    func testImportRejectsGarbage() {
        let (store, _, _) = makeStore()

        XCTAssertThrowsError(try store.importProfile(Data("not json".utf8)))
        XCTAssertEqual(store.profile, .empty)
    }

    func testTokensLiveInTheKeychainBySourceID() {
        let (store, _, keychain) = makeStore()

        XCTAssertNil(store.token(for: "src"))
        XCTAssertTrue(store.saveToken("  abc  ", for: "src"))
        XCTAssertEqual(keychain.values["src"], "abc")
        XCTAssertEqual(store.token(for: "src"), "abc")

        store.deleteToken(for: "src")

        XCTAssertNil(store.token(for: "src"))
        XCTAssertNil(keychain.values["src"])
    }

    func testEmptyTokenIsNotSaved() {
        let keychain = FakeKeychain()
        let (store, _, _) = makeStore(keychain: keychain)

        XCTAssertFalse(store.saveToken("   ", for: "src"))
        XCTAssertTrue(keychain.values.isEmpty)
    }

    func testKeychainFailureIsReported() {
        let keychain = FakeKeychain()
        keychain.failsSaving = true
        let (store, _, _) = makeStore(keychain: keychain)

        XCTAssertFalse(store.saveToken("abc", for: "src"))
        XCTAssertNil(store.token(for: "src"))
    }
}
