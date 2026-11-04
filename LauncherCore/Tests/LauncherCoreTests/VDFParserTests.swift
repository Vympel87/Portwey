import Testing
@testable import LauncherCore

@Suite("Steam VDF parser")
struct VDFParserTests {
    @Test("Reads library folders and their installed apps")
    func libraryFolders() throws {
        let text = """
        "libraryfolders"
        {
            "0"
            {
                "path"      "C:\\\\Program Files (x86)\\\\Steam"
                "apps"
                {
                    "228980"    "123"
                    "1234560"   "456"
                }
            }
        }
        """

        let root = try #require(VDFParser.parse(text))
        let folder = try #require(root["libraryfolders"]?["0"])

        #expect(folder["path"]?.stringValue == #"C:\Program Files (x86)\Steam"#)

        let apps = try #require(folder["apps"]?.objectValue)
        #expect(apps.count == 2)
        #expect(apps["1234560"]?.stringValue == "456")
    }

    @Test("Reads an app manifest")
    func appManifest() throws {
        let text = """
        "AppState"
        {
            "appid"         "1234560"
            "name"          "Starmaker Story"
            "StateFlags"    "4"
            "installdir"    "Starmaker Story"
        }
        """

        let state = try #require(VDFParser.parse(text)?["AppState"])
        #expect(state["appid"]?.stringValue == "1234560")
        #expect(state["name"]?.stringValue == "Starmaker Story")
        #expect(state["StateFlags"]?.stringValue == "4")
    }

    @Test("Values are strings, nested blocks are objects")
    func valueKinds() throws {
        let root = try #require(VDFParser.parse(#""a" { "b" "c" "d" { } }"#))
        let a = try #require(root["a"])

        #expect(a["b"]?.stringValue == "c")
        #expect(a["b"]?.objectValue == nil)
        #expect(a["d"]?.objectValue?.isEmpty == true)
        #expect(a["missing"] == nil)
    }
}
