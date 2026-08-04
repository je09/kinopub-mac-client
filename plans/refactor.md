# KinoPub Apple Client — architecture and refactoring plan

## Purpose

This is an evidence-based plan to reduce UI/data coupling, put API integration behind a real data boundary, make state ownership explicit, and enable safe incremental modernization. It is deliberately phased: no big-bang rewrite, no feature freeze, and every phase has an independently shippable exit gate.

Last stack audit: **2026-08-04**.

## Baseline verified during review

- Product: macOS 13+ SwiftUI application, currently compiled in Swift 5 language mode.
- Approximate first-party Swift size: 26.5 KLOC.
- Existing local packages:
  - `KinoPubBackend`: HTTP client, endpoints, wire models, response envelopes, and tests.
  - `KinoPubKit`: downloading, local download databases, and network monitor.
  - `KinoPubUI`: visual components, image loading/cache, and a direct dependency on `KinoPubBackend`.
  - `KinoPubLogging`: logging façade.
- Largest risk concentrations:
  - `KinoPubAppleClient/Views/MediaItem/MediaItemView.swift`: 1,923 lines.
  - `KinoPubAppleClient/Views/Player/PlayerManager.swift`: 842 lines.
  - `KinoPubAppleClient/Views/Player/PlayerView.swift`: 572 lines.
  - `KinoPubAppleClient/Views/Search/SearchView.swift`: 516 lines.
  - `KinoPubAppleClient/Views/Search/SearchModel.swift`: 475 lines.
  - `KinoPubAppleClient/Views/MediaItem/MediaItemModel.swift`: 458 lines.
- Validation baseline:
  - Debug macOS app build succeeds with code signing disabled.
  - `KinoPubBackend`: 84 tests pass.
  - `KinoPubKit`: 24 tests pass.
  - `KinoPubLogging`: 3 tests pass.
  - `KinoPubUI`: 4 tests pass.
  - At plan creation there was no application/feature test target. The current milestone worktree adds `KinoPubAppleClientTests`, deterministic auth-polling tests, rate-limit tests, and package-test CI; broad presentation/repository/navigation/optimistic-update coverage is still missing.

## Stack audit and update policy

The build infrastructure is current, but language mode and dependency hygiene need deliberate updates rather than a blanket upgrade:

- CI runs on `macos-26`; the audited local toolchain is Xcode 26.6 with Swift 6.3.3. Do not upgrade the toolchain merely for novelty.
- The application still compiles in Swift 5 language mode. Introduce strict-concurrency diagnostics early, but switch package/app language modes only after their isolation issues are fixed.
- Package manifests mix Swift tools versions 5.8 and 5.9. Align them to 5.9 immediately; move each to tools version 6.x together with that package's Swift 6 migration.
- `KeychainAccess` 4.2.2 is the latest tagged release. Keep it for now or replace its single use with a native Security-framework adapter when platform services are isolated.
- `SkeletonUI` tracks mutable `master` while lock files pin a May 2023 commit. The latest tagged version is 2.0.2 from May 2024 and contains a substantial rewrite. Prefer replacing it with a small local redaction/loading modifier; otherwise pin and test 2.0.2 explicitly. Never leave it branch-based.
- GitHub Actions are on current major versions. Pin the Xcode patch used by CI rather than selecting whichever `Xcode_26*` happens to be newest on the runner.
- The README claims Xcode 16+ while CI verifies only Xcode 26. Add minimum-toolchain and latest-toolchain lanes, or change the documented minimum.
- Dependabot's Swift entry points only at `/`, while package manifests live under `Packages/*`. Configure explicit package directories; separately monitor Xcode-project package references.
- The effective deployment target is macOS 13. Ventura is outside the normal security-maintenance window. Raising the target to macOS 14 is a product/support decision because it drops older Intel Macs. If macOS 13 remains supported, test it and document that compatibility does not imply OS security support.

Update rules:

1. Keep stack maintenance in small PRs separate from architecture or behavior changes.
2. Run minimum/latest toolchain CI before raising any declared minimum.
3. Pin direct dependencies to releases or exact revisions; do not use mutable branches.
4. Record dependency/toolchain decisions and review dates in this section.

Audit references:

- [Xcode 26.6 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes)
- [Swift 6.3 release announcement](https://www.swift.org/blog/swift-6.3-released/)
- [Swift 6.2 approachable-concurrency overview](https://www.swift.org/blog/swift-6.2-released/)
- [GitHub-hosted macOS 26 runner availability](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/)
- [Dependabot manifest-directory configuration](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file)
- [SkeletonUI releases](https://github.com/CSolanaM/SkeletonUI/releases)
- [KeychainAccess releases](https://github.com/kishikawakatsumi/KeychainAccess/releases)

## What is already good and should be preserved

- Most feature models are `@MainActor`, making their UI-state mutation intent explicit.
- The transport package has request/decoding/cache tests and abstracts `URLSession` for tests.
- API calls are generally wrapped by service protocols rather than called directly from every screen.
- `APIRequestGate` bounds 429 retries and shares server cooldown across callers.
- API response cache is opt-in, has account-isolation intent, and is cleared on logout.
- Device activation polling is bounded by expiry, responds to `authorization_pending`/`slow_down`, and owns a cancellable task.
- `EPGServiceImpl` is actor-isolated and uses streaming XML parsing rather than loading a large feed into memory.
- The code already uses constructor injection in several feature models. The refactor should standardize that direction, not replace it with a framework-heavy DI container.

---

# Findings

Severity labels:

- **P0**: correctness/security/data-race risk; address before broad modernization.
- **P1**: architectural boundary that materially blocks testing or change.
- **P2**: maintainability/UI-quality issue to address once boundaries exist.

## 1. The API abstraction leaks through every layer — P1

The intended stack is approximately `View -> Model -> app Service -> APIClient`, but it is not a true boundary:

- Presentation imports wire types directly (`MediaItem`, `PaginatedData`, `Bookmark`, `HistoryData`, `VerificationResponse`, `APIClientError`, etc.) from `KinoPubBackend`.
- `VideoContentService` returns backend response envelopes such as `PaginatedData<MediaItem>`, `SingleItemData<MediaItem>`, and `ArrayData<Bookmark>` instead of domain values.
- It accepts `MediaItemsFilter`, which is declared under `Views/Main/Filter/FilterModel.swift`. The data service therefore depends conceptually on a presentation type. This is an inverted dependency.
- `AuthModel` switches on transport-specific `APIClientError` to implement the application-level device authorization workflow.
- `AuthState` also understands `APIClientError` and `BackendError` to decide whether a session remains valid.
- `KinoPubUI` directly depends on `KinoPubBackend`, and public UI components accept backend `MediaItem` values. The reusable UI module is therefore coupled to one remote API schema.
- `KinopoiskExtrasService` lives in the backend package but is constructed directly inside `MediaItemModel`, bypassing the app composition root and any repository protocol.

**Consequence:** an API field/response change ripples into views and view models; feature tests must instantiate transport-shaped data; preview data uses backend mocks; replacing or combining data sources is expensive.

### Required boundary

Use this dependency direction:

```text
App composition root
       |
       +--> Presentation / Features ----> Domain contracts and values
       |                                  ^
       +--> Infrastructure adapters ------+
                    |
                    +--> KinoPub transport DTOs/client
                    +--> Kinopoisk transport
                    +--> local stores / file system / keychain
```

- **Transport** owns HTTP, URLs, headers, query/form encoding, DTOs, response envelopes, auth wire errors, and retry/cache policy.
- **Domain/Application** owns stable entities, pagination, filters, repository protocols, use-case/workflow rules, and typed application errors.
- **Infrastructure** maps DTOs/errors to domain values/errors and coordinates remote/local sources.
- **Presentation** owns screen state and user intents. It imports Domain, not Transport.
- **UI components** accept immutable display values, IDs, bindings, and actions. They import neither Domain repositories nor Transport.

## 2. `AppContext` is a service locator disguised as dependency injection — P1

Evidence:

- `AppContextProtocol` is a 15-protocol composition.
- `AppContext.shared` constructs transport, auth, downloads, persistence, notification, repositories/services, and shared state in one static initializer.
- The environment key defaults to the live `AppContext.shared`; a missing injection silently starts production behavior in a preview/test rather than failing visibly.
- There are many direct reads of `AppContext.shared` outside the composition root, including `HomeModel`, `HistoryModel`, `MediaItemModel`, `PlayerManager`, bookmark models, comments, downloads, and preview helpers.
- Several initializers appear injectable but default parameters point back to `AppContext.shared`, hiding dependencies and making tests accidentally integration tests.

**Consequence:** dependency graphs are implicit, lifetimes are unclear, preview/test isolation is weak, and models cannot be reasoned about from their initializer.

**Target:** one explicit `AppDependencies` composition root in the `App`, feature-scoped dependency bundles/factories, no live default environment value, and no `AppContext.shared` references below the root.

## 3. UI performs application and infrastructure work — P1

Concrete UI-layer violations:

- `CommentsView` locates the production service itself and executes request/filter/error policy in the `View`.
- `BookmarkActionSheet` performs bookmark/watchlist mutations, fetches two remote resources, applies optimistic state, ignores errors with `try?`, and dismisses after mutation.
- `StorageBreakdownView` and download views walk directories and read file metadata.
- `SearchModel` reads/writes `UserDefaults` and JSON directly.
- `AuthModel` owns `NSPasteboard` and `NSWorkspace`; those are platform adapters, not authorization state concerns.
- `ProfileModel` mutates `AppleLanguages`, calls `synchronize()`, and owns settings persistence policy.
- `MediaItemView` is 1,923 lines and includes navigation policy, domain formatting, download construction, episode continuation rules, Kinopoisk HTML cleanup, and many modal subfeatures.
- `PlayerManager`, located under `Views`, combines AVPlayer lifecycle, stream selection/fallback, download lookup, file existence checks, remote commands, persistence, watch-mark queueing, API recovery, audio/subtitle preferences, episode navigation, and 3D rendering.

**Rule after refactor:** views may format trivial display values and send intents. They must not know endpoints, repositories, filesystem layout, persistence keys, retry semantics, or cross-feature synchronization.

## 4. Multiple sources of truth and bypasses undermine optimistic state — P0/P1

- `MediaLibraryStore` intends to be the single source of truth, but Search's `BookmarkActionSheet` calls `UserActionsService` directly and does not update the store.
- Detail, bookmark, history, home, player, and search flows access the same state through different paths (`AppContext.shared`, environment object, service, local store).
- `MediaItemModel` repeatedly accesses `AppContext.shared.libraryState` despite already using injected dependencies for other work.
- Comments promise “single source of truth,” but responsibility spans backend DTO flags, `MediaLibraryStore`, `LocalWatchProgressStore`, `DownloadManager`, download database, and model-local optimistic state.
- The app injects `libraryState` in both `KinoPubAppleClientApp` and `RootView` preview/environment helpers, obscuring actual ownership.

**Consequence:** stale screens, failed rollbacks, duplicate requests, and behavior that varies by entry point.

**Target:** one `LibraryRepository`/`LibraryStore` actor for durable data and optimistic commands, plus one `@MainActor` observable projection for UI state. Every feature sends the same typed command path.

## 5. Concurrency safety is partly convention-based — P0

- `MediaLibraryStore` explicitly says it is not `@MainActor` and relies on callers being on main. The compiler cannot enforce this. It contains mutable dictionaries, synchronous disk writes, Combine sinks, and `@Published` properties.
- `DownloadManager` is a mutable `ObservableObject` with delegate callbacks and manually dispatches to main; its concurrency contract is not represented by actor isolation.
- `ImageCache` is declared `@unchecked Sendable`, mixes `NSCache`, lock-protected continuation lists, a serial queue, detached tasks, and non-Sendable AppKit image objects. This deserves stress tests or actor isolation, not a blanket assertion.
- Many models start unstructured `Task` instances in `init` or methods and do not retain/cancel them. Several comments say SwiftUI `.task` is “unreliable,” so work has been moved into model initialization. That disconnects work from view lifetime and can outlive navigation.
- Search uses Combine debounce plus manually managed tasks; cancellation/stale-result checks vary between pathways.
- App is compiled in Swift 5 mode, so stricter Swift 6 sendability/isolation diagnostics are deferred.
- `MediaLibraryStore.persist()` and local progress persistence perform synchronous file I/O from UI-driven mutation paths.

**Target:** UI-facing observable state is `@MainActor`; mutable persistence/network coordinators are actors; detached work has a documented Sendable boundary; all long-running feature tasks are owned and cancelled; Swift 6 diagnostics are enabled incrementally.

## 6. The transport layer is stringly typed and has unsafe construction — P1

- `Endpoint.method` is `String` and parameters are `[String: Any]`.
- Request building stringifies arbitrary values, making encoding semantics implicit.
- HTTP body/query behavior is selected by string comparisons and `forceSendAsGetParams`.
- `APIClient` force-unwraps the base URL.
- `RequestBuilder` force-unwraps URL components.
- Each request and response type is public, expanding the API surface.
- A concrete `APIClient` is injected into every service; there is no narrow transport protocol at the service/adapter seam.
- Decoder configuration is recreated and fixed to default behavior rather than injected once.
- Token refresh occurs at app startup but there is no centralized authenticated-request recovery path for an expired token/401 during a session.
- Plugins are synchronous mutable collaborators and their thread-safety contract is unspecified.
- Cache policy is encoded on endpoint types and `forceRefresh` leaks upward through service APIs and feature models.

**Target:** typed `HTTPMethod`, typed/Encodable query and body values, throwing URL construction, injected decoder/clock/sleeper/session, narrow `HTTPClient` protocol, auth interceptor with a single-flight refresh actor, and repository-owned freshness policy.

## 7. Remote schema doubles as the domain and display model — P1

- `Packages/KinoPubBackend/Models/MediaItem.swift` includes API decoding tolerance, display helpers, mock/skeleton construction, playback/domain computations, and force-unwrapped URL helpers.
- Backend models expose malformed-data fallbacks such as `TVChannel.id = 0`, empty titles/streams, and lossy decoding. Invalid wire values can become apparently valid domain objects.
- Person search mines comma-separated `cast` and `director` strings from returned movies because the API lacks person entities; this workaround is embedded in `SearchModel`.
- Filter behavior knows which server fields are silently ignored and applies client-side matching inside a presentation model/type.

**Target:** tolerate irregularities in DTO decoding, validate during DTO-to-domain mapping, reject/record unusable records, and expose normalized domain values (`Person`, `CatalogFilter`, `MediaSummary`, `MediaDetails`, `PlaybackSource`) to features.

## 8. Error handling is inconsistent and often silent — P0/P1

- Extensive `try?` converts transport, decoding, and persistence errors to empty arrays or missing UI sections.
- Search's bookmark sheet optimistically changes checkmarks but ignores mutation failures and does not revert.
- `AuthModel.handleError` ignores every non-`APIClientError` completely.
- `MediaLibraryStore` silently ignores persistence failures and bookmark refresh failures.
- Home drops failed shelves and can leave skeletons indefinitely without a typed partial-failure state.
- Global `ErrorHandler` encourages unrelated screens to share one error channel while other screens use local booleans/toasts.
- Several models combine “loading” booleans with skeleton domain objects, so loading, empty, stale, and error are not mutually exclusive.

**Target:** typed domain errors; explicit `Loadable<Value>`/screen-state enums; cancellation never presented as error; partial failures modeled intentionally; persistence errors logged and surfaced where recovery is actionable.

## 9. SwiftUI state/lifetime concerns — P1/P2

- `@StateObject` ownership is generally used, but model creation has hidden live singleton defaults and several models start network tasks in their initializers.
- Initial skeletons are fake `MediaItem` values. A placeholder can accidentally enter navigation/actions and forces `skeleton ?? false` checks across code.
- Some view-triggered tasks are wrapped in `Task {}` inside button handlers rather than going through one model intent and owned task lifecycle.
- View state and model state overlap (for example search query/results/committed/focus; detail navigation and item-model navigation helpers).
- Models subscribe manually to `AuthState` with Combine, creating repeated feature-specific auth gating. Session state belongs above repositories/use cases.
- Navigation is split across route values, `NavigationLinkProvider`, sidebar imperative mutations, and model-generated `(any Hashable)?` routes.

**Target:** explicit feature state machines; placeholders represented by loading state, not fake domain values; navigation destinations represented by one typed router; task ownership attached to screen/model lifetime.

## 10. UI package boundary is violated — P1

- `KinoPubUI` depends on `KinoPubBackend` because content components consume backend `MediaItem`.
- `ImageCache` performs HTTP, disk persistence, cache policy, and `UserDefaults` maintenance from the UI package.
- `HeroBackdrop` includes AVPlayer preview session management in the design-system module.

**Target:**

- `KinoPubUI`: design tokens and stateless/reusable SwiftUI components only.
- `ImagePipeline` infrastructure module: loading, HTTP validation, memory/disk cache, cancellation.
- `PlaybackUI`/app feature: AVKit bridge and preview playback coordination.
- UI input models such as `PosterCardModel` and `ContentRowModel`, or generic component inputs, prevent transport/domain coupling.

## 11. General maintainability smells — P2

- Very large files and types obscure boundaries and slow review.
- Typo/obsolete naming: `FilteDataServiceImpl`; apparently duplicate filter-data behavior already exists in `VideoContentService`.
- Numerous provider protocols contain mutable `get set` requirements although dependencies should be immutable.
- Mocks return empty/success values only, which makes failure/cancellation/race testing awkward.
- `String.localized` and many hard-coded strings coexist. Some user-visible strings are Russian literals (`"Свернуть"`, `"ЕЩЕ"`) or English accessibility labels and may bypass localization.
- `DateFormatter` is created during each `CommentRow` access rather than using `FormatStyle`/a reusable formatter.
- Forced dark mode compensates for incorrectly authored color assets instead of fixing semantic colors; this ignores the user's system appearance choice.
- Layout uses fixed dimensions (for example a 500-point search field and a 900×600 minimum window), requiring explicit accessibility/window-size verification.
- Previews often depend on live singleton defaults, reducing determinism.
- Package manifests only declare macOS despite the repository/product naming and historical multiplatform concepts. Either document macOS-only scope or restore explicit platform targets; do not retain ambiguous architecture.
- SwiftLint/format configuration exists, but architectural constraints and maximum type/file responsibilities are not enforced.

---

# Contradictions with published SwiftUI/Apple guidance

SwiftUI does **not** prescribe MVVM, Clean Architecture, or a repository pattern. The recommendation here is therefore not “Apple requires layers”; it is the minimum separation justified by this app's multiple remotes, local stores, optimistic updates, downloads, auth, and test needs.

1. **One explicit source of truth**
   - Apple describes app/model state as authoritative source-of-truth data and recommends `StateObject` for a view-owned observable reference.
   - Contradiction: bookmark/watch/progress/download truth is mutated through multiple bypasses; fake skeleton domain objects also represent loading state.
   - Sources:
     - [StateObject](https://developer.apple.com/documentation/swiftui/stateobject)
     - [Data Essentials in SwiftUI](https://developer.apple.com/videos/play/wwdc2020/10040/)
     - [Introduction to SwiftUI](https://developer.apple.com/videos/play/wwdc2020/10119/)

2. **Explicit data dependencies and previewability**
   - Apple recommends explicit view inputs when possible and uses the environment for intentionally shared dependencies.
   - Contradiction: `AppContext.shared` and production defaults hide dependencies; `CommentsView` locates its service; previews can silently use live services.
   - Source: [Structure your app for SwiftUI previews](https://developer.apple.com/videos/play/wwdc2020/10149/)

3. **State belongs at the lifetime that owns it**
   - Apple ties model lifetimes to views, scenes, and apps and identifies the app as the owner of app-global model data.
   - Contradiction: static construction and repeated singleton access blur app, feature, and view lifetime; initializer-started tasks can outlive the view.
   - Sources:
     - [App essentials in SwiftUI](https://developer.apple.com/videos/play/wwdc2020/10037/)
     - [Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)

4. **View-specific state stays in the view hierarchy**
   - Apple advises encapsulating view-specific data in the view hierarchy to keep views reusable.
   - Contradiction: some screen models include navigation/platform operations, while some views contain remote workflows and persistence. Ownership is divided by convenience rather than lifetime/concern.
   - Source: [Managing user interface state](https://developer.apple.com/documentation/swiftui/managing-user-interface-state)

5. **Structured concurrency and main-actor UI state**
   - Apple's concurrency material notes that SwiftUI's run loop is on the main actor and observable UI updates belong there.
   - Contradiction: `MediaLibraryStore` relies on a comment/caller discipline instead of compiler-enforced isolation; widespread unowned tasks and Swift 5 mode defer safety checks.
   - Sources:
     - [Discover concurrency in SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10019/)
     - [Swift concurrency: Update a sample app](https://developer.apple.com/videos/play/wwdc2021/10194/)

6. **Appearance and accessibility should adapt**
   - Apple's HIG describes Dark Mode as a systemwide appearance and recommends accessible interfaces/customization.
   - Contradiction: the app forces dark appearance to mask bad color assets, has hard-coded/fixed sizing, and has no meaningful UI/accessibility test coverage.
   - Sources:
     - [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)
     - [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
     - [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)

---

# Target architecture

## Modules

Start with logical targets/packages; do not create dozens of micro-packages.

1. **KinoPubDomain** — pure Swift/Foundation where necessary
   - Domain entities and validated IDs.
   - `CatalogFilter`, `Page`, `MediaSummary`, `MediaDetails`, `Person`, `Comment`, `Device`, `PlaybackSource`, `LibraryItemState`.
   - Repository protocols: `CatalogRepository`, `LibraryRepository`, `SessionRepository`, `DeviceRepository`, `PlaybackRepository`, `CommentsRepository`, `GuideRepository`.
   - Application errors and use cases/workflows.
   - No SwiftUI, AppKit, AVKit, URLSession, DTO, keychain, or file-layout knowledge.

2. **KinoPubTransport** (evolution/rename of `KinoPubBackend`)
   - `HTTPClient`, typed endpoint/request, URLSession adapter, DTOs, response envelopes, middleware, retry/rate limit, raw response cache.
   - No display helpers, skeletons, or domain/business logic.

3. **KinoPubData**
   - Repository implementations and DTO/domain mappers.
   - Actors for session refresh, library synchronization, persistence, and image pipeline.
   - Remote/local source coordination and freshness policy.

4. **KinoPubUI**
   - Semantic tokens and stateless components.
   - UI-specific immutable component models only.
   - No `KinoPubBackend`, networking, filesystem, UserDefaults, or business repositories.

5. **KinoPubApp / Features**
   - SwiftUI screens, `@MainActor` feature stores/models, typed navigation, AppKit/AVKit adapters.
   - Imports Domain and UI. It receives use cases/repositories via constructors/factories.

## Composition and injection

```swift
struct AppDependencies {
  let session: any SessionRepository
  let catalog: any CatalogRepository
  let library: any LibraryRepository
  let playback: any PlaybackRepository
  let comments: any CommentsRepository
  let guide: any GuideRepository
  let imagePipeline: any ImagePipeline
  let platform: PlatformServices
}
```

- Construct once in `KinoPubAppleClientApp.init` or a dedicated bootstrapper.
- Environment has no live default. In debug, use an unavailable/failing test value if SwiftUI requires a default.
- Root feature factories create feature models with only needed dependencies.
- Dependencies are `let`, not mutable provider properties.
- Use protocols at volatile/side-effect boundaries, not for every value/type.

## Feature state shape

Prefer mutually exclusive state over boolean combinations and fake data:

```swift
enum Loadable<Value> {
  case idle
  case loading(previous: Value?)
  case loaded(Value)
  case failed(DisplayError, previous: Value?)
}

@MainActor
final class SearchStore: ObservableObject {
  @Published private(set) var state: Loadable<SearchContent> = .idle
  @Published var query = ""
  func send(_ action: Action) async { /* orchestrate use cases */ }
}
```

Use this only where it clarifies behavior; small local UI state remains `@State`.

---

# Multiphase implementation plan

## Phase 0A — Toolchain and dependency hygiene

**Implementation status (current branch):**

- [x] Pin CI lanes to Xcode 26.6 and the documented minimum Xcode 16.4.
- [x] Verify the macOS 13 deployment floor in the minimum-toolchain lane and document the policy.
- [x] Standardize all local package manifests on Swift tools 5.9.
- [x] Run every package with targeted strict-concurrency diagnostics in CI; all are warning-free (including the `URLSessionDownloadTask` mock's explicit `@unchecked Sendable` conformance).
- [x] Replace `SkeletonUI` with a local native-redaction modifier and remove mutable branch references.
- [x] Configure Dependabot for all four package directories and document manual Xcode-reference monitoring.
- [x] Keep lockfiles reproducible (`KeychainAccess` 4.2.2 is the only remote package remaining).
- [x] Keep `plans*` ignored as explicitly requested for this repository; this intentionally supersedes the generic planning-document action below.

**Goal:** make builds reproducible and expose migration diagnostics without changing runtime behavior.

Actions:

- Pin CI to an explicit Xcode 26 patch and add a second lane for the documented minimum Xcode version. If the minimum lane cannot remain green, update the README requirement in the same PR.
- Change all local package manifests to Swift tools version 5.9. Do not adopt tools version 6.x in this phase.
- Enable strict-concurrency diagnostics incrementally in leaf packages: start with targeted checking, move to complete checking, and keep Swift 5 language mode until diagnostics are resolved.
- Replace `SkeletonUI` with a local loading/redaction modifier. If replacement is deferred, pin version 2.0.2, add visual regression coverage, and remove branch tracking.
- Configure Dependabot with explicit `Packages/KinoPubBackend`, `Packages/KinoPubKit`, `Packages/KinoPubLogging`, and `Packages/KinoPubUI` directories. Document manual monitoring for Xcode-project package references.
- Decide and document the macOS 13 support policy; add an oldest-supported-OS verification path if it remains supported.
- Commit this plan and future ADRs; planning documents must not be excluded by `.gitignore`.

Exit gate:

- Latest and declared-minimum toolchain builds are green.
- Dependency resolution is reproducible and no direct remote dependency tracks a mutable branch.
- Every package receives at least targeted concurrency diagnostics without introducing ignored warnings.
- The README, CI, package manifests, and deployment-target policy agree.

Rollback: each setting/dependency update is an independent PR; no feature behavior is coupled to this phase.

## Phase 0 — Freeze behavior with characterization tests

**Implementation status (current branch):**

- [x] Add the hosted application test target and shared scheme integration.
- [x] Make authorization polling deterministic with injected time/sleep.
- [x] Characterize polling success, pending, slow-down, transient failure, terminal failure, expiry replacement, and cancellation.
- [x] Make API 429 cooldown deterministic and test retry/cancellation.
- [x] Run all package tests in a CI matrix and run app tests in the native build job.
- [x] Record architecture metrics as CI summary/artifact.
- [x] Remove an existing download-flow test race/flaky temp-file dependency exposed by the matrix.
- [x] Add optimistic library mutation/revert, reconciliation, and persistence tests.
- [x] Add search stale-response and pagination tests.
- [x] Add player watch-mark ordering/coalescing tests.
- [x] Add local-progress persistence, replacement/deduplication, identity, threshold, and corruption tests.
- [x] Add sanitized catalog list/detail/malformed, bookmark, history, comments, media-links, and playback-source fixtures with contract-decoding tests.
- [x] Add stable accessibility selectors and contract assertions for Auth (loading/code/activation), Home (screen/loading), detail/bookmark picker, and player error. Image snapshots remain deliberately deferred: supplied visual references guide sanitized fixtures but are not committed as copyrighted baseline artwork.

**Goal:** create a safety net before moving boundaries.

Actions:

- Add an application test target that can `@testable import` feature code.
- Add fixture JSON captured/sanitized for:
  - catalog list/detail;
  - malformed optional fields;
  - auth device code, pending, slow-down, expired, success;
  - bookmark/watchlist/watched toggles;
  - history and comments;
  - media links/playback source refresh.
- Add characterization tests for current critical workflows:
  - activation poll cadence, cancellation, expiry replacement, slow-down increment, and transient recovery using injected clock/sleeper;
  - logout cache clearing and account isolation;
  - optimistic mutation success/failure/revert;
  - search stale response suppression and pagination;
  - player watch-mark coalescing/order;
  - local progress merge/deduplication;
  - API 429 gate and cancellation.
- Add snapshot/accessibility tests for auth, home, search, detail, empty/error/loading states, bookmark sheet, and player error.
- Add build/test CI matrix for all four packages and app target on the pinned latest toolchain; keep minimum-toolchain compatibility as a separate lane.
- Record architecture metrics in CI: forbidden imports, `AppContext.shared` references outside bootstrap, files >500 lines, force unwraps in production transport.
- Capture strict-concurrency warning counts per package so modernization does not silently add new debt; warnings become blocking only after each package's baseline is cleaned.

Exit gate:

- Current app build remains green.
- Existing package suite baseline is 117 tests (86 Backend, 24 Kit, 3 Logging, 4 UI) and remains green.
- Critical workflow tests demonstrate at least one failure-path and cancellation-path each.
- No refactor starts until auth polling and optimistic mutation tests are deterministic (no real sleeps/network).

Rollback: test-only phase; no production behavior change.

## Phase 1 — Harden transport without changing feature APIs

**Implementation status (current branch):**

- [x] Add typed `HTTPMethod`, `HTTPRequest`, and deterministic `HTTPParameters`; migrate existing endpoints without changing service call sites.
- [x] Remove production URL-construction force unwraps; invalid base URLs now fail requests with `APIClientError.invalidRequest`.
- [x] Inject `JSONDecoder`, clock/sleeper, and `URLSessionProtocol`; expose the narrow `HTTPClient` seam.
- [x] Add transport error categories while retaining legacy error cases for unmigrated feature APIs.
- [x] Add an opt-in single-flight credential-refresh coordinator; eligible safe requests replay once after 401 and rerun auth plugins.
- [x] Keep the shared 429 gate cancellation-aware and make Retry-After date parsing use the injected clock.
- [x] Version cache keys by transport schema.
- [x] Redact authorization headers and known query/form secrets before plugin/cURL logging.
- [x] Add invalid-base-URL, 401 replay, and logging-redaction characterization tests.
- [ ] Wire the app's access-token refresh implementation into `CredentialRefreshing`, add concurrent-refresh-collapse/fairness coverage, inject jitter, and add authenticated account cache partitioning.

**Goal:** make networking safe and injectable while preserving service call sites.

Actions:

- Introduce `HTTPMethod` and a typed `HTTPRequest`/`Endpoint<Response>` representation.
- Replace `[String: Any]` with deterministic typed query/form values.
- Make base URL and URLComponents construction throwing; remove production force unwraps.
- Inject `JSONDecoder`, clock, sleeper, random/jitter source, and `URLSessionProtocol`/`HTTPTransport`.
- Make `APIClient` conform to a narrow `HTTPClient` protocol and preferably an actor or immutable Sendable value around an actor-owned pipeline.
- Define one error taxonomy:
  - transport/offline/timeout;
  - invalid request;
  - HTTP status with sanitized metadata;
  - backend-declared error;
  - decoding/schema mismatch;
  - cancellation.
- Add a single-flight credential refresh actor. On eligible 401, refresh once and replay safe requests once; never loop and never blindly replay unsafe mutations unless endpoint policy permits it.
- Preserve shared 429 cooldown, but inject time/sleep and test fairness/cancellation.
- Make cache keys include API version, authenticated account partition (or guarantee only non-personal data), and decoder/schema version. Keep logout invalidation.
- Mark endpoint/request structs `internal` unless genuinely public.
- Redact authorization/body secrets in all plugin/logging paths by construction.

Exit gate:

- All transport tests pass with typed endpoint parity tests.
- Invalid base URLs return errors rather than crash.
- 401 refresh and concurrent refresh collapse are tested.
- No bearer token/client secret appears in captured logs.
- Existing app services compile unchanged through an adapter.

Rollback: retain old `APIClient` behind the same protocol until parity is proven; switch construction with one composition-root flag.

## Phase 2 — Introduce Domain and repository adapters as a vertical slice

**Goal:** prove the boundary on one low-risk feature before broad migration.

Recommended slice: **Comments** (small read-only surface), then **Catalog/Search**.

Actions:

- Create `KinoPubDomain` and `KinoPubData` targets.
- Define domain `Comment`, `UserSummary`, and `CommentsRepository`.
- Implement DTO-to-domain validation/mapping in Data.
- Add `CommentsStore` with explicit loading/empty/error/loaded states.
- Inject it into `CommentsView`; remove `AppContext.shared`, backend import, and network method from the view.
- Convert `CommentRow` to accept a display model and use `Date.FormatStyle`.
- Repeat for catalog summaries/search:
  - domain `MediaSummary`, `Page`, `CatalogQuery`, `PersonSearchResult`;
  - repository hides request names, response envelopes, ignored server-filter behavior, caching, and pagination DTOs;
  - move cast/director workaround and filter fallback into repository/application policy;
  - Search presentation no longer imports `KinoPubBackend`.

Exit gate:

- Comments and Search feature code imports Domain/UI only.
- DTO fixture changes do not require view changes.
- Both features have deterministic success/empty/partial/error/cancellation tests.
- No behavior or visual regression in snapshots.

Rollback: old app services remain available for unmigrated features; migrate feature by feature.

## Phase 3 — Remove service locator and establish explicit ownership

**Goal:** make the dependency graph visible and testable.

Actions:

- Replace `AppContextProtocol` composition with immutable `AppDependencies` plus small feature factories.
- Create dependencies once in app bootstrap.
- Remove live singleton default from `EnvironmentKey`.
- Replace every `AppContext.shared` below app/bootstrap in this order:
  1. comments/search;
  2. bookmark/history/home;
  3. media detail;
  4. downloads/storage;
  5. player;
  6. previews.
- Replace defaulted singleton initializer parameters with required dependencies.
- Inject platform capabilities (`OpenURL`, clipboard, notifications), persistence, clocks, and file metadata readers through narrow interfaces.
- Ensure exactly one app-owned library UI projection is injected once.
- Delete provider-protocol boilerplate and mutable `get set` requirements after last use.

Exit gate:

- `rg 'AppContext\.shared'` returns only bootstrap (or zero if type is removed).
- Every feature model can be created with a pure in-memory dependency set.
- Every preview uses explicit fixtures and cannot make a production network request.
- Dependency lifecycle is documented: app, session, feature, transient view.

Rollback: migrate and merge one feature at a time; temporary adapters can bridge `AppDependencies` to old service protocols.

## Phase 4 — Unify library, persistence, and optimistic commands

**Goal:** enforce one route for bookmark/watch/watchlist/progress state.

Actions:

- Split current `MediaLibraryStore` responsibilities:
  - `LibraryRepository` actor: authoritative local state, persistence, remote synchronization, optimistic command journal.
  - `LibraryViewState` (`@MainActor`, observable): UI projection/subscription.
  - download status adapter and watch-progress repository remain separate sources joined by a use case/read model.
- Define typed commands with IDs/idempotency and rollback information.
- Route Search bookmark sheet, detail, bookmark lists, history, home, and player through the same command API.
- Serialize conflicting mutations per item; coalesce repeated toggles; handle cancellation after remote commit safely.
- Move disk reads/writes off the main actor and use atomic versioned persistence with corruption recovery.
- Replace silent persistence failures with structured logs/metrics and a recoverable state.
- Partition user-specific persisted state by account and clear/switch atomically on logout/account change.
- Add reconciliation tests for stale remote data, in-flight toggles, relaunch, offline queue, and failed rollback.

Exit gate:

- No feature directly calls bookmark/watch mutation endpoints.
- Search and detail always render identical state for the same item.
- Concurrency stress tests pass under Thread Sanitizer.
- Main Thread Checker shows no synchronous persistence in interactive mutation paths.

Rollback: command adapter initially delegates to existing `MediaLibraryStore`; switch individual intents after tests.

## Phase 5 — Refactor feature presentation and giant views

**Goal:** reduce UI responsibility without creating a “view model for every row.”

### Media detail

Split `MediaItemView.swift` into focused files/components:

- `MediaDetailsScreen` — composition only.
- `MediaHeroSection`.
- `MediaActionsSection`.
- `EpisodeSection` / `EpisodeRow`.
- `TrailersSection`, `StillsSection`.
- `CastCrewSection`.
- `FactsSection`, `ReviewsSection`, `CommentsSection`.
- `RelatedMediaSection`.
- `MediaMetadataSection`.
- `KinopoiskTextSanitizer` outside UI.

Split `MediaItemModel` into use cases/read models rather than one larger model:

- details loader;
- recommendations loader;
- extras loader;
- library command handler;
- download command handler.

Represent optional supplementary sections as independently loadable state so one failure does not trigger a global error or indefinite skeleton.

### Search

- Keep focus and `committed` as local view state.
- Move recents persistence to `RecentSearchRepository`.
- Move query debounce/cancellation into one async sequence/task owned by `SearchStore`; remove duplicate Combine + task paths.
- Move bookmark action behavior to shared library commands.
- Model partial scope failures explicitly instead of converting all errors to empty arrays.

### Downloads/storage

- Move filesystem traversal/size computation to a `StorageUsageRepository` actor.
- Views receive `StorageUsage` snapshots and send clear/delete intents.

### Auth

- Move activation polling to a `DeviceAuthorizationCoordinator` actor with injected clock/sleeper.
- Model states: idle, requestingCode, awaitingApproval, slowingDown, authorized, expired/restarting, failed.
- `AuthStore` maps coordinator state to UI.
- Clipboard/open URL are injected platform actions.
- Cancel polling on feature/session teardown and ensure only one poll generation exists.

Exit gate:

- No production SwiftUI screen file >500 lines; target <300 where practical.
- Views contain no repository/network/filesystem/UserDefaults calls.
- Feature stores expose state + intents and are `@MainActor`.
- UI snapshots and VoiceOver labels cover every state.

Rollback: extract render-only subviews first, then move behavior behind tested stores.

## Phase 6 — Isolate playback and media infrastructure

**Goal:** separate AVKit presentation from playback/domain/network recovery.

Actions:

- Split `PlayerManager` into:
  - `PlaybackSession` actor/state machine — item transitions, recovery ladder, watch marks.
  - `PlaybackSourceRepository` — local-vs-remote source resolution and signed URL refresh.
  - `WatchProgressSync` actor — ordered/coalesced marks and retry policy.
  - `MediaPreferenceStore` — audio/subtitle/quality/3D preferences.
  - `AVPlayerController` (`@MainActor`) — AVFoundation object lifecycle and observations.
  - `RemoteCommandController` and display-sleep/window-chrome adapters.
  - `ThreeDVideoComposition` pure media utility with focused tests.
- Move file existence/database lookup out of AVPlayer construction.
- Represent playback as an explicit state machine: preparing, ready, playing, paused, buffering, recovering, failed, finished.
- Ensure observers, notifications, remote command targets, and tasks are removed exactly once on teardown.
- Inject playback source policy; no `AppContext.shared` in player.
- Keep native `NSViewRepresentable` bridge in app/platform UI, not generic design system.

Exit gate:

- Player state-machine tests run without AVPlayer/network.
- AVPlayer adapter tests verify observer teardown.
- Signed-URL fallback, local-file disappearance, episode transitions, resume, and final watch mark are covered.
- No watch-mark can be sent out of order.

Rollback: façade preserves current `PlayerManager` initializer while internals migrate component by component.

## Phase 7 — Clean the UI module and image pipeline

**Goal:** restore one-way package dependencies.

Actions:

- Replace backend-model parameters in `KinoPubUI` with generic/content display models.
- Move `ImageCache`/loading into `KinoPubImagePipeline` or Data infrastructure.
- Prefer an actor-based in-flight request registry and disk store; avoid `@unchecked Sendable` unless proven unavoidable and documented.
- Inject URLSession, file store, clock, cache limits, and maintenance metadata.
- Return typed image-load outcomes internally; negative-cache only appropriate status codes and honor cancellation.
- Move video preview playback coordination out of `KinoPubUI` into playback/app UI.
- Make `KinoPubUI` dependency graph: SwiftUI/AppKit as needed + design-only libraries, no Backend/Data.

Exit gate:

- `KinoPubUI/Package.swift` has no `KinoPubBackend` dependency.
- No `URLSession`, filesystem persistence, or UserDefaults in `KinoPubUI`.
- Image coalescing, cancellation, disk expiry, corruption, HTTP status, and memory-warning behavior are tested.

Rollback: add compatibility initializers in the app target, not in `KinoPubUI`, during migration.

## Phase 8 — Complete Swift 6/concurrency migration

**Goal:** finish the diagnostic work started in Phase 0A and have the compiler enforce contracts currently held in comments.

Actions:

- Require complete strict-concurrency checking with a zero-warning baseline; fix leaf packages before the app.
- Evaluate Swift 6.2+ approachable-concurrency settings explicitly rather than accepting new-project defaults accidentally. Record default actor isolation per module; do not apply `MainActor` by default to Domain/Data modules without justification.
- Mark UI observable models and AV/AppKit adapters `@MainActor`.
- Convert shared mutable coordinators/stores to actors.
- Audit every `@unchecked Sendable`; eliminate or justify with invariant + stress test.
- Replace `DispatchQueue.main.async` with actor hops where possible.
- Replace nanosecond sleeps with `Duration` and injected clocks in logic.
- Retain task handles for long-lived operations; cancel on replacement/deinit/session end.
- Avoid `Task.detached` unless work and captures are genuinely Sendable and independent.
- Switch Swift language mode one package at a time, then app.

Exit gate:

- Complete build in Swift 6 mode with strict concurrency and no suppressed warnings.
- Thread Sanitizer passes critical state/download/image/auth scenarios.
- No comments claim thread safety that the type system does not enforce.

Rollback: language-mode changes are per target; never combine them with feature behavior changes.

## Phase 9 — UI quality, localization, accessibility, and adaptive appearance

**Goal:** correct UI abstraction and platform contradictions after state/data are testable.

Actions:

- Fix semantic color assets for both appearances; stop forcing dark mode unless “dark-only product” is an explicit, documented requirement validated with HIG/accessibility review.
- Centralize design tokens but use semantic system colors/materials where appropriate.
- Audit all user-visible/accessibility strings; migrate hard-coded Russian/English text to String Catalogs.
- Use locale-aware `FormatStyle` for dates, numbers, durations, and byte counts.
- Test Dynamic Type/accessibility text sizes even on macOS, VoiceOver labels/order, Reduce Motion, Increase Contrast, Differentiate Without Color, keyboard navigation, and focus.
- Replace fixed 500-point search sizing with adaptive min/ideal/max behavior.
- Verify minimum window size against zoom/accessibility needs.
- Add loading/empty/error/offline states with actionable retry and stable layout.
- Ensure color is not the sole signal for ratings/status.

Exit gate:

- Appearance snapshots for light/dark (or documented dark-only), increased contrast, reduced motion, and representative text sizes.
- Accessibility Inspector audit has no unlabeled controls in critical flows.
- All shipped locales pass missing-key and truncation checks.

Rollback: token/asset changes are independently revertible and protected by snapshots.

## Phase 10 — Delete bridges and enforce architecture

Actions:

- Delete old app service wrappers once all repositories have migrated.
- Rename `KinoPubBackend` to `KinoPubTransport` if public compatibility permits; otherwise document its transport-only role.
- Delete backend display helpers/skeleton mocks and old singleton context.
- Add CI architecture checks:
  - Features cannot import Transport/Data implementation modules.
  - UI cannot import Domain/Transport/Data.
  - Domain cannot import SwiftUI/AppKit/AVKit/URLSession.
  - `AppContext.shared`, direct `UserDefaults.standard`, and `URLSession.shared` are forbidden outside approved adapters.
  - Production force unwraps in transport fail lint.
- Document module ownership and dependency diagram in `docs/architecture.md`.
- Add an ADR for repository boundaries, state ownership, and error policy.

Exit gate / definition of done:

- Dependency graph matches the target diagram.
- All feature screens have deterministic fixture previews.
- Critical workflows have success, failure, cancellation, stale-response, and offline tests.
- Swift 6 build, package tests, app tests, snapshots, Thread Sanitizer, and accessibility checks pass in CI.
- No production singleton service lookup outside bootstrap.
- No transport DTO/response envelope reaches presentation.
- No UI module performs network or persistence work.
- One command path owns all library mutations.

---

# Suggested delivery order

Use small vertical pull requests, each preserving behavior:

1. Toolchain reproducibility, dependency hygiene, and initial concurrency diagnostics (Phase 0A).
2. Test clocks/sleepers + auth polling characterization.
3. Comments vertical slice (Domain/Data/store/view).
4. Typed transport primitives behind compatibility API.
5. Search vertical slice + recents repository.
6. Explicit `AppDependencies`; remove service location feature-by-feature.
7. Shared library command path, starting with Search bookmark sheet.
8. Catalog/Home/History/Bookmarks domain migration.
9. Media detail split and supplementary loaders.
10. Downloads/storage actor.
11. Playback split.
12. UI package/image pipeline cleanup.
13. Complete Swift 6 migration.
14. Appearance/localization/accessibility pass.
15. Bridge deletion and architecture enforcement.

Each PR must include:

- behavior statement and non-goals;
- before/after dependency diagram for affected code;
- tests for success + one failure + cancellation/race where async;
- build/test evidence;
- rollback note;
- no unrelated formatting churn.

# Risk register

- **API quirks get lost during mapping.** Preserve sanitized fixtures and parity tests before moving DTOs.
- **Optimistic behavior regresses.** Move one command at a time through an adapter and test success/failure/relaunch.
- **Task cancellation changes loading behavior.** Characterize current behavior and make state transitions explicit.
- **Player refactor destabilizes playback.** Keep an AVPlayer façade and migrate source selection/watch marks before UI chrome.
- **Too many protocols/types add ceremony.** Abstract only side-effect/volatility boundaries; keep domain values concrete.
- **Module split slows builds.** Begin with 3 core boundaries (Domain, Transport, Data); split playback/image only when justified.
- **Dark-mode visual regressions.** Snapshot semantic tokens before correcting assets and test both appearances.
- **Swift 6 migration explodes scope.** Turn on diagnostics per leaf package and never mix mode conversion with feature changes.

# Immediate first milestone

Status as of the 2026-08-04 audit: the worktree already contains the application test target, deterministic auth-polling work, 429 gate tests, package-test CI, and architecture metrics. Validate and commit those changes before expanding scope.

A safe first milestone should deliver all of the following together:

- pinned latest Xcode CI plus a verified minimum-toolchain lane, or a corrected README minimum;
- aligned Swift tools version 5.9 manifests and initial strict-concurrency diagnostics;
- corrected Dependabot package directories;
- no mutable branch dependency (`SkeletonUI` replaced or explicitly pinned and tested);
- application test target;
- injected clock/sleeper for device activation polling and 429 cooldown;
- complete activation polling tests;
- Comments domain/repository/store vertical slice;
- immutable app dependency container with Comments supplied explicitly;
- architecture CI rule preventing `AppContext.shared` and `KinoPubBackend` from returning to Comments;
- unchanged UI snapshots and green app/package builds on supported toolchains.

This milestone proves both reproducible stack maintenance and the target architecture without touching high-risk playback or the library synchronization core.
