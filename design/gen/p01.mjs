import { D, L, F, T, I, chip, card, sectionLabel, page, row, bar, emptyState, notice, statTile } from "./kit.mjs";

const swatch = (name, hex, role, onDark) =>
  F(
    "Swatch",
    { flex: "col", gap: 5, w: 150, h: "hug" },
    F("Color", { w: 150, h: 58, rounded: 10, bg: hex, stroke: onDark ? "#FFFFFF1A" : "#00000014", strokeWidth: 1 }) +
      T(name, { size: 10, weight: "bold", color: onDark ? "#FFFFFF" : "#20252C" }) +
      T(hex.toUpperCase(), { size: 9, color: onDark ? "#A0A0A0" : "#6B7079" }) +
      T(role, { size: 9, color: onDark ? "#8A8A8A" : "#8A919B", lineHeight: 12, w: 150 }),
  );

const swatchRows = (items, onDark, perRow = 6) =>
  F("Swatches", { flex: "col", gap: 14, w: "fill", h: "hug" },
    Array.from({ length: Math.ceil(items.length / perRow) }, (_, r) =>
      F("Row", { flex: "row", gap: 12, w: "fill", h: "hug" },
        items.slice(r * perRow, r * perRow + perRow).map((s) => swatch(s[0], s[1], s[2], onDark)).join("")),
    ).join(""),
  );

const typeRow = (size, weight, label, sample, color = "#171B21") =>
  F(
    "Type row",
    { flex: "row", items: "center", gap: 16, w: "fill", h: "hug", pb: 7, stroke: "#0000000A", strokeWidth: 1 },
    F("Meta", { flex: "col", gap: 1, w: 150 },
      T(label, { size: 10, weight: "bold", color: "#20252C" }) +
      T(`${size}px · ${weight}`, { size: 9, color: "#8A919B" })) +
      T(sample, { size, weight, color, w: "fill", lineHeight: Math.round(size * 1.3) }),
  );

const specimen = (label, node, note = "", w = 368) =>
  F(
    "Specimen",
    { flex: "col", gap: 8, w, h: "hug", p: 13, rounded: 12, bg: "#F7F8FA", stroke: "#00000010", strokeWidth: 1 },
    T(label.toUpperCase(), { size: 9, weight: "bold", color: "#8A919B", letterSpacing: 0.7 }) + node +
      (note ? T(note, { size: 9, color: "#8A919B", lineHeight: 13, w: "fill" }) : ""),
  );

const btn = (label, kind = "primary") => {
  const map = {
    primary: { bg: D.accent, color: "#062017", stroke: "#00000000" },
    secondary: { bg: "#F1F3F6", color: "#2B3038", stroke: "#00000014" },
    danger: { bg: "#F7666B18", color: D.danger, stroke: "#F7666B33" },
    ghost: { bg: "#FFFFFF00", color: "#4C545E", stroke: "#00000012" },
  }[kind];
  return F("Button", { px: 12, py: 6, rounded: 9, bg: map.bg, stroke: map.stroke, strokeWidth: 1, w: "hug", h: "hug" },
    T(label, { size: 11, weight: "semibold", color: map.color }));
};

const input = (placeholder, value = "") =>
  F("Input", { flex: "row", items: "center", gap: 7, px: 10, py: 7, rounded: 10, bg: "#FFFFFF", stroke: "#00000014", strokeWidth: 1, w: "fill", h: "hug" },
    I("lucide:search", 12, "#8A919B") +
    T(value || placeholder, { size: 11, color: value ? "#20252C" : "#8A919B", w: "fill" }));

const darkCard = (children, w) =>
  F("Dark card", { flex: "col", gap: 16, p: 22, rounded: 16, bg: D.panel, stroke: D.border, strokeWidth: 1, w, h: "hug" }, children);

const lightCard = (children, w) =>
  F("Light card", { flex: "col", gap: 14, p: 22, rounded: 16, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w, h: "hug" }, children);

