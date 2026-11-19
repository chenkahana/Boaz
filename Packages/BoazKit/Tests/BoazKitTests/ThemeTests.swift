import Foundation
import Testing
@testable import BoazKit

@Suite("Themes")
struct ThemeTests {
    @Test func paletteThemeJSONDecodesAndMatchesItself() throws {
        for palette in SpacePalette.all {
            let theme = try WindowTheme.decode(palette.themeJSON)
            #expect(theme.primaryColorPalette?["midTone"] != nil)
            #expect(SpacePalette.matching(palette.themeJSON) == palette)
        }
    }

    @Test func decodeReadsArcSemanticColors() throws {
        let json = """
        {"semanticColorPalette": {"appearanceBased": {
          "light": {"background": {"colorSpace": "extendedSRGB", "red": 1, "green": 0, "blue": 0, "alpha": 1}},
          "dark": {"background": {"colorSpace": "extendedSRGB", "red": 0, "green": 0, "blue": 1, "alpha": 1}}
        }}}
        """
        let theme = try WindowTheme.decode(Data(json.utf8))
        #expect(theme.color("background", dark: false)?.red == 1)
        #expect(theme.color("background", dark: true)?.blue == 1)
        #expect(theme.color("missing", dark: false) == nil)
    }

    @Test func decodeSurvivesAnUnfamiliarBackground() throws {
        // A background shape this build doesn't know must not cost the space its palettes.
        let json = """
        {"semanticColorPalette": {"appearanceBased": {
          "light": {"background": {"colorSpace": "extendedSRGB", "red": 0.5, "green": 0.5, "blue": 0.5, "alpha": 1}}
        }},
        "background": {"someFutureFormat": {"_0": {"whatever": true}}}}
        """
        let theme = try WindowTheme.decode(Data(json.utf8))
        #expect(theme.color("background", dark: false)?.red == 0.5)
        #expect(theme.lightBackdrop == nil)
    }

    @Test func themeOptionsEditOnlyWhatChanged() throws {
        let original = SpacePalette.sky.themeJSON
        var options = SpaceThemeOptions(themeJSON: original)
        #expect(SpacePalette.matching(original)?.id == "sky")
        options.accent = WindowTheme.RGBA(red: 1, green: 0, blue: 0)
        let edited = options.applied(to: original)
        let theme = try WindowTheme.decode(edited)
        #expect(theme.primaryColorPalette?["midTone"]?.red == 1)
        // The untouched background survives the edit.
        let untouched = try WindowTheme.decode(original)
        #expect(theme.color("background", dark: false) == untouched.color("background", dark: false))
        #expect(theme.color("background", dark: true) == untouched.color("background", dark: true))
    }

    @Test func themeOptionsRoundTrip() throws {
        let original = SpacePalette.rose.themeJSON
        let options = SpaceThemeOptions(themeJSON: original)
        #expect(options.applied(to: original) == original)
    }
}

@Suite("LiveSource")
struct LiveSourceTests {
    @Test func filtersAndRepositoriesAreSortedAndUnique() {
        let source = LiveSource(provider: LiveSource.githubPulls,
                                filters: ["b", "a", "a"], repositories: ["z/one", "a/two", "a/two"])
        #expect(source.filters == ["a", "b"])
        #expect(source.repositories == ["a/two", "z/one"])
        #expect(source.has("a"))
        #expect(!source.has("c"))
    }

    @Test func unknownFieldsAndProvidersStillDecode() throws {
        let json = #"{"provider": "gitlab.issues", "filters": ["mine"], "repositories": [], "future": 42}"#
        let source = try JSONDecoder().decode(LiveSource.self, from: Data(json.utf8))
        #expect(source.provider == "gitlab.issues")
        #expect(source.has("mine"))
    }

    @Test func liveChildIDsAreStableAcrossDevices() {
        let url = URL(string: "https://github.com/boaz/repo/pull/1")!
        let first = SidebarItem.liveChildID(folderID: "folder-1", url: url)
        let second = SidebarItem.liveChildID(folderID: "folder-1", url: url)
        #expect(first == second)
        #expect(SidebarItem.liveChildID(folderID: "folder-2", url: url) != first)
    }

    @Test func isLiveChildDistinguishesRefreshTabsFromUserTabs() {
        let url = URL(string: "https://github.com/boaz/repo/pull/1")!
        let folder = SidebarItem(id: "folder-1", spaceID: "s1", profileID: "p1", parentID: nil,
                                 kind: .folder, position: 0)
        let refreshTab = SidebarItem(id: SidebarItem.liveChildID(folderID: "folder-1", url: url),
                                     spaceID: "s1", profileID: "p1", parentID: "folder-1",
                                     kind: .tab, url: url, position: 0)
        let userTab = SidebarItem(id: "user-tab", spaceID: "s1", profileID: "p1", parentID: "folder-1",
                                  kind: .tab, url: url, position: 1)
        #expect(refreshTab.isLiveChild(of: folder))
        #expect(!userTab.isLiveChild(of: folder))
        #expect(!folder.isLiveChild(of: folder))
    }
}
