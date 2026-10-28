import { D, F, T, I, chip, card, sectionLabel, pageParts, group } from "./kit.mjs";

const row = (area, sources, page, states) =>
  F("Coverage row", { flex: "row", items: "start", gap: 8, w: "fill", py: 5, stroke: "#00000008", strokeWidth: 1 },
    T(area, { size: 9.5, weight: "semibold", color: "#20252C", w: 220 }) +
    T(sources, { size: 8, color: "#626A75", w: 430, lineHeight: 11 }) +
    T(page, { size: 8, color: "#0B8F65", w: 150 }) +
    F("States", { flex: "row", gap: 3, wrap: true, w: "fill", h: "hug" }, states.map((s) => chip(s, s === "empty" ? D.warn : s === "error" ? D.danger : s === "light" ? D.running : D.accent)).join("")),
  );

const docRow = (path, title, note) =>
  F("Doc", { flex: "row", items: "start", gap: 7, w: "fill", py: 4 },
    I("lucide:file-text", 9, D.sec) + T(path, { size: 8.5, color: "#20252C", w: 300 }) + T(title, { size: 8.5, weight: "semibold", color: "#3C4450", w: 260 }) + T(note, { size: 8, color: "#6B7079", w: "fill", lineHeight: 11 }),
  );

export default function () {
  return pageParts({
    title: "Coverage and documentation",
    subtitle: "The audit trail: which SwiftUI files each design page mirrors, which states are covered, and which documentation pages describe the same behaviour.",
    meta: "Keep this page and design/TODO.md in sync with every build pass.",
    width: 2400,
    sections: [
      group("Screen coverage", "Every product area names its source files and the states present in the file.", [
        F("Card", { flex: "col", gap: 2, p: 18, rounded: 14, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 1560, h: "hug" },
          F("Head", { flex: "row", gap: 8, w: "fill", pb: 6 }, T("AREA", { size: 8, weight: "bold", color: "#8A919B", w: 220 }) + T("SOURCE FILES", { size: 8, weight: "bold", color: "#8A919B", w: 430 }) + T("DESIGN PAGE", { size: 8, weight: "bold", color: "#8A919B", w: 150 }) + T("STATES", { size: 8, weight: "bold", color: "#8A919B", w: "fill" })) +
          row("Menu bar + panel", "StatusItemController.swift · PanelView.swift", "02 · macOS shell", ["populated", "empty", "settings"]) +
          row("Desktop window", "DesktopWindowController.swift · DesktopView.swift", "02 · macOS shell", ["3-column", "narrow"]) +
          row("Live", "LiveTab.swift · LiveRunningRow.swift · LiveRecentRow.swift", "02/03 · macOS", ["populated", "empty", "filters", "failed", "paused"]) +
          row("Tasks", "TasksTab.swift · MobileStore+Tasks.swift", "02/06 · Tasks", ["board", "empty", "done", "light"]) +
          row("Session", "SessionDetailView*.swift · SessionMessageViews.swift", "03 · macOS · 06 · iOS", ["chat", "stats", "changes", "prompts", "git", "subagents"]) +
          row("Projects", "ProjectsTab.swift · ProjectDetail*.swift · MobileProjectFiles.swift", "04 · macOS · 06 · iOS", ["populated", "empty", "stats", "files", "non-git"]) +
          row("Usage", "UsageTab.swift · UsageCharts.swift · UsageView.swift", "04 · macOS · 06 · iOS", ["overview", "activity", "breakdown", "tools", "no key", "stale"]) +
          row("System", "SystemTab.swift · SystemCategoryView.swift · PerformanceViews.swift", "05 · macOS · 07 · iOS", ["dashboard", "performance", "network", "software"]) +
          row("Terminals + files", "TerminalViews.swift · SystemFileBrowser.swift · MobileFileBrowser.swift", "05/07", ["list", "emulator", "mirror", "preview"]) +
          row("Remote desktop", "RemoteDesktopView.swift · RemoteDesktopConnection.swift", "07 · iOS", ["connected", "permissions", "view-only"]) +
          row("Virtual machines", "VirtualMachinesTab.swift · VirtualMachineDetailView.swift · NixOSBuilderView.swift", "05/08", ["populated", "empty", "not ready", "console", "builder"]) +
          row("Widgets", "LiveWidget.swift · UsageWidget.swift · WidgetTheme.swift", "08 · iOS", ["small", "medium", "large", "cached"]) +
          row("Settings", "SettingsTab.swift · SettingsView.swift · SettingsDeviceDetail.swift", "02/06", ["devices", "server", "power", "developer", "pairing"])),
      ].join("")),
      group("Documentation map", "The docs site is the published companion; the README is the deep reference.", [
        F("Card", { flex: "col", gap: 2, p: 18, rounded: 14, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 1300, h: "hug" },
          docRow("website/docs/intro.md", "Overview", "What OpenCodeBar is and the three surfaces.") +
          docRow("website/docs/getting-started/", "Install & pairing", "Hub, Mac app, iOS app, QR pairing.") +
          docRow("website/docs/using/live.md", "Live", "Running and recent sessions, filters.") +
          docRow("website/docs/using/session.md", "Sessions", "Chat, stats, changes, prompts, git, subagents.") +
          docRow("website/docs/using/projects.md", "Projects", "Overview, stats, changes, files, git.") +
          docRow("website/docs/using/usage.md", "Usage", "Plan limits, trends, breakdown, tools.") +
          docRow("website/docs/using/system.md", "System", "Inventory, performance, media, terminals, files.") +
          docRow("website/docs/using/virtual-machines.md", "VMs", "Builder, lifecycle, console, rebuild.") +
          docRow("website/docs/using/remote.md", "Remote desktop", "Streaming, permissions, quality presets.") +
          docRow("website/docs/hub/architecture.md", "Architecture", "Hub topology and request flow.") +
          docRow("website/docs/hub/api.md", "API", "OpenAPI reference and examples.") +
          docRow("website/docs/hub/security.md", "Security", "Token, pairing, local-only storage.") +
          docRow("README.md", "Deep reference", "Features, how it works, project layout, limitations.") +
          docRow("design/README.md", "This design", "How to open and regenerate the .fig.")),
      ].join("")),
      group("Repository map", "The design mirrors these top-level areas.", [
        F("Card", { flex: "col", gap: 3, p: 18, rounded: 14, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 1300, h: "hug" },
          [["Sources/OpenCodeBar/", "macOS app · Core, Models, Views, Preview"],
           ["Sources/OpenCodeBarMobile/", "iOS app · store, SQLite cache, views"],
           ["Sources/OpenCodeBarWidgets/", "Live + Usage Home Screen widgets"],
           ["Sources/OpenCodeBarRemoteHost/", "ScreenCaptureKit helper"],
           ["Sources/OpenCodeBarVZ/", "Virtualization.framework helper"],
           ["server/", "Bun + SQLite hub · API, sync, VMs, terminals"],
           ["website/", "Docusaurus docs site"],
           ["docs/", "Static marketing site + screenshots"],
           ["performance/", "Before/after measurements"],
           ["Scripts/", "Build, restart, mobile, icons"],
           ["Tests/", "Event folding and ordering"]].map(([p, n]) =>
            F("R", { flex: "row", items: "center", gap: 7, py: 4, w: "fill" }, I("lucide:folder", 9, D.accent) + T(p, { size: 9, weight: "semibold", color: "#20252C", w: 340 }) + T(n, { size: 8.5, color: "#6B7079", w: "fill" }))).join("")),
      ].join("")),
      group("Changelog and rebuild", "The file is generated; the generator is the source of truth.", [
        F("Card", { flex: "col", gap: 6, p: 18, rounded: 14, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 1000, h: "hug" },
          T("2026-10-27 · initial mirror", { size: 12, weight: "bold", color: "#20252C" }) +
          ["Created 13 pages covering macOS, iOS, iPad, widgets, states, architecture and roadmap.", "Built the design-system page from Theme.swift and Components.swift.", "Added demo data for sessions, projects, tasks, usage, system, terminals and VMs.", "Documented empty, loading, error, stale, permission and light-mode states.", "Added design/build.mjs and per-page JSX modules under design/gen."].map((t) =>
            F("C", { flex: "row", items: "start", gap: 5, w: "fill" }, I("lucide:check", 9, D.accent) + T(t, { size: 9, color: "#3C4450", lineHeight: 13, w: "fill" }))).join("") +
          F("Code", { flex: "col", gap: 3, p: 10, rounded: 8, bg: "#0F0F0F", w: "fill" },
            T("# regenerate JSX for every page", { size: 8, color: "#8A8A8A" }) +
            T("node design/build.mjs", { size: 9, color: D.output }) +
            T("# render into the open document and save", { size: 8, color: "#8A8A8A" }) +
            T("OPENPENCIL_DOC=tab-1 node design/build.mjs --render", { size: 9, color: D.output }) +
            T("openpencil documents save --document-id tab-1", { size: 9, color: D.output }))) +
        F("Card", { flex: "col", gap: 6, p: 18, rounded: 14, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 760, h: "hug" },
          T("How to review", { size: 12, weight: "bold", color: "#20252C" }) +
          ["Open design/OpenCodeBar.fig in OpenPencil 0.16.", "Start at 00 · Cover, then follow the numbered pages.", "Compare a frame caption with the named SwiftUI file.", "Use 09 · States for empty/loading/error/light checks.", "Use 10 · Architecture for the hub and API.", "Update design/TODO.md after adding a frame."].map((t) =>
            F("R", { flex: "row", items: "start", gap: 5, w: "fill" }, I("lucide:arrow-right", 9, D.accent) + T(t, { size: 9, color: "#3C4450", lineHeight: 13, w: "fill" }))).join("")),
      ].join("")),
    ],
  });
}
