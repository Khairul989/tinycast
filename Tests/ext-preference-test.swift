import Foundation

/// `StoredValue(renderValue:)` is the only reach into the render tree, and this harness has none.
enum RenderValue: Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
}

enum ExtensionCatalog {
    static func safeName(_ name: String) -> String { name }
}

/// Holds what the Keychain would, so the harness never writes to the real login keychain.
final class StubSecretStore: ExtensionPreferenceSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]

    var accounts: [String] { lock.withLock { items.keys.sorted() } }

    func get(account: String) -> String? { lock.withLock { items[account] } }
    func set(_ value: String, account: String) { lock.withLock { items[account] = value } }
    func remove(account: String) { lock.withLock { _ = items.removeValue(forKey: account) } }

    func removeAll(prefix: String) {
        lock.withLock { items = items.filter { !$0.key.hasPrefix(prefix) } }
    }
}

@main
@MainActor
struct ExtensionPreferenceTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        passwordPreferencesStayOutOfTheFile()
        aPlaintextPasswordLeftByAnOlderBuildMoves()
        uninstallTakesTheSecretsWithIt()
        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func passwordPreferencesStayOutOfTheFile() {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = StubSecretStore()
        let storage = ExtensionStorage(directory: directory, secrets: secrets)

        storage.setPreference(
            extension: "sample", key: "apiKey", value: .string("sk-live-1"), kind: .password)
        storage.setPreference(
            extension: "sample", key: "host", value: .string("example.com"), kind: .textfield)
        storage.flush()

        let onDisk =
            (try? String(contentsOf: directory.appendingPathComponent("sample.json"), encoding: .utf8))
            ?? ""
        check("the secret is not in the file", !onDisk.contains("sk-live-1"), onDisk)
        check("a non-secret still is", onDisk.contains("example.com"), onDisk)
        check("the secret is in the keychain", secrets.get(account: "sample:apiKey") == "sk-live-1")
        check(
            "the secret reads back",
            storage.preference(extension: "sample", key: "apiKey", kind: .password)
                == .string("sk-live-1"))

        storage.setPreference(extension: "sample", key: "apiKey", value: .string(""), kind: .password)
        check("clearing it removes the item", secrets.get(account: "sample:apiKey") == nil)
    }

    static func aPlaintextPasswordLeftByAnOlderBuildMoves() {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("legacy.json")
        // What the old build wrote: the secret in `preferences`, no keychain item anywhere.
        let older = ExtensionStorage(directory: directory, secrets: StubSecretStore())
        older.setPreference(
            extension: "legacy", key: "apiKey", value: .string("sk-old-9"), kind: .textfield)
        older.flush()
        check(
            "the harness really wrote the plaintext it is about to migrate",
            ((try? String(contentsOf: file, encoding: .utf8)) ?? "").contains("sk-old-9"))

        let secrets = StubSecretStore()
        let storage = ExtensionStorage(directory: directory, secrets: secrets)
        check(
            "the value still resolves",
            storage.preference(extension: "legacy", key: "apiKey", kind: .password)
                == .string("sk-old-9"))
        check("it moved to the keychain", secrets.get(account: "legacy:apiKey") == "sk-old-9")
        storage.flush()
        let onDisk = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        check("the plaintext copy is gone", !onDisk.contains("sk-old-9"), onDisk)
    }

    static func uninstallTakesTheSecretsWithIt() {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = StubSecretStore()
        let storage = ExtensionStorage(directory: directory, secrets: secrets)
        storage.setPreference(
            extension: "gone", key: "apiKey", value: .string("sk-1"), kind: .password)
        storage.setPreference(
            extension: "gone-too", key: "apiKey", value: .string("sk-2"), kind: .password)
        storage.removeAll(extension: "gone")
        check("its own secret goes", secrets.get(account: "gone:apiKey") == nil)
        check("a neighbour's stays", secrets.get(account: "gone-too:apiKey") == "sk-2")
    }

    // MARK: - Harness

    static func scratch() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ext-preference-\(UUID().uuidString)")
    }

    static func check(_ label: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passes += 1
            print("ok    \(label)")
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }
}
