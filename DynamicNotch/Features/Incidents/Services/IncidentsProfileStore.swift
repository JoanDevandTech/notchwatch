import Combine
import Foundation
import NotchwatchCore

/// Perfil de Notchwatch persistido como JSON en Application Support y tokens por fuente en el Llavero
/// (servicio «com.joandev.notchwatch», cuenta = identificador de la fuente).
@MainActor
final class IncidentsProfileStore: ObservableObject {
    static let directoryName = "Notchwatch"
    static let profileFileName = "profile.json"
    static let seenStoreFileName = "seen.json"

    /// Instancia única de la app: Ajustes y el view model deben compartirla.
    static let shared = IncidentsProfileStore()

    @Published var profile: NotchwatchProfile {
        didSet {
            guard profile != oldValue else { return }
            persist()
        }
    }

    let directoryURL: URL

    private let keychain: any KeychainStoring

    var profileURL: URL {
        directoryURL.appendingPathComponent(IncidentsProfileStore.profileFileName)
    }

    /// Estado de vistas y pospuestas del monitor; vive junto al perfil.
    var seenStoreURL: URL {
        directoryURL.appendingPathComponent(IncidentsProfileStore.seenStoreFileName)
    }

    init(directoryURL: URL? = nil, keychain: (any KeychainStoring)? = nil) {
        self.directoryURL = directoryURL ?? IncidentsProfileStore.defaultDirectoryURL()
        self.keychain = keychain ?? KeychainStore()
        let url = self.directoryURL.appendingPathComponent(IncidentsProfileStore.profileFileName)
        self.profile = ProfileCodec.load(from: url) ?? .empty
    }

    static func defaultDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    func token(for sourceID: String) -> String? {
        keychain.read(account: sourceID)
    }

    @discardableResult
    func saveToken(_ token: String, for sourceID: String) -> Bool {
        guard let trimmed = Text.nonEmpty(token) else { return false }
        return keychain.save(trimmed, account: sourceID)
    }

    func deleteToken(for sourceID: String) {
        keychain.delete(account: sourceID)
    }

    func export() throws -> Data {
        try ProfileCodec.encode(profile)
    }

    func importProfile(_ data: Data) throws {
        profile = try ProfileCodec.decode(data)
    }

    private func persist() {
        try? ProfileCodec.save(profile, to: profileURL)
    }
}
