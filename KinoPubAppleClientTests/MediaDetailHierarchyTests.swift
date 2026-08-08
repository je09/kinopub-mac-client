import SwiftUI
import XCTest
import ViewInspector
import KinoPubBackend
@testable import KinoPub

/// Deterministic hierarchy contracts for the split media-detail screen (Phase 5): loading and
/// loaded states expose stable texts and VoiceOver labels without any network. Sections are
/// exercised through the composition; environment objects must be applied before `.environment`
/// (ViewInspector traversal quirk).
@MainActor
final class MediaDetailHierarchyTests: XCTestCase {

  func testLoadingStateReservesShelvesWithStableTexts() throws {
    let deps = AppDependencies.preview()
    let model = makeModel(deps: deps)
    // Default model state: skeleton item, itemLoaded == false.
    let view = makeView(model: model, deps: deps)

    let inspect = try view.inspect()
    // Skeleton shelves hold the page layout while the item is in flight.
    XCTAssertNoThrow(try inspect.find(text: "Trailers"))
    // Cast & Crew renders from the mock item's credited names even before the server load.
    XCTAssertNoThrow(try inspect.find(text: "Cast & Crew"))
    // The hero still renders the (skeleton-redacted) title.
    XCTAssertNoThrow(try inspect.find(text: MediaItem.mock().localizedTitle))
  }

  func testLoadedStateRendersAllPrimarySections() throws {
    let deps = AppDependencies.preview()
    let model = makeModel(deps: deps)
    // Simulate a finished details load (no network in tests).
    model.mediaItem = MediaItem.mock()
    model.itemLoaded = true
    let view = makeView(model: model, deps: deps)

    let inspect = try view.inspect()
    XCTAssertNoThrow(try inspect.find(text: "Description"))
    XCTAssertNoThrow(try inspect.find(text: "Information"))
    XCTAssertNoThrow(try inspect.find(text: "Languages"))
    XCTAssertNoThrow(try inspect.find(text: "Cast & Crew"))
    // Supplementary shelves reserve skeleton space until their loaders settle.
    XCTAssertNoThrow(try inspect.find(text: "Related"))
    XCTAssertNoThrow(try inspect.find(text: "Images"))
    XCTAssertNoThrow(try inspect.find(text: "Facts"))
    XCTAssertNoThrow(try inspect.find(text: "Reviews"))
    XCTAssertNoThrow(try inspect.find(text: "More from Джеймс Ганн"))
    XCTAssertNoThrow(try inspect.find(text: "More with Крис Пратт"))
  }

  func testVotePillsAndPrimaryActionsRender() throws {
    let deps = AppDependencies.preview()
    let model = makeModel(deps: deps)
    model.mediaItem = MediaItem.mock()
    model.itemLoaded = true
    // The hero is exercised directly: HeroBackdrop (an AppKit-backed container) is not traversable
    // through the composition by ViewInspector, but the section itself is.
    let hero = MediaHeroSection(
      model: model,
      plotExpanded: .constant(false),
      showCreateFolder: .constant(false),
      newFolderName: .constant(""),
      usesSidebar: true)
      .environmentObject(deps.libraryState)

    // Vote pills (2) + primary watched/watchlist action + plot toggle must all be buttons.
    let buttons = try hero.inspect().findAll(ViewType.Button.self)
    XCTAssertGreaterThanOrEqual(buttons.count, 4, "expected vote pills + primary action + plot toggle")
    // Bookmark picker + download are menus (label/identifier stability is covered by
    // AccessibilityContractTests; ViewInspector cannot extract macOS .plain-style modifiers).
    let menus = try hero.inspect().findAll(ViewType.Menu.self)
    XCTAssertGreaterThanOrEqual(menus.count, 2, "expected bookmark + download menus")
  }

  // MARK: - Fixtures

  private func makeModel(deps: AppDependencies) -> MediaItemModel {
    MediaItemModel(
      mediaItemId: MediaItem.mock().id,
      itemsService: VideoContentServiceMock(),
      downloadManager: deps.downloadManager,
      linkProvider: RouteLinkProvider(),
      errorHandler: ErrorHandler(),
      actionsService: deps.actionsService,
      libraryState: deps.libraryState,
      localProgressStore: deps.localProgressStore,
      seasonDownloadManager: deps.seasonDownloadManager)
  }

  private func makeView(model: MediaItemModel, deps: AppDependencies) -> some View {
    MediaItemView(model: model)
      .environmentObject(deps.libraryState)
      .environmentObject(NavigationState())
      .environmentObject(ErrorHandler())
      .environment(\.dependencies, deps)
  }
}
