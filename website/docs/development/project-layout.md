---
title: Project layout
sidebar_position: 4
---

# Project layout

```text
Sources/OpenCodeBar/              macOS menu bar app (SwiftPM)
  OpenCodeBarApp.swift            AppKit entry point, app delegate, status item install
  StatusItemController.swift      status item, left/right click routing, panel popover
  DesktopWindowController.swift   optional desktop window, Dock mode, app menu
  main.swift                      entry point, preview/screenshot mode
  AppState.swift                  observable state, polling, derived data
  AppState+Terminals.swift        terminal polling, creation and removal
  Core/
    HubAPI.swift                  async client for the hub (shared)
    HubAPI+Endpoints.swift        endpoint methods
    HubAPI+Transport.swift        requests, decoding and diagnostics
    HubModels.swift               hub transport/health models
    HubEventStream.swift          SSE subscription with reconnect (shared)
    HubDiscovery.swift            hub URL + token discovery (macOS)
    ServiceDiscovery.swift        OpenCode config paths
    DeviceIdentity.swift          stable client id + platform headers
    HubConfig.swift               URL/token settings model (shared)
    WidgetShared.swift            shared keychain + snapshot cache (shared)
    UsageCache.swift              last-known usage on disk
    TerminalConnection.swift      PTY socket, input and resize bridging (shared)
  Models/                         Codable models, events, activity, ordering
    TokenUsage.swift              token/model primitives
    Session.swift                 sessions and projects
    Stats.swift                   aggregate and per-session statistics
    Messages.swift                messages, parts and pending prompts
    Changes.swift                 file patches and grouping
    ProjectFiles.swift            project file browser payloads
    APIEnvelopes.swift            request/response envelopes
    SessionFilter.swift           project/date filters for recent feeds
    WidgetSnapshot.swift          compact widget payload (shared)
    Terminals.swift               terminal models and requests (shared)
  Support/
    SpeechInput.swift             speech-to-text dictation (shared)
    QRCode.swift                  pairing QR rendering
    Formatters.swift
    DebugLog.swift
  Views/
    PanelView.swift               panel shell and tabs
    DesktopView.swift             desktop window: sidebar + content
    LiveTab.swift                 running and recent sessions
    SessionDetailView.swift       chat, stats, changes, prompts, subagents
    SessionDetailView+Composer.swift  pending queue and composer
    SessionDetailView+Content.swift   tab content
    SessionDetailView+Loading.swift   message paging
    SessionMessageViews.swift         message and prompt cards
    ProjectDetailView.swift       project page: header, tabs, sections
    ProjectDetailAnalytics.swift  scoped at-a-glance stats
    ProjectSessions.swift         recent-session rows
    SettingsTab.swift             devices, server controls, pairing
    SettingsTab+Support.swift     derived labels and actions
    NewSessionSheet.swift         create a session with a first prompt
    SessionStatsView.swift        per-session reliability and failures
    ChangeViews.swift             patch cards and diffs
    SubagentViews.swift           child-session tree
    UsageTab.swift                plan limits, trends, heatmap
    TerminalViews.swift           terminal list, new-terminal sheet, terminal window
    TerminalEmulatorView.swift    SwiftTerm host for Mac and iOS
  Preview/PreviewRunner.swift     offscreen screenshots

Sources/OpenCodeBarMobile/        iOS app (XcodeGen target)
  OpenCodeBarMobileApp.swift      app entry + floating tab dock
  MobileStore.swift               observable hub state
  MobileStore+Sync.swift          snapshot/delta refresh
  MobileStore+Events.swift        event folding and activity seeding
  MobileStore+Messages.swift      messages and prompt queue
  MobileStore+Loaders.swift       project/changes/stats/subagent loaders
  MobileStore+Terminals.swift     terminal polling, creation and removal
  MobileDatabase.swift            local SQLite cache + incremental sync
  MobileDatabase+Sessions.swift   sessions/projects persistence
  MobileDatabase+Messages.swift   message cache
  MobileDatabase+Metadata.swift   stats/usage/identity
  MobileDatabase+Schema.swift     schema migration
  HubSettings.swift               URL/token storage and pairing links
  MobileRouter.swift              widget/deep-link routing
  WidgetPublisher.swift           writes the shared widget snapshot
  PairingScanner.swift            camera QR scanner for pairing
  LiveView.swift                  running/recent sessions
  LiveView+Filters.swift          project/date filters
  SessionDetailView.swift         chat, stats, changes, prompts, subagents
  SessionDetailView+Composer.swift  pending queue and composer
  SessionDetailView+Content.swift   tab content
  SessionDetailView+Loading.swift   message paging
  NewSessionSheet.swift           create a session from the phone
  ProjectDetailView.swift         scoped analytics and changes
  ProjectsView.swift              list + search
  UsageView.swift                 plan limits, trends, stats
  SettingsView.swift              appearance, pairing, status
  SettingsView+Connection.swift   status and hub connection controls
  MobileTerminalViews.swift       terminal list, new-terminal and terminal sheets
  MobileCharts.swift              Swift Charts
  MobileMessageViews.swift        message cards
  MobileChangeViews.swift         patch cards
  MobileSessionStatsView.swift    session reliability
  MobileTheme.swift               design tokens

Sources/OpenCodeBarWidgets/       iOS Home Screen extension
  OpenCodeBarWidgets.swift        WidgetBundle with Live and Usage
  LiveWidget.swift                running sessions, small/medium/large
  UsageWidget.swift               stats, trend and plan limits
  WidgetDataLoader.swift          hub fetch + cached snapshot fallback
  WidgetTheme.swift               widget palette and compact components

server/                           Bun + TypeScript + SQLite hub
  src/index.ts                    entry point and port fallback
  src/config.ts                   env/config resolution, pairing link
  src/types.ts                    wire types shared with the apps
  src/opencode.ts                 OpenCode integration (barrel)
  src/opencode/                   discovery, REST client, errors, Go usage
  src/terminals.ts                PTY aggregation and lifecycle across locations
  src/api/terminal-socket.ts      WebSocket proxy for live terminal I/O
  src/db.ts                       SQLite facade
  src/db/                         schema, row mapping, stores, queries
  src/hub.ts                      polling/event hub facade
  src/hub/                        event bus, sync, reads, usage cache
  src/files.ts                    project file browser
  src/projectIcon.ts              project app icon discovery
  src/api.ts                      HTTP routes
  src/api/                        request helpers and SSE clients
  test/                           Bun tests

website/                          Docusaurus documentation site
  docs/                           Markdown/MDX pages
  src/components/                 Figure, HomeHero
  src/css/custom.css              docs theme
  static/img/                     logo and screenshots
  docusaurus.config.js            site config and GitHub Pages base URL
  sidebars.js                     documentation navigation

docs/                             static marketing site
  index.html
  assets/style.css
  screenshots/                    shared screenshots used by README and site

.github/workflows/deploy-pages.yml  builds marketing + docs, deploys Pages

project.yml                       XcodeGen spec
Mobile/Info.plist                 generated by XcodeGen
Scripts/                          app, hub, iOS, icon, and screenshot helpers
Tests/OpenCodeBarTests/           Swift tests
```

## Generated and ignored

- `.build/`, `dist/`, `.swiftpm/`
- `server/node_modules/`
- `website/node_modules/`, `website/build/`, `website/.docusaurus/`
- `OpenCodeBarMobile.xcodeproj` (regenerate with `make mobile-project`)
- `Mobile/Info.plist` (regenerate with XcodeGen)
- `Mobile/Widgets-Info.plist` (regenerate with XcodeGen)
