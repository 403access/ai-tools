import { D, F, T, I, chip, sectionLabel, page } from "./kit.mjs";

const item = (n, title, note) =>
  F("Index", { flex: "row", items: "start", gap: 10, p: 12, rounded: 10, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 680, h: "hug" },
    T(n, { size: 18, weight: "bold", color: D.accent, w: 34 }) +
    F("B", { flex: "col", gap: 2, grow: 1 }, T(title, { size: 11, weight: "bold", color: "#20252C" }), T(note, { size: 9, color: "#6B7079", lineHeight: 13, w: "fill" })),
  );

export default function () {
  return page({
    title: "OpenCodeBar — design mirror",
    subtitle: "A complete visual mirror of the repository: macOS, iPhone, iPad, widgets, hub architecture, states and roadmap. Start with the cover, then follow the numbered pages.",
    meta: "Generated from design/gen · OpenPencil 0.16 · 13 pages · synthetic demo data",
    width: 2400,
    children:
      F("Hero", { flex: "row", items: "center", gap: 18, p: 24, rounded: 18, bg: "#151515", stroke: "#FFFFFF18", strokeWidth: 1, w: "fill", h: "hug" },
        F("Logo", { w: 64, h: 64, rounded: 18, bg: D.accent, items: "center", justify: "center" }, I("lucide:code-xml", 34, "#0B1F17")) +
        F("B", { flex: "col", gap: 4, grow: 1 },
          T("OpenCodeBar", { size: 30, weight: "bold", color: "#FFFFFF" }) +
          T("Watch your OpenCode work from a macOS menu bar app, a desktop window, and an iPhone or iPad app — all through one Bun + SQLite hub.", { size: 12, color: "#BDBDBD", lineHeight: 17, w: 900 }) +
          F("Chips", { flex: "row", gap: 6, wrap: true, w: "fill", h: "hug" }, chip("SwiftUI", D.accent) + chip("Bun + SQLite", D.warn) + chip("iOS 17+", D.purple) + chip("NixOS VMs", D.running))) +
        F("Meta", { flex: "col", gap: 3, items: "end" },
          T("REPOSITORY", { size: 8, weight: "bold", color: "#6F6F6F", letterSpacing: 0.8 }) +
          T("403access/ai-tools", { size: 11, weight: "semibold", color: "#FFFFFF" }) +
          T("DOCS", { size: 8, weight: "bold", color: "#6F6F6F", letterSpacing: 0.8 }) +
          T("403access.github.io/ai-tools/docs", { size: 10, color: D.accent }))) +
      sectionLabel("Page index") +
      F("Grid", { flex: "row", gap: 14, wrap: true, w: "fill", h: "hug" },
        item("00", "Cover & repo map", "Product summary, repository tree, runtime topology and legend.") +
        item("01", "Design system", "Dark and light tokens, type, components and domain specimens.") +
        item("02", "macOS shell", "Menu bar, desktop window, Live, Tasks, Settings and every sheet.") +
        item("03", "macOS sessions", "Conversation, stats, changes, prompts, git, subagents, failure and hold.") +
        item("04", "Projects & usage", "Lists, project tabs, non-git empty, four usage pages, no-key and stale.") +
        item("05", "System & VMs", "Inventory, performance, media, terminals, files, VM list/detail/builder.") +
        item("06", "iOS core", "Live, sessions, projects, tasks, usage, settings, pairing, light mode.") +
        item("07", "iOS Host & Remote", "Dashboard, focused pages, terminals, files, remote display and permissions.") +
        item("08", "iOS VMs & widgets", "Guest list/detail/console/builder, Live and Usage widgets, iPad.") +
        item("09", "States", "Empty, loading, error, stale, permission, long content and light appearance.") +
        item("10", "Architecture", "Topology, request flow, API surface, data model, storage, security, build.") +
        item("11", "Roadmap", "Phases, milestones, current sprint, risks and definition of done.") +
        item("12", "Coverage & docs", "Source-to-screen matrix, documentation map, repository map, changelog.")) +
      F("Note", { flex: "row", items: "center", gap: 8, p: 14, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: "fill" },
        I("lucide:refresh-cw", 14, D.accent) +
        T("Regenerate with `node design/build.mjs`; render with `OPENPENCIL_DOC=tab-1 node design/build.mjs --render`. Demo data is synthetic.", { size: 10, color: "#3C4450", w: "fill" })),
  });
}
