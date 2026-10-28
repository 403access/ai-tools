import { D, F, T, I, chip, card, sectionLabel, page, row, group, node, arrow, esc } from "./kit.mjs";

const fact = (label, value, sub) =>
  F(
    "Fact",
    { flex: "col", gap: 3, p: 14, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: "fill", grow: 1, h: "hug" },
    T(label.toUpperCase(), { size: 9, weight: "bold", color: "#7A828C", letterSpacing: 0.8 }) +
      T(value, { size: 22, weight: "bold", color: "#171B21" }) +
      T(sub, { size: 10, color: "#6B7079", lineHeight: 14 }),
  );

const repoLine = (depth, name, note, color = "#3C4450") =>
  F(
    "Repo line",
    { flex: "row", items: "center", gap: 8, h: 22, w: "fill", h: "hug" },
    F("Indent", { w: depth * 16, h: 1 }) +
      I(depth === 0 ? "lucide:folder" : "lucide:corner-down-right", 11, depth === 0 ? D.accent : "#B6BCC5") +
      T(name, { size: 11, weight: depth === 0 ? "bold" : "medium", color }) +
      T(note, { size: 9.5, color: "#8A919B", w: "fill" }),
  );

export default function () {
  const hero =
    F(
      "Hero",
      {
        w: 1480,
        h: 620,
        flex: "col",
        justify: "between",
        gap: 24,
        p: 48,
        rounded: 28,
        bg: "#151515",
        stroke: "#FFFFFF18",
        strokeWidth: 1,
        overflow: "hidden",
      },
      F(
        "Glow",
        {
          position: "absolute",
          x: 900,
          y: -180,
          w: 760,
          h: 760,
          rounded: 380,
          bg: "#4DD9A01A",
        },
      ) +
        F(
          "Top",
          { flex: "row", items: "center", gap: 14, w: "fill" },
          F(
            "Logo",
            { w: 62, h: 62, rounded: 18, bg: D.accent, items: "center", justify: "center" },
            I("lucide:code-xml", 34, "#0B1F17"),
          ) +
            F(
              "Titles",
              { flex: "col", gap: 3 },
              T("OpenCodeBar", { size: 42, weight: "bold", color: "#FFFFFF", letterSpacing: -1 }) +
                T("A complete OpenPencil mirror of the repository", { size: 15, color: "#A0A0A0" }),
            ) +
            F("Spacer", { grow: 1, w: 1 }) +
            chip("v1.0", D.accent) +
            chip("macOS 14+", D.running) +
            chip("iOS 17+", D.purple),
        ) +
        F(
          "Body",
          { flex: "col", gap: 14, w: 980 },
          T(
            "Watch your OpenCode work from a native macOS menu bar app, an optional desktop window, and an iPhone or iPad app. Both clients talk to OpenCodeBar Hub — a small Bun + SQLite server that ingests the local OpenCode service and keeps one shared, cached history.",
            { size: 20, color: "#D6D6D6", lineHeight: 30, w: 980 },
          ) +
            F(
              "Badges",
              { flex: "row", gap: 8, wrap: true, w: 980 },
              chip("SwiftUI", D.accent) +
                chip("Bun + SQLite", D.warn) +
                chip("Docusaurus", D.running) +
                chip("NixOS / Virtualization.framework", D.purple) +
                chip("SwiftTerm", D.cacheRead) +
                chip("ScreenCaptureKit", D.cacheWrite),
            ),
        ) +
        F(
          "Bottom",
          { flex: "row", items: "end", justify: "between", w: "fill" },
          F(
            "Repo",
            { flex: "col", gap: 4 },
            T("REPOSITORY", { size: 9, weight: "bold", color: "#6F6F6F", letterSpacing: 1 }) +
              T("github.com/403access/ai-tools", { size: 13, weight: "semibold", color: "#FFFFFF" }) +
              T("~/Developer/ai-tools", { size: 11, color: "#8A8A8A" }),
          ) +
            F(
              "Docs",
              { flex: "col", gap: 4, items: "end" },
              T("DOCUMENTATION", { size: 9, weight: "bold", color: "#6F6F6F", letterSpacing: 1 }) +
                T("403access.github.io/ai-tools/docs", { size: 13, weight: "semibold", color: D.accent }),
            ),
        ),
    );

  const glance = card(
    sectionLabel("At a glance") +
      F(
        "Grid",
        { flex: "col", gap: 10, w: "fill", h: "hug" },
        F("R1", { flex: "row", gap: 10, w: "fill" }, fact("Surfaces", "5", "menu bar · panel · desktop · iPhone · iPad")) +
          F("R2", { flex: "row", gap: 10, w: "fill" }, fact("Feature areas", "11", "tasks, live, projects, usage, system…")) +
          F("R3", { flex: "row", gap: 10, w: "fill" }, fact("Design pages", "13", "screens, states, architecture, roadmap")) +
          F("R4", { flex: "row", gap: 10, w: "fill" }, fact("Screens & states", "110+", "populated, empty, loading, error, light")),
      ) +
      F(
        "Note",
        { flex: "col", gap: 6, p: 12, rounded: 12, bg: "#4DD9A010", stroke: "#4DD9A033", strokeWidth: 1, w: "fill" },
        T("How to read this project", { size: 11, weight: "bold", color: D.accent }) +
          T(
            "Each page is a product area. Dark frames are the shipping appearance; light frames document the alternate appearance. Captions name the SwiftUI source file so design and code stay in sync.",
            { size: 10, color: "#B9C4C0", lineHeight: 15, w: "fill" },
          ),
      ),
    { w: 700, p: 20, gap: 14, bg: "#FFFFFF", stroke: "#00000012" },
  );

  const repo = card(
    sectionLabel("Repository map") +
      F(
        "Tree",
        { flex: "col", gap: 1, w: "fill", h: "hug" },
        repoLine(0, "Sources/OpenCodeBar/", "macOS menu bar app (SwiftPM)") +
        repoLine(1, "Core/", "hub client, discovery, terminals, VMs") +
        repoLine(1, "Models/", "sessions, messages, stats, git, system") +
        repoLine(1, "Views/", "panel, tabs, session, projects, VMs") +
        repoLine(1, "Preview/", "offscreen screenshot runner") +
        repoLine(0, "Sources/OpenCodeBarMobile/", "iOS app (XcodeGen)") +
        repoLine(1, "MobileStore*.swift", "sync, events, messages, tasks") +
        repoLine(1, "MobileDatabase*.swift", "local SQLite cache") +
        repoLine(0, "Sources/OpenCodeBarWidgets/", "Live + Usage Home Screen widgets") +
        repoLine(0, "Sources/OpenCodeBarRemoteHost/", "ScreenCaptureKit helper") +
        repoLine(0, "Sources/OpenCodeBarVZ/", "Virtualization.framework helper") +
        repoLine(0, "server/", "Bun + TypeScript + SQLite hub") +
        repoLine(1, "src/api/", "HTTP routes and SSE") +
        repoLine(1, "src/vms/", "NixOS catalog, builds, console") +
        repoLine(0, "website/", "Docusaurus documentation site") +
        repoLine(0, "docs/", "static marketing site + screenshots") +
        repoLine(0, "performance/", "before/after analysis") +
        repoLine(0, "Scripts/", "build, restart, mobile, icons") +
        repoLine(0, "Tests/", "event folding and ordering"),
      ),
    { w: 940, p: 20, gap: 12, bg: "#FFFFFF", stroke: "#00000012" },
  );

  const stack = card(
    sectionLabel("Runtime topology") +
      F(
        "Diagram",
        { flex: "row", items: "center", gap: 4, w: "fill", h: "hug" },
        node("OpenCode service", ["loopback · HTTP Basic auth", "REST + SSE"], D.running, 200) +
          arrow("REST + SSE") +
          node("OpenCodeBar Hub", ["Bun · SQLite · Bearer auth", "cache, sync, event throttle"], D.accent, 200) +
          arrow("cached REST + SSE") +
          F(
            "Clients",
            { flex: "col", gap: 8, w: 230, h: "hug" },
            node("macOS app", ["menu bar · panel · desktop"], D.purple, 230) +
              node("iOS app", ["iPhone · iPad · widgets"], D.warn, 230),
          ),
      ),
    { w: 940, p: 20, gap: 12, bg: "#FFFFFF", stroke: "#00000012" },
  );

  const legend = card(
    sectionLabel("Legend") +
      F(
        "Items",
        { flex: "col", gap: 8, w: "fill", h: "hug" },
        F("L1", { flex: "row", items: "center", gap: 10, h: "hug" }, F("Sw", { w: 28, h: 16, rounded: 4, bg: D.accent }) + T("Accent · success · connected", { size: 10, color: "#3C4450" })) +
        F("L2", { flex: "row", items: "center", gap: 10, h: "hug" }, F("Sw", { w: 28, h: 16, rounded: 4, bg: D.running }) + T("Running · live activity", { size: 10, color: "#3C4450" })) +
        F("L3", { flex: "row", items: "center", gap: 10, h: "hug" }, F("Sw", { w: 28, h: 16, rounded: 4, bg: D.warn }) + T("Needs review · warning · stale", { size: 10, color: "#3C4450" })) +
        F("L4", { flex: "row", items: "center", gap: 10, h: "hug" }, F("Sw", { w: 28, h: 16, rounded: 4, bg: D.danger }) + T("Failed · destructive", { size: 10, color: "#3C4450" })) +
        F("L5", { flex: "row", items: "center", gap: 10, h: "hug" }, F("Sw", { w: 28, h: 16, rounded: 4, bg: "#F1F3F6", stroke: "#00000014", strokeWidth: 1 }) + T("Light appearance frames", { size: 10, color: "#3C4450" })),
      ),
    { w: 440, p: 20, gap: 12, bg: "#FFFFFF", stroke: "#00000012" },
  );

  return page({
    title: "OpenCodeBar — the whole product, in one OpenPencil file",
    subtitle:
      "A working visual mirror of the repository: every app surface, every feature area, demo data, empty and failure states, the hub architecture, and the roadmap that keeps this file honest.",
    meta: "13 pages · 110+ screens and states · generated from design/gen · OpenPencil 0.16",
    width: 3300,
    children:
      row("Hero row", hero + glance, { gap: 32 }) +
      row("Repo row", repo + stack, { gap: 32 }) +
      row("Legend row", legend + card(
        sectionLabel("What is inside") +
          F("List", { flex: "col", gap: 7, w: "fill", h: "hug" },
            T("01  Design system", { size: 12, weight: "semibold", color: "#20252C" }) +
            T("02–05  macOS: shell, live, sessions, projects, usage, system, VMs", { size: 11, color: "#4C545E" }) +
            T("06–08  iOS: core, host/remote, VMs, widgets, iPad", { size: 11, color: "#4C545E" }) +
            T("09  States and edge cases", { size: 11, color: "#4C545E" }) +
            T("10  Architecture and API", { size: 11, color: "#4C545E" }) +
            T("11  Roadmap", { size: 11, color: "#4C545E" }) +
            T("12  Coverage and documentation", { size: 11, color: "#4C545E" }),
          ),
        { w: 900, p: 20, gap: 12, bg: "#FFFFFF", stroke: "#00000012" },
      )),
  });
}
