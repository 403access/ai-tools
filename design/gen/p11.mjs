import { D, F, T, I, chip, card, sectionLabel, pageParts, group, bar } from "./kit.mjs";

const phase = (n, title, scope, status, color, items) =>
  F("Phase", { flex: "col", gap: 8, p: 16, rounded: 14, bg: "#FFFFFF", stroke: color + "33", strokeWidth: 1, w: 480, h: "hug" },
    F("H", { flex: "row", items: "center", gap: 7, w: "fill" },
      F("N", { w: 26, h: 26, rounded: 13, bg: color + "1A", items: "center", justify: "center" }, T(n, { size: 10, weight: "bold", color })) +
      T(title, { size: 13, weight: "bold", color: "#20252C", w: "fill" }) + chip(status, color)) +
    T(scope, { size: 9, color: "#6B7079", lineHeight: 13, w: "fill" }) +
    F("Items", { flex: "col", gap: 4, w: "fill" }, items.map(([t, done]) =>
      F("Item", { flex: "row", items: "start", gap: 5, w: "fill" },
        I(done ? "lucide:check-circle" : "lucide:circle", 9, done ? color : "#B6BCC5") +
        T(t, { size: 8.5, color: done ? "#3C4450" : "#7A828C", lineHeight: 12, w: "fill" }))).join("")),
  );

const milestone = (m, title, detail, status, color) =>
  F("Milestone", { flex: "row", items: "start", gap: 10, p: 12, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 620, h: "hug" },
    F("Badge", { w: 34, h: 34, rounded: 10, bg: color + "18", items: "center", justify: "center" }, T(m, { size: 11, weight: "bold", color })) +
    F("B", { flex: "col", gap: 2, grow: 1 }, T(title, { size: 11, weight: "bold", color: "#20252C" }), T(detail, { size: 8.5, color: "#6B7079", lineHeight: 12, w: "fill" })) + chip(status, color),
  );

const todo = (t, done) =>
  F("Todo", { flex: "row", items: "start", gap: 6, w: "fill", py: 3 },
    I(done ? "lucide:check-square" : "lucide:square", 10, done ? D.accent : "#B6BCC5") +
    T(t, { size: 9, color: done ? "#20252C" : "#6B7079", lineHeight: 13, w: "fill" }),
  );

