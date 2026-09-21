import Foundation

@main
@MainActor
struct ExtensionManifestNameTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        namesThatEscapeTheInstallDirectory()
        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// `ExtensionCatalog.install` removes the destination it builds from this name before copying.
    static func namesThatEscapeTheInstallDirectory() {
        for name in ["", ".", "..", ".hidden"] {
            check(
                "a manifest named \(name.debugDescription) is refused",
                ExtensionManifest(json: manifest(named: name)) == nil)
        }
        for name in ["clipboard", "@raycast/clipboard", "a-..", " ..", "with.dots"] {
            check(
                "a manifest named \(name.debugDescription) still loads",
                ExtensionManifest(json: manifest(named: name))?.name == name)
        }
    }

    static func manifest(named name: String) -> [String: Any] {
        ["name": name, "commands": [["name": "index", "title": "Index", "mode": "view"]]]
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
