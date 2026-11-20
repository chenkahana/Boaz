import Foundation
import GRDB
import Testing
@testable import BoazKit

@Suite("StarterLibrary")
struct StarterLibraryTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func seedCreatesThePersonalSpaceOnce() throws {
        let store = try BoazStore.inMemory()
        #expect(try StarterLibrary.seedIfEmpty(store) == true)
        let sidebar = try store.sidebar()
        #expect(sidebar.spaces.map(\.id) == ["personal"])
        #expect(sidebar.container(.pinned, in: "personal") != nil)
        #expect(sidebar.container(.unpinned, in: "personal") != nil)
        #expect(try StarterLibrary.seedIfEmpty(store) == false)
    }

    @Test func finishSetupAddsFavoritesOnce() throws {
        let store = try BoazStore.inMemory()
        try StarterLibrary.seedIfEmpty(store)
        try StarterLibrary.finishSetup(store, syncing: false)
        let favorites = try store.sidebar().favorites(profileID: "default")
        #expect(favorites.count == 3)
        try StarterLibrary.finishSetup(store, syncing: false)
        #expect(try store.sidebar().favorites(profileID: "default").count == 3)
    }

    @Test func finishSetupNeverRevivesADeletedFavorite() throws {
        let store = try BoazStore.inMemory()
        try StarterLibrary.seedIfEmpty(store)
        try StarterLibrary.finishSetup(store, syncing: false)
        try store.writer.write { db in
            var favorite = try #require(try SidebarItem.fetchOne(db, key: "starter-favorite-0"))
            favorite.deletedAt = t0
            try favorite.update(db)
            // Removing it also removes the last tab, so the next setup would re-add it if it could.
        }
        try store.writer.write { db in
            for id in ["starter-favorite-1", "starter-favorite-2"] {
                var favorite = try #require(try SidebarItem.fetchOne(db, key: id))
                favorite.deletedAt = t0
                try favorite.update(db)
            }
        }
        try StarterLibrary.finishSetup(store, syncing: false)
        #expect(try store.sidebar().favorites(profileID: "default").isEmpty)
    }

    @Test func finishSetupDoesNothingWhileSyncing() throws {
        let store = try BoazStore.inMemory()
        try StarterLibrary.seedIfEmpty(store)
        try StarterLibrary.finishSetup(store, syncing: true)
        #expect(try store.sidebar().favorites(profileID: "default").isEmpty)
    }

    @Test func hasUserContent() throws {
        let store = try BoazStore.inMemory()
        try StarterLibrary.seedIfEmpty(store)
        try StarterLibrary.finishSetup(store, syncing: false)
        #expect(try StarterLibrary.hasUserContent(store) == false)
        let personal = try #require(store.sidebar().container(.unpinned, in: "personal"))
        try store.save([SidebarItem(id: "my-tab", spaceID: "personal", profileID: "default",
                                    parentID: personal.id, kind: .tab,
                                    url: URL(string: "https://example.com"), position: 0, modifiedAt: t0)])
        #expect(try StarterLibrary.hasUserContent(store) == true)
    }

    @Test func retireUnusedStarterSpaceOnlyWhenUntouchedAndEmpty() async throws {
        let store = try BoazStore.inMemory()
        try StarterLibrary.seedIfEmpty(store)
        let starterProfile = try #require(store.sidebar().spaces.first?.profileID)
        _ = try store.createSpace(title: "Real", icon: nil, palette: .defaultPalette, profileID: starterProfile, at: t0)

        // The starter profile gains a space of the user's own: the untouched starter space retires.
        #expect(try await StarterLibrary.retireUnusedStarterSpace(store) == true)
        #expect(try store.sidebar().spaces.count == 1)

        // A starter space the user renamed stays.
        let second = try BoazStore.inMemory()
        try StarterLibrary.seedIfEmpty(second)
        try second.updateSpace("personal", title: "Mine", icon: nil, themeJSON: nil)
        _ = try second.createSpace(title: "Real", icon: nil, palette: .defaultPalette, profileID: "default", at: t0)
        #expect(try await StarterLibrary.retireUnusedStarterSpace(second) == false)
        #expect(try second.sidebar().spaces.count == 2)
    }
}