export default function () {
  return pageParts({
    title: "Roadmap",
    subtitle: "The plan for the design mirror itself: what is already in the file, what comes next, and how each milestone is judged. Update this page and design/TODO.md together.",
    meta: "Companion files: design/ROADMAP.md · design/TODO.md · README.md · website/docs/development/project-layout.md",
    width: 2400,
    sections: [
      group("Vision", "A visual source of truth that can be reviewed without running the app.", [
        F("Row", { flex: "row", gap: 12, w: "fill", h: "hug" },
          F("Card", { flex: "col", gap: 6, p: 16, rounded: 14, bg: "#151515", stroke: "#FFFFFF18", strokeWidth: 1, w: 760, h: "hug" },
            T("One file, every surface", { size: 18, weight: "bold", color: "#FFFFFF" }) +
            T("The macOS menu bar, the desktop window, iPhone, iPad, widgets, the hub and the docs all live in the same document. A reviewer can compare the real app, the SwiftUI source and the design without switching tools.", { size: 10, color: "#C9C9C9", lineHeight: 15, w: 700 }) +
            F("Chips", { flex: "row", gap: 5, wrap: true, w: "fill", h: "hug" }, chip("Demo data", D.accent) + chip("All states", D.running) + chip("Architecture", D.purple) + chip("Docs", D.warn))) +
          F("Card", { flex: "col", gap: 7, p: 16, rounded: 14, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 760, h: "hug" },
            T("Principles", { size: 14, weight: "bold", color: "#20252C" }) +
            ["Mirror the shipping UI, not an idealised redesign.", "Every list has an empty, loading and failure frame.", "Captions name the SwiftUI source file.", "Demo data is synthetic and safe to share.", "Regenerate with one command; never hand-edit the .fig."].map((t) =>
              F("P", { flex: "row", items: "start", gap: 5, w: "fill" }, I("lucide:check", 9, D.accent) + T(t, { size: 9, color: "#3C4450", lineHeight: 13, w: "fill" }))).join(""))) ,
      ].join("")),
      group("Phases · 0–3", "Status reflects the OpenPencil document, not the product roadmap.", [
        phase("0", "Foundations", "Tokens, type, components, page skeleton.", "Done", D.accent, [["Palette from Theme.swift", true], ["Type scale and spacing", true], ["Core components", true], ["13-page skeleton", true]]) +
        phase("1", "macOS shell", "Menu bar, panel, Live, Tasks, Settings.", "Done", D.accent, [["Menu bar + desktop window", true], ["Live populated/empty", true], ["Tasks board/empty", true], ["Settings + sheets", true]]) +
        phase("2", "macOS depth", "Sessions, projects, usage, system, VMs.", "Done", D.accent, [["Session tabs + failures", true], ["Projects + usage", true], ["System + VMs", true], ["Review pass", true]]) +
        phase("3", "iOS core", "Tasks, Live, Projects, Usage, Settings.", "Done", D.accent, [["Live + filters", true], ["Sessions + projects", true], ["Tasks + usage", true], ["Pairing + light mode", true]]),
      ].join("")),
      group("Phases · 4–7", "The mobile extras and the documentation close-out.", [
        phase("4", "iOS host", "Host, Remote desktop, terminals, files.", "Done", D.accent, [["Dashboard + focused pages", true], ["Remote connected/permissions", true], ["App detail", true]]) +
        phase("5", "iOS extras", "VMs, widgets, iPad.", "Done", D.accent, [["VM list/detail/builder", true], ["Live + Usage widgets", true], ["iPad layout", true]]) +
        phase("6", "States + architecture", "Edge cases, API, data model.", "Done", D.accent, [["Empty/loading/error", true], ["Architecture pages", true], ["Coverage matrix", true]]) +
        phase("7", "Docs + review", "README, website, final QA.", "Done", D.accent, [["README project layout", true], ["Website layout page", true], ["Final export check", true]]),
      ].join("")),
      group("Milestones · M1–M3", "Each milestone is a reviewable slice, not a percentage.", [
        milestone("M1", "Reviewable shell", "Cover, design system and macOS Live/Tasks open in OpenPencil and export cleanly.", "Met", D.accent) +
        milestone("M2", "Full macOS surface", "Every macOS tab and sheet has populated and empty/error frames.", "Met", D.accent) +
        milestone("M3", "Full mobile surface", "Every iOS tab, sheet, widget and the Host/Remote flow are covered.", "Met", D.accent),
      ].join("")),
      group("Milestones · M4–M5", "State coverage and the project memory close-out.", [
        milestone("M4", "State coverage", "One page proves empty, loading, error, stale, permission and light states.", "Met", D.accent) +
        milestone("M5", "Project memory", "Architecture, API, roadmap and coverage match the repository and docs site.", "Met", D.accent),
      ].join("")),
      group("Current sprint", "The remaining work is documentation and a final visual review.", [
        F("Col", { flex: "col", gap: 5, w: 680, h: "hug" },
          T("TODO", { size: 10, weight: "bold", color: "#20252C", letterSpacing: 0.6 }) +
          todo("Export the final .fig and verify all 13 pages open", true) +
          todo("Add the design to README project layout", true) +
          todo("Add the design to website/docs/development/project-layout.md", true) +
          todo("Write design/README.md with rebuild steps", true) +
          todo("Check every page at 100% zoom for clipped text", true) +
          todo("Confirm no missing-icon render hangs", true)) +
        F("Col", { flex: "col", gap: 6, w: 780, h: "hug" },
          T("RISKS", { size: 10, weight: "bold", color: "#20252C", letterSpacing: 0.6 }) +
          [["Design drifts from SwiftUI", "Captions + generator modules; rebuild after UI changes", D.warn],
           ["Demo data looks real", "Synthetic paths, names and tokens only", D.accent],
           ["Document too large", "One page per area, sections rendered separately", D.running],
           ["Generated JSX is brittle", "Small kit, variadic frames, no hand edits", D.purple]].map(([r, m, c]) =>
            F("Risk", { flex: "row", items: "start", gap: 6, p: 8, rounded: 8, bg: "#FFFFFF", stroke: "#00000010", strokeWidth: 1, w: "fill" },
              I("lucide:triangle-alert", 10, c) + F("B", { flex: "col", gap: 1, grow: 1 }, T(r, { size: 9, weight: "semibold", color: "#20252C" }), T(m, { size: 8, color: "#6B7079", lineHeight: 12 })))).join("")),
        F("Col", { flex: "col", gap: 6, w: 680, h: "hug" },
          T("DEFINITION OF DONE", { size: 10, weight: "bold", color: "#20252C", letterSpacing: 0.6 }) +
          ["OpenPencil 0.16 opens design/OpenCodeBar.fig with all pages.", "node design/build.mjs regenerates every page.", "design/TODO.md has no unchecked coverage items.", "README and website layout docs mention the design.", "The final export is checked at 100% zoom."].map((t) =>
            F("D", { flex: "row", items: "start", gap: 5, w: "fill" }, I("lucide:check-circle", 9, D.accent) + T(t, { size: 8.5, color: "#3C4450", lineHeight: 12, w: "fill" }))).join("")),
      ].join("")),
    ],
  });
}
