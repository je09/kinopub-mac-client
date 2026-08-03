# Changelog

## [2.0.0](https://github.com/je09/kinopub-mac-client/compare/v1.5.0...v2.0.0) (2026-08-03)


### ⚠ BREAKING CHANGES

* iOS and iPadOS are no longer supported.

### ✨ Features

* AltStore/SideStore source for one-tap install + auto-updates ([d302bc4](https://github.com/je09/kinopub-mac-client/commit/d302bc49a39e82ad76dedf01aae4a86539d821ba))
* **altstore:** richer source metadata ([#15](https://github.com/je09/kinopub-mac-client/issues/15)) ([1bd4c86](https://github.com/je09/kinopub-mac-client/commit/1bd4c86333096d7b31f194a39c2a208dc8d352aa))
* **auth:** refine device activation flow ([9563fd9](https://github.com/je09/kinopub-mac-client/commit/9563fd9fe88cfeb08c04b4ca3c3659f0efe71cd6))
* **chrome:** keep heroes behind toolbar glass ([bee91c8](https://github.com/je09/kinopub-mac-client/commit/bee91c817ee542ca86b9c762d54697d3bd903a2a))
* Continue Watching polish + unified watch-status (tested) + lazy lists ([16763d4](https://github.com/je09/kinopub-mac-client/commit/16763d481c18c550666f3d5611c1122a6953d3a3))
* **details:** add Apple TV-style previews ([38bc21e](https://github.com/je09/kinopub-mac-client/commit/38bc21ee9650c6e151b7871cc4e85e00be02b680))
* **details:** extend hero across window ([918afba](https://github.com/je09/kinopub-mac-client/commit/918afba6e65d6bbb459f0a5b0f48be925cf88f22))
* GitHub Pages redirector for one-tap AltStore/SideStore source links ([ec616da](https://github.com/je09/kinopub-mac-client/commit/ec616da6e52e052630395ad8307733fda4e0275a))
* **home:** delay trailer previews ([f400b0f](https://github.com/je09/kinopub-mac-client/commit/f400b0f63313cfc62bec4bb840813a161cbf1498))
* **home:** load muted trailer previews ([9b370d0](https://github.com/je09/kinopub-mac-client/commit/9b370d06673a08765c7260813f5e00ec18b1ce49))
* improve episode playback navigation ([437b0fa](https://github.com/je09/kinopub-mac-client/commit/437b0fad977921b8874fb5bfe3ce35ccc82a6989))
* **l10n:** expand macOS interface strings ([e6b06f9](https://github.com/je09/kinopub-mac-client/commit/e6b06f94e36e33ff05125d84e753daa2c8ec1f2e))
* macOS fixes, DMG installer, rename to dungeon-master-xx, device screenshots ([7b3377a](https://github.com/je09/kinopub-mac-client/commit/7b3377a774c8e4bd250a4e135dd3fa5beed0804f))
* make app macOS-only ([b061429](https://github.com/je09/kinopub-mac-client/commit/b0614293f5eefb5573c8e17bc958eb5379f08745))
* playback, search, collections & cross-platform (macOS/iPad) improvements ([9a25b0c](https://github.com/je09/kinopub-mac-client/commit/9a25b0c1c4adb5bd18edf573428165c618217f9f))
* **player:** add smooth gesture seeking ([cda08b3](https://github.com/je09/kinopub-mac-client/commit/cda08b3ad9d778f6f083b1b3ae7d7408b10301d7))
* **player:** add stream quality controls ([55c4d56](https://github.com/je09/kinopub-mac-client/commit/55c4d56171e59b251e6be917bb9d1de218fc02cf))
* refine macOS desktop experience ([a10775e](https://github.com/je09/kinopub-mac-client/commit/a10775eb172d35d74f155c49ec5349abe11b6207))
* **release:** build & attach macOS app artifact ([a19ceec](https://github.com/je09/kinopub-mac-client/commit/a19ceec44d54f2ec2d77814a800af1934e12a701))
* **settings:** add About section (source code, report a problem, install guide) ([b3771e2](https://github.com/je09/kinopub-mac-client/commit/b3771e250f6abbaf426d40c200759318988bb2b3))
* **sidebar:** add Music-style customization ([482d1f2](https://github.com/je09/kinopub-mac-client/commit/482d1f218a494a9fe49f067a8ed359fd94231755))
* **sidebar:** personalize macOS navigation ([948784e](https://github.com/je09/kinopub-mac-client/commit/948784e280c97dbaf502a5898cf3e28b3de87584))
* **ui:** mirror Apple TV layout ([e1ce0a1](https://github.com/je09/kinopub-mac-client/commit/e1ce0a170fc6fdbd1508010da39c127c60e5a367))
* **ui:** respect system glass appearance ([e952eb8](https://github.com/je09/kinopub-mac-client/commit/e952eb89ce2478afcb762e9934aaaa148c078260))


### 🐛 Fixes

* **altstore:** declare screenshot width/height (AltStore requires size for iPad) ([#13](https://github.com/je09/kinopub-mac-client/issues/13)) ([e00065d](https://github.com/je09/kinopub-mac-client/commit/e00065d9a3ab8bf3a707b497aec23a82dfd51467))
* **altstore:** include legacy source fields for older AltStore compatibility ([f3a1a7b](https://github.com/je09/kinopub-mac-client/commit/f3a1a7ba7c4bab0e6428c415d0f8a1b4f1155f98))
* **api:** coordinate rate-limit cooldowns ([34fa4f2](https://github.com/je09/kinopub-mac-client/commit/34fa4f2ed707d13c66866ae1926e073235e7549d))
* **api:** validate responses and cache clearing ([72c3b56](https://github.com/je09/kinopub-mac-client/commit/72c3b56ea475d3c2f7129690778e22cbc152c628))
* **build:** stabilize release configuration ([acd83e4](https://github.com/je09/kinopub-mac-client/commit/acd83e40fa98b53b77b9c36f82273bd1378c9141))
* **device:** hide local computer name ([a7e591d](https://github.com/je09/kinopub-mac-client/commit/a7e591d508f653a53875e6e493aaf1368c139528))
* **hero:** keep detail text readable ([e6eb05c](https://github.com/je09/kinopub-mac-client/commit/e6eb05c9090f3c0518d3f03da76a86539ae82d7b))
* **hero:** preserve trailer framing ([55d3f69](https://github.com/je09/kinopub-mac-client/commit/55d3f691c6a2234f573b09af60cb5ff53a592e25))
* **hero:** restore full-width text scrims ([4e4e6bd](https://github.com/je09/kinopub-mac-client/commit/4e4e6bd3bedae2f2422b7e41cc45d8c682a2b308))
* **hero:** widen trailer previews ([f11590a](https://github.com/je09/kinopub-mac-client/commit/f11590a5ac40960853e19603d34d402650ef9d98))
* **home:** make featured carousel interactive ([2d636fc](https://github.com/je09/kinopub-mac-client/commit/2d636fcedd85c6494ea70e5b97c89898ce699c27))
* **macos:** add macOS app icon (idiom: mac) so the .app isn't blank ([dde14d4](https://github.com/je09/kinopub-mac-client/commit/dde14d4b0d425bae0ccd70aec3f78707471b3494))
* make device activation polling resilient ([3f93658](https://github.com/je09/kinopub-mac-client/commit/3f936580de49f3c9201b2f186464a0055f919a82))
* **navigation:** isolate screen scroll positions ([4fe24e2](https://github.com/je09/kinopub-mac-client/commit/4fe24e28902ddcfdfe96a695640b2362d53e304b))
* **player:** activate default subtitles ([b3f88ff](https://github.com/je09/kinopub-mac-client/commit/b3f88ff0d3995bca40313ab3250997c9dafb3f0c))
* **player:** manage active playback lifecycle ([ab44aab](https://github.com/je09/kinopub-mac-client/commit/ab44aab4a13357decbab5d6c98f12eaaa4e25e63))
* **player:** return after final playback ([41f3f75](https://github.com/je09/kinopub-mac-client/commit/41f3f7593491c9b6b5157180817786e2135a4689))
* **player:** stabilize native macOS playback ([9e8a8b2](https://github.com/je09/kinopub-mac-client/commit/9e8a8b28db5043f157110741ac2fd5c5437b31ce))
* **player:** stabilize PiP handoff ([5ad8afe](https://github.com/je09/kinopub-mac-client/commit/5ad8afe971962709f99472f0de7d717b4ade59e5))
* **player:** stabilize playback and window chrome ([c1d3309](https://github.com/je09/kinopub-mac-client/commit/c1d33093a92048f515b02edd8853ea4f2f33b054))
* **player:** sync window chrome with controls ([24cfa2e](https://github.com/je09/kinopub-mac-client/commit/24cfa2e00aa763995c55c4da38330b8d0e55aeda))
* render clean plain-text What's New in AltStore source (strip Markdown) ([e76b783](https://github.com/je09/kinopub-mac-client/commit/e76b783c9e68ecab5809e640a434eab9f51721dc))
* **security:** restore sandbox protections ([b5a7166](https://github.com/je09/kinopub-mac-client/commit/b5a716661382d2743fffb21a0151022372a70010))
* **state:** discard stale async responses ([7cbf96b](https://github.com/je09/kinopub-mac-client/commit/7cbf96b3d03c2642e112c4452f33a3780faf5125))
* stop advertising 3D video in the README (it's disabled behind a flag) ([#18](https://github.com/je09/kinopub-mac-client/issues/18)) ([500c50a](https://github.com/je09/kinopub-mac-client/commit/500c50a77577adea4fd805d572fae5acaf2e81f4))
* sync app version across project, settings and releases ([d2d947c](https://github.com/je09/kinopub-mac-client/commit/d2d947ca0035eab8e3748072050b1426512c9a98))
* **ui:** improve native control semantics ([a14c756](https://github.com/je09/kinopub-mac-client/commit/a14c756919730c134c8e4b0883b48cbf462c3531))
* **ui:** stabilize previews and hero updates ([ab88a50](https://github.com/je09/kinopub-mac-client/commit/ab88a50c7eb41388045b90cc4280e1d7c894a774))
* **ui:** use semantic text colors ([e882343](https://github.com/je09/kinopub-mac-client/commit/e8823437667414e49daffad94bb8ecef2d9c98be))


### ⚡ Performance

* **cache:** avoid redundant image requests ([24ef3dd](https://github.com/je09/kinopub-mac-client/commit/24ef3ddf437c5bd941b428358c6101abe7eacd24))
* **media:** bound cache and serialize downloads ([338e13d](https://github.com/je09/kinopub-mac-client/commit/338e13d8e691e3eaaebcaf0b391d17b3db1c8108))
* **player:** buffer remote playback ([a3365e2](https://github.com/je09/kinopub-mac-client/commit/a3365e28d41e52dba073c10d078da015bff215b3))


### 📝 Docs

* add app screenshots gallery to README; bump actions/checkout to v5 ([f1a82de](https://github.com/je09/kinopub-mac-client/commit/f1a82decf0427eef0c4997713dd7ae09c8dc47ed))
* add CLAUDE.md dev/architecture guide ([#24](https://github.com/je09/kinopub-mac-client/issues/24)) ([d60388a](https://github.com/je09/kinopub-mac-client/commit/d60388a5d3b73fd7ce2ed1880291d1cadbeda2a9))
* AltStore button uses altstore-classic:// scheme (avoid AltStore PAL) ([#20](https://github.com/je09/kinopub-mac-client/issues/20)) ([2b90eab](https://github.com/je09/kinopub-mac-client/commit/2b90eabc44fc834ce78d90d5cc91d4e6a1feec06))
* AltStore/SideStore install banner with badges in README ([dc7c8aa](https://github.com/je09/kinopub-mac-client/commit/dc7c8aadd33d99760b8f2ff6fc1bfff2dba749de))
* landing page with AltStore/SideStore buttons + screenshots ([099f3e5](https://github.com/je09/kinopub-mac-client/commit/099f3e5a6254eaef01e59f1536c40b24bb078cbd))
* top AltStore version badge + use self-hosted Pages redirector for source buttons ([40aba5a](https://github.com/je09/kinopub-mac-client/commit/40aba5aa7fadac0f2635d9f150b1405db0e8ba8f))
* update macOS project links ([e799276](https://github.com/je09/kinopub-mac-client/commit/e799276124427567a62a0b6db086581d3d4bf832))

## [1.5.0](https://github.com/dungeon-master-xx/kinopub-apple-client/compare/v1.4.2...v1.5.0) (2026-06-28)


### ✨ Features

* Continue Watching polish + unified watch-status (tested) + lazy lists ([16763d4](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/16763d481c18c550666f3d5611c1122a6953d3a3))

## [1.4.2](https://github.com/dungeon-master-xx/kinopub-apple-client/compare/v1.4.1...v1.4.2) (2026-06-28)


### 📝 Docs

* AltStore button uses altstore-classic:// scheme (avoid AltStore PAL) ([#20](https://github.com/dungeon-master-xx/kinopub-apple-client/issues/20)) ([2b90eab](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/2b90eabc44fc834ce78d90d5cc91d4e6a1feec06))

## [1.4.1](https://github.com/dungeon-master-xx/kinopub-apple-client/compare/v1.4.0...v1.4.1) (2026-06-28)


### 🐛 Fixes

* stop advertising 3D video in the README (it's disabled behind a flag) ([#18](https://github.com/dungeon-master-xx/kinopub-apple-client/issues/18)) ([500c50a](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/500c50a77577adea4fd805d572fae5acaf2e81f4))

## [1.4.0](https://github.com/dungeon-master-xx/kinopub-apple-client/compare/v1.3.0...v1.4.0) (2026-06-28)


### ✨ Features

* **altstore:** richer source metadata ([#15](https://github.com/dungeon-master-xx/kinopub-apple-client/issues/15)) ([1bd4c86](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/1bd4c86333096d7b31f194a39c2a208dc8d352aa))


### 🐛 Fixes

* **altstore:** declare screenshot width/height (AltStore requires size for iPad) ([#13](https://github.com/dungeon-master-xx/kinopub-apple-client/issues/13)) ([e00065d](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/e00065d9a3ab8bf3a707b497aec23a82dfd51467))

## [1.3.0](https://github.com/dungeon-master-xx/kinopub-apple-client/compare/v1.2.0...v1.3.0) (2026-06-28)


### ✨ Features

* macOS fixes, DMG installer, rename to dungeon-master-xx, device screenshots ([7b3377a](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/7b3377a774c8e4bd250a4e135dd3fa5beed0804f))

## [1.2.0](https://github.com/dungeon-master-xx/kinopub-apple-client/compare/v1.1.1...v1.2.0) (2026-06-27)


### ✨ Features

* AltStore/SideStore source for one-tap install + auto-updates ([d302bc4](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/d302bc49a39e82ad76dedf01aae4a86539d821ba))
* GitHub Pages redirector for one-tap AltStore/SideStore source links ([ec616da](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/ec616da6e52e052630395ad8307733fda4e0275a))
* **settings:** add About section (source code, report a problem, install guide) ([b3771e2](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/b3771e250f6abbaf426d40c200759318988bb2b3))


### 🐛 Fixes

* **altstore:** include legacy source fields for older AltStore compatibility ([f3a1a7b](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/f3a1a7ba7c4bab0e6428c415d0f8a1b4f1155f98))
* render clean plain-text What's New in AltStore source (strip Markdown) ([e76b783](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/e76b783c9e68ecab5809e640a434eab9f51721dc))
* sync app version across project, settings and releases ([d2d947c](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/d2d947ca0035eab8e3748072050b1426512c9a98))


### 📝 Docs

* AltStore/SideStore install banner with badges in README ([dc7c8aa](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/dc7c8aadd33d99760b8f2ff6fc1bfff2dba749de))
* landing page with AltStore/SideStore buttons + screenshots ([099f3e5](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/099f3e5a6254eaef01e59f1536c40b24bb078cbd))
* top AltStore version badge + use self-hosted Pages redirector for source buttons ([40aba5a](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/40aba5aa7fadac0f2635d9f150b1405db0e8ba8f))

## [1.1.1](https://github.com/dungeon-master-xx/kinopub-apple-client/compare/v1.1.0...v1.1.1) (2026-06-27)


### 🐛 Fixes

* **macos:** add macOS app icon (idiom: mac) so the .app isn't blank ([dde14d4](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/dde14d4b0d425bae0ccd70aec3f78707471b3494))

## [1.1.0](https://github.com/dungeon-master-xx/kinopub-apple-client/compare/v1.0.0...v1.1.0) (2026-06-27)


### ✨ Features

* playback, search, collections & cross-platform (macOS/iPad) improvements ([9a25b0c](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/9a25b0c1c4adb5bd18edf573428165c618217f9f))
* **release:** build & attach macOS app artifact ([a19ceec](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/a19ceec44d54f2ec2d77814a800af1934e12a701))


### 📝 Docs

* add app screenshots gallery to README; bump actions/checkout to v5 ([f1a82de](https://github.com/dungeon-master-xx/kinopub-apple-client/commit/f1a82decf0427eef0c4997713dd7ae09c8dc47ed))