export default function () {
  const darkColors = darkCard(
    T("DARK APPEARANCE · VIEWS/THEME.SWIFT", { size: 9, weight: "bold", color: "#8A8A8A", letterSpacing: 0.8 }) +
      swatchRows([
        ["Panel", D.panel, "Panel background"],
        ["Card", D.card, "Card and row fill"],
        ["Accent", D.accent, "Success, connected, primary"],
        ["Running", D.running, "Live activity and timers"],
        ["Warn", D.warn, "Review, stale, warnings"],
        ["Danger", D.danger, "Failures, destructive"],
        ["Input", D.input, "Prompt tokens"],
        ["Output", D.output, "Completion tokens"],
        ["Reasoning", D.reasoning, "Reasoning blocks"],
        ["Cache read", D.cacheRead, "Cache read tokens"],
        ["Cache write", D.cacheWrite, "Cache write tokens"],
      ], true, 6) +
      F("Borders", { flex: "row", gap: 22, w: "fill", h: "hug" },
        F("B1", { flex: "row", items: "center", gap: 8, grow: 1 },
          F("Sw", { w: 44, h: 22, rounded: 6, bg: D.panel, stroke: D.border, strokeWidth: 1 }) + T("border #FFFFFF14", { size: 9, color: "#8A8A8A" })) +
        F("B2", { flex: "row", items: "center", gap: 8, grow: 1 },
          F("Sw", { w: 44, h: 22, rounded: 6, bg: D.panel, stroke: D.borderHi, strokeWidth: 1 }) + T("borderHi #FFFFFF24", { size: 9, color: "#8A8A8A" })) +
        F("B3", { flex: "row", items: "center", gap: 8, grow: 1 },
          F("Sw", { w: 44, h: 22, rounded: 6, bg: D.card, stroke: "#FFFFFF00" }) + T("card radius 14 · row radius 12", { size: 9, color: "#8A8A8A" })),
      ),
    1560,
  );

  const lightColors = lightCard(
    T("LIGHT APPEARANCE", { size: 9, weight: "bold", color: "#8A919B", letterSpacing: 0.8 }) +
      swatchRows([
        ["Backdrop", L.bg, "Window backdrop"],
        ["Panel", L.panel, "Panel surface"],
        ["Card", L.card, "White cards on cool grey"],
        ["Accent", L.accent, "Deeper green for contrast"],
        ["Running", L.running, "Deeper blue for contrast"],
        ["Warn", L.warn, "Readable amber"],
        ["Danger", L.danger, "Readable red"],
      ], false, 4) +
      T("Same semantic names; adaptive counterparts from Theme.adaptive(light:dark:).", { size: 10, color: "#6B7079", lineHeight: 15, w: "fill" }),
    780,
  );

  const typeCard = lightCard(
    T("TYPE SCALE · SYSTEM FONT", { size: 9, weight: "bold", color: "#8A919B", letterSpacing: 0.8 }) +
      F("Rows", { flex: "col", gap: 2, w: "fill", h: "hug" },
        typeRow(42, "bold", "Page title", "OpenCodeBar") +
        typeRow(28, "bold", "Display", "Usage") +
        typeRow(21, "bold", "Panel title", "OpenCode") +
        typeRow(17, "semibold", "Section", "Recent sessions") +
        typeRow(14, "semibold", "Row title", "Match iPhone dark theme") +
        typeRow(12, "semibold", "Body strong", "List tutor and participants") +
        typeRow(11, "regular", "Body", "The background shell exited; the hub is healthy.") +
        typeRow(10, "bold", "Meta / caps", "PLAN LIMITS") +
        typeRow(9, "regular", "Caption", "deepseek-v4.1-flash · 14m 04s"),
      ),
    900,
  );

  const tokens = lightCard(
    T("SPACING, RADII, ELEVATION", { size: 9, weight: "bold", color: "#8A919B", letterSpacing: 0.8 }) +
      F("Spacing", { flex: "col", gap: 7, w: "fill", h: "hug" },
        F("S1", { flex: "row", items: "center", gap: 10, h: "hug" }, F("Box", { w: 4, h: 14, bg: D.accent }) + T("4 · hairline gap", { size: 10, color: "#3C4450" })) +
        F("S2", { flex: "row", items: "center", gap: 10, h: "hug" }, F("Box", { w: 8, h: 14, bg: D.accent }) + T("8 · row gap", { size: 10, color: "#3C4450" })) +
        F("S3", { flex: "row", items: "center", gap: 10, h: "hug" }, F("Box", { w: 12, h: 14, bg: D.accent }) + T("12 · card padding", { size: 10, color: "#3C4450" })) +
        F("S4", { flex: "row", items: "center", gap: 10, h: "hug" }, F("Box", { w: 20, h: 14, bg: D.accent }) + T("20 · panel padding", { size: 10, color: "#3C4450" })) +
        F("S5", { flex: "row", items: "center", gap: 10, h: "hug" }, F("Box", { w: 36, h: 14, bg: D.accent }) + T("36 · page gutter", { size: 10, color: "#3C4450" })) +
        F("S6", { flex: "row", items: "center", gap: 10, h: "hug" }, F("Box", { w: 72, h: 14, bg: D.accent }) + T("72 · design page padding", { size: 10, color: "#3C4450" })),
      ) +
      F("Radii", { flex: "row", gap: 10, w: "fill", h: "hug" },
        F("R1", { flex: "col", gap: 4, items: "center" }, F("B", { w: 32, h: 32, rounded: 8, bg: "#E6E9EE", stroke: "#00000012", strokeWidth: 1 }) + T("8", { size: 9, color: "#6B7079" })) +
        F("R2", { flex: "col", gap: 4, items: "center" }, F("B", { w: 32, h: 32, rounded: 12, bg: "#E6E9EE", stroke: "#00000012", strokeWidth: 1 }) + T("12", { size: 9, color: "#6B7079" })) +
        F("R3", { flex: "col", gap: 4, items: "center" }, F("B", { w: 32, h: 32, rounded: 14, bg: "#E6E9EE", stroke: "#00000012", strokeWidth: 1 }) + T("14", { size: 9, color: "#6B7079" })) +
        F("R4", { flex: "col", gap: 4, items: "center" }, F("B", { w: 32, h: 32, rounded: 20, bg: "#E6E9EE", stroke: "#00000012", strokeWidth: 1 }) + T("20", { size: 9, color: "#6B7079" })) +
        F("R5", { flex: "col", gap: 4, items: "center" }, F("B", { w: 32, h: 32, rounded: 32, bg: "#E6E9EE", stroke: "#00000012", strokeWidth: 1 }) + T("pill", { size: 9, color: "#6B7079" })),
      ) +
      T("Shadows are reserved for light cards and floating docks. Dark surfaces use a 1px translucent border instead.", { size: 10, color: "#6B7079", lineHeight: 15, w: "fill" }),
    760,
  );

  const components = lightCard(
    T("CORE COMPONENTS", { size: 9, weight: "bold", color: "#8A919B", letterSpacing: 0.8 }) +
      F("R1", { flex: "row", gap: 14, w: "fill", h: "hug" },
        specimen("Chips", F("Row", { flex: "row", gap: 6, wrap: true, w: "fill", h: "hug" },
          chip("ai-tools", D.accent) + chip("deepseek-v4.1-flash", D.sec) + chip("build", D.purple, "lucide:user") + chip("Finished", D.running) + chip("Security-sensitive", D.warn, "lucide:shield-alert") + chip("Failed", D.danger, "lucide:triangle-alert")),
          "Chip: 10pt, capsule, 14% tint of the semantic color.") +
        specimen("Choice chips", F("Row", { flex: "row", gap: 4, h: "hug" },
          chip("Review 3", D.warn) + chip("Working 2", D.running) + chip("Done 12", D.sec) + chip("All 17", D.sec)),
          "Selected filters use the accent tint; counts stay monospaced.") +
        specimen("Buttons", F("Row", { flex: "row", gap: 8, wrap: true, w: "fill", h: "hug" },
          btn("New task") + btn("Sync now", "secondary") + btn("Stop", "danger") + btn("Continue", "ghost")),
          "Primary is accent on dark text; destructive is a tinted outline.") +
        specimen("Search field", input("Search projects"), "Used by Projects, Models, Files and System."),
      ) +
      F("R2", { flex: "row", gap: 14, w: "fill", h: "hug" },
        specimen("Section header", F("Col", { flex: "col", gap: 10, w: "fill", h: "hug" },
          F("H1", { flex: "row", items: "center", justify: "between", w: "fill" },
            T("RECENT SESSIONS", { size: 10, weight: "bold", color: D.sec, letterSpacing: 0.7 }) + T("All 90", { size: 10, weight: "semibold", color: D.accent })) +
          F("H2", { flex: "row", items: "center", justify: "between", w: "fill" },
            T("VIRTUAL MACHINES", { size: 10, weight: "bold", color: D.sec, letterSpacing: 0.7 }) + T("2 running", { size: 9, weight: "semibold", color: D.running }))),
          "Uppercase 10pt with 0.7 tracking; trailing count or action.") +
        specimen("Stat tile", F("Row", { flex: "row", gap: 10, w: "fill" },
          statTile("Steps", "12.582", "642 prompts", "lucide:zap", D.running) + statTile("Cost", "$14.11", "85 sessions", "lucide:circle-dollar-sign", D.accent)),
          "Two-up tiles used across Usage, Projects and Session stats.") +
        specimen("Notice", notice("lucide:triangle-alert", "Showing the last known usage. The service is unreachable.", D.warn), "Never hides stale data — labels it.") +
        specimen("Skeleton", F("Col", { flex: "col", gap: 6, w: "fill" },
          F("A", { w: "fill", h: 10, rounded: 5, bg: "#E9ECF0" }) + F("B", { w: "70%", h: 10, rounded: 5, bg: "#E9ECF0" }) + F("C", { w: "45%", h: 10, rounded: 5, bg: "#E9ECF0" })),
          "Shimmer placeholders for initial loads; no layout jump."),
      ) +
      F("R3", { flex: "row", gap: 14, w: "fill", h: "hug" },
        specimen("Plan limit", F("Col", { flex: "col", gap: 7, w: "fill" },
          F("L1", { flex: "row", justify: "between", w: "fill" }, T("Rolling", { size: 10, weight: "semibold", color: "#3C4450" }) + T("4%", { size: 10, weight: "bold", color: D.accent })) + bar(4, D.accent) +
          F("L2", { flex: "row", justify: "between", w: "fill" }, T("Weekly", { size: 10, weight: "semibold", color: "#3C4450" }) + T("16%", { size: 10, weight: "bold", color: D.accent })) + bar(16, D.accent) +
          F("L3", { flex: "row", justify: "between", w: "fill" }, T("Monthly", { size: 10, weight: "semibold", color: "#3C4450" }) + T("49%", { size: 10, weight: "bold", color: D.warn })) + bar(49, D.warn)),
          "Hidden entirely when no Go key is configured.") +
        specimen("Empty state", emptyState("lucide:server", "No virtual machines", "Create a NixOS guest. The hub builds a raw EFI image and runs it with Virtualization.framework.", { color: D.sec }), "Icon well + title + one sentence, never a dead end.") +
        specimen("Tab bar · 3", F("Row", { flex: "row", gap: 2, p: 3, rounded: 12, bg: "#E6E9EE", w: "fill", h: "hug" },
          F("T1", { flex: "row", gap: 4, grow: 1, items: "center", justify: "center", py: 6, rounded: 9, bg: "#FFFFFF" }, I("lucide:radio", 11, "#171B21") + T("Live", { size: 11, weight: "semibold", color: "#171B21" })) +
          F("T2", { flex: "row", gap: 4, grow: 1, items: "center", justify: "center", py: 6 }, I("lucide:bar-chart-3", 11, "#6B7079") + T("Usage", { size: 11, color: "#6B7079" })) +
          F("T3", { flex: "row", gap: 4, grow: 1, items: "center", justify: "center", py: 6 }, I("lucide:folder", 11, "#6B7079") + T("Projects", { size: 11, color: "#6B7079" }))),
          "Compact panel switcher; seven tabs shrink labels to 9.5pt.") +
        specimen("Status pill", F("Row", { flex: "row", gap: 6, h: "hug" },
          F("P", { flex: "row", gap: 4, px: 8, py: 3, rounded: 99, bg: "#4DD9A018" }, F("D", { w: 5, h: 5, rounded: 3, bg: D.accent }) + T("Connected · v2.1.4", { size: 9, color: D.accent })) +
          F("P2", { flex: "row", gap: 4, px: 8, py: 3, rounded: 99, bg: "#F7B84B18" }, I("lucide:pause", 8, D.warn) + T("Paused until 21:40", { size: 9, color: D.warn }))),
          "Connection and hold state share one pill shape."),
      ),
    1560,
  );

  const domain = lightCard(
    T("DOMAIN COMPONENTS", { size: 9, weight: "bold", color: "#8A919B", letterSpacing: 0.8 }) +
      F("R1", { flex: "row", gap: 14, w: "fill", h: "hug" },
        specimen("Running session row", F("Card", { flex: "col", gap: 7, p: 12, rounded: 12, bg: D.panel, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
          F("T", { flex: "row", items: "center", gap: 7, w: "fill" },
            F("Dot", { w: 7, h: 7, rounded: 4, bg: D.running }) +
            T("Match iPhone dark theme to macOS tray app", { size: 12, weight: "semibold", color: D.text, w: "fill" }) +
            T("14m 04s", { size: 9, color: D.running })) +
          F("A", { flex: "row", items: "center", gap: 6, w: "fill" },
            I("lucide:terminal", 10, D.warn) + T("Running · npm run build --watch", { size: 10, color: D.warn, w: "fill" }) + T("4s", { size: 9, color: D.ter })) +
          F("M", { flex: "row", items: "center", gap: 5, w: "fill" },
            chip("ai-tools", D.accent) + chip("deepseek-v4.1-flash", D.sec) + chip("build", D.purple, "lucide:user")) +
          F("F", { flex: "row", items: "center", gap: 8, w: "fill" },
            I("lucide:clock", 9, D.ter) + T("14m 04s", { size: 9, color: D.ter }) + T("$0.41", { size: 9, color: D.accent }) + I("lucide:list", 9, D.ter) + T("1.2M tok", { size: 9, color: D.ter }))),
          "Live rows carry a pulsing dot, current tool, project, model, agent, cost and tokens.", 430) +
        specimen("Task card", F("Card", { flex: "row", gap: 9, p: 10, rounded: 12, bg: D.panel, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
          F("Status", { w: 18, h: 18, rounded: 9, bg: D.warn + "22", items: "center", justify: "center" }, I("lucide:eye", 10, D.warn)) +
          F("Body", { flex: "col", gap: 5, grow: 1, w: "fill" },
            T("Add map-based language family quiz", { size: 12, weight: "semibold", color: D.text, w: "fill" }) +
            T("stuttgart-uni-assistant · 48m ago", { size: 9, color: D.sec }) +
            F("Labels", { flex: "row", gap: 4, wrap: true, w: "fill", h: "hug" }, chip("Feature", D.accent, "lucide:sparkles") + chip("Product", D.running) + chip("Breaking change", D.warn, "lucide:triangle-alert"))) +
          I("lucide:ellipsis", 12, D.sec)),
          "Labels come from the request without a model call.", 430) +
        specimen("Project row", F("Card", { flex: "row", gap: 9, p: 10, rounded: 12, bg: D.panel, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
          F("Icon", { w: 34, h: 34, rounded: 9, bg: "#2F7CF6", items: "center", justify: "center" }, T("AT", { size: 12, weight: "bold", color: "#FFFFFF" })) +
          F("Body", { flex: "col", gap: 3, grow: 1 },
            F("N", { flex: "row", items: "center", gap: 6 }, T("ai-tools", { size: 12, weight: "bold", color: D.text }) + chip("git", D.purple)) +
            T("~/Developer/ai-tools", { size: 9, color: D.sec })) +
          F("Right", { flex: "col", gap: 3, items: "end" }, T("2", { size: 9, weight: "bold", color: D.running }) + T("just now", { size: 9, color: D.ter }))),
          "Running count first, then most recently active.", 430),
      ) +
      F("R2", { flex: "row", gap: 14, w: "fill", h: "hug" },
        specimen("VM row", F("Card", { flex: "row", gap: 9, p: 10, rounded: 12, bg: D.panel, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
          F("Status", { w: 26, h: 26, rounded: 8, bg: D.accent + "1F", items: "center", justify: "center" }, I("lucide:server", 13, D.accent)) +
          F("Body", { flex: "col", gap: 3, grow: 1 },
            T("nixos-dev", { size: 12, weight: "bold", color: D.text }) +
            T("NixOS · running · 192.168.64.12", { size: 9, color: D.sec }) +
            T("2 CPU · 4 GB · 20 GB disk", { size: 9, color: D.ter })) +
          chip("Stop", D.warn)),
          "Lifecycle actions inline; setup problems surface as a card.", 430) +
        specimen("Device row", F("Card", { flex: "row", gap: 9, p: 10, rounded: 12, bg: D.panel, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
          F("Icon", { w: 30, h: 30, rounded: 8, bg: D.running + "1F", items: "center", justify: "center" }, I("lucide:smartphone", 14, D.running)) +
          F("Body", { flex: "col", gap: 2, grow: 1 }, T("Oliver’s iPhone", { size: 11, weight: "semibold", color: D.text }) + T("iOS 18.2 · 1.0 (42) · live now", { size: 9, color: D.sec })) +
          chip("live", D.accent)),
          "Settings lists every paired client with live state.", 430) +
        specimen("Message + tool cards", F("Col", { flex: "col", gap: 6, w: "fill", h: "hug" },
          F("Msg", { flex: "col", gap: 5, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
            F("H", { flex: "row", items: "center", gap: 5 }, I("lucide:sparkles", 10, D.running) + T("Assistant", { size: 10, weight: "bold", color: D.running }) + F("S", { grow: 1 }) + T("38m ago", { size: 9, color: D.ter })) +
            T("The hub is still running detached and healthy.", { size: 10, color: D.sec })) +
          F("Tool", { flex: "row", gap: 6, p: 8, rounded: 10, bg: "#59D6A10E", stroke: "#59D6A12E", strokeWidth: 1, w: "fill" },
            I("lucide:terminal", 10, D.output) + T("shell", { size: 9, weight: "bold", color: D.output }) + T("npm test", { size: 9, color: D.sec, w: "fill" }) + I("lucide:check", 10, D.accent))),
          "Reasoning, tool and text parts share one card rhythm.", 430),
      ),
    1560,
  );

  const iconsCard = lightCard(
    T("ICONOGRAPHY · SF SYMBOLS → LUCIDE", { size: 9, weight: "bold", color: "#8A919B", letterSpacing: 0.8 }) +
      F("Grid", { flex: "row", gap: 10, wrap: true, w: "fill", h: "hug" },
        [
          ["lucide:terminal", "terminal"],
          ["lucide:list-checks", "checklist"],
          ["lucide:radio", "dot.radiowaves"],
          ["lucide:folder", "folder.fill"],
          ["lucide:bar-chart-3", "chart.bar.fill"],
          ["lucide:monitor", "desktopcomputer"],
          ["lucide:server", "server.rack"],
          ["lucide:settings", "gearshape.fill"],
          ["lucide:git-branch", "arrow.triangle.branch"],
          ["lucide:file-diff", "doc.text"],
          ["lucide:mic", "mic.fill"],
          ["lucide:qr-code", "qrcode"],
          ["lucide:pause", "pause.fill"],
          ["lucide:play", "play.fill"],
          ["lucide:shield-check", "checkmark.shield"],
          ["lucide:cpu", "cpu"],
        ].map(([icon, name]) =>
          F("Icon cell", { flex: "col", gap: 5, items: "center", w: 76, h: "hug", p: 8, rounded: 10, bg: "#F7F8FA", stroke: "#00000010", strokeWidth: 1 },
            I(icon, 19, "#3C4450") + T(name, { size: 8, color: "#7A828C", textAlign: "center" }))).join(""),
      ) +
      T("Icons are paired with text everywhere; color carries state, never meaning alone.", { size: 9, color: "#8A919B", lineHeight: 13, w: "fill" }),
    1000,
  );

  const dataCard = lightCard(
    T("DATA DISPLAY", { size: 9, weight: "bold", color: "#8A919B", letterSpacing: 0.8 }) +
      F("Trend", { flex: "col", gap: 6, w: "fill", h: "hug" },
        F("H", { flex: "row", justify: "between", w: "fill" }, T("30 DAYS · STEPS", { size: 9, weight: "bold", color: "#8A919B" }), T("2.6k peak", { size: 9, color: "#6B7079" })) +
        F("Bars", { flex: "row", items: "end", gap: 4, w: "fill", h: 110 },
          [22, 30, 18, 44, 38, 52, 26, 60, 48, 70, 36, 58, 66, 40, 74, 55, 80, 62, 90, 68, 84, 96, 72, 88, 60, 78, 54, 70, 46, 58]
            .map((h) => F("Bar", { w: 12, h, rounded: 3, bg: "#5CCCFA" })).join("")),
      ) +
      F("Heatmap", { flex: "col", gap: 5, w: "fill", h: "hug" },
        T("ACTIVITY HEATMAP", { size: 9, weight: "bold", color: "#8A919B" }) +
        F("Grid", { flex: "col", gap: 3, w: "fill", h: "hug" },
          Array.from({ length: 6 }, (_, r) =>
            F("Week", { flex: "row", gap: 3, w: "fill" },
              Array.from({ length: 14 }, (_, c) =>
                F("Day", { w: 14, h: 14, rounded: 3, bg: ["#E9ECF0", "#C9F0E2", "#8EE3C5", "#4DD9A0", "#0B8F65"][(r * 7 + c * 3) % 5] })).join(""))).join("")),
      ) +
      F("Diff", { flex: "col", gap: 4, p: 9, rounded: 9, bg: "#0F1A14", w: "fill", h: "hug" },
        T("Views/Theme.swift", { size: 8, weight: "bold", color: "#8A919B" }) +
        T("+ static let accent = adaptive(light: …)", { size: 8, color: D.output }) +
        T("- static let accent = Color(red: 0.30 …)", { size: 8, color: D.danger }) +
        T("  static let running = adaptive(light: …)", { size: 8, color: "#9AA0A8" })),
    1000,
  );

  const motionCard = lightCard(
    T("INTERACTION & ACCESSIBILITY", { size: 9, weight: "bold", color: "#8A919B", letterSpacing: 0.8 }) +
      F("States", { flex: "col", gap: 8, w: "fill", h: "hug" },
        T("INTERACTIVE STATES", { size: 9, weight: "bold", color: "#8A919B" }) +
        F("Row", { flex: "row", gap: 8, w: "fill" },
          F("Default", { flex: "col", items: "center", gap: 4, grow: 1 }, F("B", { w: "fill", h: 30, rounded: 9, bg: "#F1F3F6", stroke: "#00000014", strokeWidth: 1, items: "center", justify: "center" }, T("Default", { size: 9, color: "#4C545E" }))) +
          F("Hover", { flex: "col", items: "center", gap: 4, grow: 1 }, F("B", { w: "fill", h: 30, rounded: 9, bg: "#E9ECF0", stroke: "#0000001F", strokeWidth: 1, items: "center", justify: "center" }, T("Hover", { size: 9, color: "#20252C" }))) +
          F("Pressed", { flex: "col", items: "center", gap: 4, grow: 1 }, F("B", { w: "fill", h: 30, rounded: 9, bg: "#DDE1E7", stroke: "#00000024", strokeWidth: 1, items: "center", justify: "center" }, T("Pressed", { size: 9, color: "#20252C" }))) +
          F("Selected", { flex: "col", items: "center", gap: 4, grow: 1 }, F("B", { w: "fill", h: 30, rounded: 9, bg: "#0B8F6518", stroke: "#0B8F654D", strokeWidth: 1, items: "center", justify: "center" }, T("Selected", { size: 9, weight: "semibold", color: "#0B8F65" })))),
      ) +
      F("Motion", { flex: "col", gap: 5, w: "fill", h: "hug" },
        T("MOTION", { size: 9, weight: "bold", color: "#8A919B" }) +
        T("• New live rows animate in at the top (0.18s ease-out).", { size: 9, color: "#4C545E" }) +
        T("• Tab indicator uses matchedGeometryEffect; content switches immediately.", { size: 9, color: "#4C545E" }) +
        T("• Shimmer only on initial loads; refreshes keep the old rows.", { size: 9, color: "#4C545E" }) +
        T("• Reduce Motion respected by SwiftUI transitions.", { size: 9, color: "#4C545E" }),
      ) +
      F("A11y", { flex: "col", gap: 5, w: "fill", h: "hug" },
        T("ACCESSIBILITY", { size: 9, weight: "bold", color: "#8A919B" }) +
        T("• 4.5:1 minimum for body text in both appearances.", { size: 9, color: "#4C545E" }) +
        T("• Status is always icon + label, never color alone.", { size: 9, color: "#4C545E" }) +
        T("• Dynamic Type: rows grow, counts stay monospaced.", { size: 9, color: "#4C545E" }) +
        T("• VoiceOver labels for running, paused, failed and queued states.", { size: 9, color: "#4C545E" }),
      ) +
      T("Tap targets are at least 28pt on macOS and 44pt on iOS; the dock adds 6pt of padding around each item.", { size: 9, color: "#8A919B", lineHeight: 13, w: "fill" }),
    1000,
  );

  return page({
    title: "Design system",
    subtitle: "One shared palette and component language for macOS, iPhone, iPad and the widgets. Everything here is drawn from the SwiftUI sources so a new screen can be composed without inventing styles.",
    meta: "Sources: Views/Theme.swift · Views/Components.swift · MobileTheme.swift · WidgetTheme.swift",
    width: 2800,
    children:
      row("Palette + icons", darkColors + iconsCard, { gap: 28 }) +
      row("Light + type + spacing", lightColors + typeCard + tokens, { gap: 28 }) +
      row("Components + data", components + dataCard, { gap: 28 }) +
      row("Domain + interaction", domain + motionCard, { gap: 28 }),
  });
}
