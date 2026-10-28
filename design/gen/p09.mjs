import { D, L, F, T, I, chip, card, sectionLabel, pageParts, group, bar, notice, emptyState, phone, panel, macTabs4, iconButton } from "./kit.mjs";

const emptyCard = (icon, title, sub, color = D.sec) =>
  F("Empty", { flex: "col", gap: 6, items: "center", p: 16, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 330, h: 170, justify: "center" },
    F("Well", { w: 34, h: 34, rounded: 10, bg: color + "16", items: "center", justify: "center" }, I(icon, 17, color)) +
    T(title, { size: 12, weight: "semibold", color: "#20252C", textAlign: "center" }) +
    T(sub, { size: 9, color: "#6B7079", textAlign: "center", lineHeight: 13, w: 270 }),
  );

const stateCard = (title, note, node) =>
  F("State card", { flex: "col", gap: 8, w: 620, h: "hug" },
    T(title, { size: 13, weight: "semibold", color: "#2B3038" }) + T(note, { size: 10, color: "#6B7079", lineHeight: 14, w: 600 }) + node,
  );

export default function () {
  const empties = F("Empty grid", { flex: "row", gap: 12, wrap: true, w: "fill", h: "hug" },
    emptyCard("lucide:list-checks", "No tasks yet", "New sessions become tasks. Finished work lands here for review.") +
    emptyCard("lucide:radio", "No sessions running", "Start a session from Projects or New task.") +
    emptyCard("lucide:folder", "No projects yet", "OpenCode projects appear after the first session.") +
    emptyCard("lucide:server", "No virtual machines", "Create a NixOS guest; the hub builds the image.") +
    emptyCard("lucide:terminal", "No terminals", "Start a shell in any project to see it here.") +
    emptyCard("lucide:git-branch", "Not a git repository", "Git data is unavailable; files and sessions still work.") +
    emptyCard("lucide:search", "No matches", "Try a different search or clear the filters.") +
    emptyCard("lucide:file-diff", "No changes yet", "Patches appear after the session edits a file.") +
    emptyCard("lucide:git-fork", "No subagents", "Child sessions appear here when work is delegated.") +
    emptyCard("lucide:key-round", "No Go plan key", "Add a usage key to see rolling, weekly and monthly limits.") +
    emptyCard("lucide:cloud-off", "Hub offline", "Showing the last snapshot from local SQLite.") +
    emptyCard("lucide:monitor-off", "Remote needs permission", "Enable Screen Recording to stream this Mac."),
  );

  const loading = F("Loading", { flex: "row", gap: 12, wrap: true, w: "fill", h: "hug" },
    F("Skeleton panel", { flex: "col", gap: 8, p: 14, rounded: 14, bg: D.panel, w: 340, h: 300, stroke: D.border, strokeWidth: 1 },
      F("A", { w: 110, h: 10, rounded: 5, bg: "#3A3A3A" }) +
      [1, 2, 3].map(() => F("Card", { flex: "col", gap: 6, p: 10, rounded: 10, bg: D.card }, F("B", { w: "fill", h: 9, rounded: 4, bg: "#3A3A3A" }) + F("C", { w: "70%", h: 9, rounded: 4, bg: "#333333" }) + F("D", { w: "45%", h: 8, rounded: 4, bg: "#333333" }))).join("")) +
    F("Shimmer", { flex: "col", gap: 8, p: 14, rounded: 14, bg: "#FFFFFF", w: 340, h: 300, stroke: "#00000012", strokeWidth: 1 },
      F("A", { w: 110, h: 10, rounded: 5, bg: "#E9ECF0" }) +
      [1, 2, 3].map(() => F("Card", { flex: "col", gap: 6, p: 10, rounded: 10, bg: "#F7F8FA" }, F("B", { w: "fill", h: 9, rounded: 4, bg: "#E9ECF0" }) + F("C", { w: "70%", h: 9, rounded: 4, bg: "#E9ECF0" }))).join("")),
  );

  const banners = F("Banners", { flex: "row", gap: 12, wrap: true, w: "fill", h: "hug" },
    F("Col", { flex: "col", gap: 10, w: 620, h: "hug" },
      notice("lucide:cloud-off", "Showing the last known usage. The service is unreachable; numbers may be stale.", D.warn) +
      notice("lucide:triangle-alert", "GET /api/usage returned 503. Cached values are still shown.", D.danger) +
      notice("lucide:info", "History is still loading; totals cover the loaded window.", D.sec) +
      notice("lucide:lock", "The hub token is invalid. Re-pair this device to continue.", D.danger) +
      notice("lucide:refresh-cw", "Hub restarting. Clients reconnect automatically; no data is lost.", D.running)) +
    F("Col", { flex: "col", gap: 10, w: 620, h: "hug" },
      F("Offline", { flex: "col", gap: 6, p: 12, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: "fill" },
        T("Hub unreachable", { size: 13, weight: "bold", color: "#20252C" }) +
        T("The phone keeps rendering its SQLite snapshot. New prompts are disabled until the hub returns.", { size: 10, color: "#6B7079", lineHeight: 14 }) +
        F("Actions", { flex: "row", gap: 6, w: "fill" }, F("A", { px: 10, py: 6, rounded: 8, bg: L.accent }, T("Retry", { size: 10, weight: "bold", color: "#FFFFFF" })) + F("B", { px: 10, py: 6, rounded: 8, bg: "#F1F3F6" }, T("Open Settings", { size: 10, color: "#2B3038" })))) +
      F("Unauthorized", { flex: "col", gap: 6, p: 12, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: "fill" },
        T("Pairing expired", { size: 13, weight: "bold", color: "#20252C" }) +
        T("The hub rejected this device's token. Scan the QR code again; the token is stored only on the device.", { size: 10, color: "#6B7079", lineHeight: 14 }) +
        F("Actions", { flex: "row", gap: 6, w: "fill" }, F("A", { px: 10, py: 6, rounded: 8, bg: L.accent }, T("Scan QR code", { size: 10, weight: "bold", color: "#FFFFFF" }))))),
  );

  const permissions = F("Permissions", { flex: "row", gap: 12, wrap: true, w: "fill", h: "hug" },
    F("Perm", { flex: "col", gap: 6, p: 12, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 400, h: "hug" },
      F("H", { flex: "row", items: "center", gap: 6 }, I("lucide:monitor", 14, L.warn) + T("Screen Recording", { size: 12, weight: "bold", color: "#20252C" }) + F("S", { grow: 1 }) + chip("required", L.warn)) +
      T("The ScreenCaptureKit helper needs this to capture a display. Open System Settings → Privacy & Security → Screen Recording.", { size: 9, color: "#6B7079", lineHeight: 13 }) +
      chip("Open Settings", L.accent)) +
    F("Perm", { flex: "col", gap: 6, p: 12, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 400, h: "hug" },
      F("H", { flex: "row", items: "center", gap: 6 }, I("lucide:hand", 14, L.accent) + T("Accessibility", { size: 12, weight: "bold", color: "#20252C" }) + F("S", { grow: 1 }) + chip("input", L.accent)) +
      T("Without Accessibility the stream stays view-only. Taps, drags and keys are not sent to the Mac.", { size: 9, color: "#6B7079", lineHeight: 13 }) +
      chip("View-only is fine", L.sec)),
  );

  const longContent = F("Long content", { flex: "row", gap: 12, wrap: true, w: "fill", h: "hug" },
    F("Card", { flex: "col", gap: 5, p: 12, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 600, h: "hug" },
      T("Very long session title wraps to two lines and then truncates", { size: 14, weight: "semibold", color: "#20252C", w: "fill", maxLines: 2, truncate: true }) +
      T("stuttgart-uni-assistant · deepseek-v4.1-flash · build", { size: 9, color: "#6B7079" }) +
      T("A very long tool command that must not push the row wider than the panel: `npm run build --workspace @open-pencil/core -- --watch --mode production`.", { size: 9.5, color: "#4C545E", lineHeight: 14, w: "fill" })) +
    F("Card", { flex: "col", gap: 5, p: 12, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 600, h: "hug" },
      T("Narrow window", { size: 12, weight: "bold", color: "#20252C" }) +
      T("At narrow widths the desktop window falls back to one page and the panel keeps its 800pt composition. Lists never collapse into unlabeled icons.", { size: 9.5, color: "#4C545E", lineHeight: 14, w: "fill" }) +
      F("Row", { flex: "row", gap: 5, w: "fill" }, chip("≥ 1180 · 3 columns", L.accent) + chip("≥ 760 · 2 columns", L.sec) + chip("< 760 · 1 page", L.sec))),
  );

  const lightPanel = panel({ tabs: macTabs4, active: "Live", dark: false, name: "Light panel", children:
    sectionLabel("Running", T("2", { size: 10, weight: "bold", color: L.running }), L.ter) +
    F("Row", { flex: "col", gap: 5, p: 10, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: "fill" },
      F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, F("Dot", { w: 7, h: 7, rounded: 4, bg: L.running }) + T("Match iPhone dark theme to macOS tray app", { size: 12, weight: "semibold", color: L.text, w: "fill" }) + T("14m 04s", { size: 9, color: L.running })) +
      F("A", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:terminal", 9, L.warn) + T("Running · npm run build --watch", { size: 9, color: L.warn, w: "fill" })) +
      F("M", { flex: "row", gap: 4, w: "fill" }, chip("ai-tools", L.accent) + chip("deepseek-v4.1-flash", L.sec) + chip("build", L.accent))) +
    sectionLabel("Recent", T("All 90", { size: 10, color: L.accent }), L.ter) +
    F("Recent", { flex: "col", gap: 4, p: 10, rounded: 11, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: "fill" },
      T("Mobile app with shared server and SQLite database", { size: 11, weight: "semibold", color: L.text }) +
      F("M", { flex: "row", gap: 4, w: "fill" }, T("ai-tools", { size: 8, color: L.accent, w: "fill" }) + chip("deepseek-v4.1-flash", L.sec) + T("$0.29", { size: 8, color: L.accent }))),
  });

  return pageParts({
    title: "States and edge cases",
    subtitle: "A product is only as good as its empty, loading, stale and failure states. This page proves every list has an explanation, every failure is recoverable, and both appearances keep contrast.",
    meta: "Sources: PerformanceViews.swift · SessionDetailView+Pieces.swift · MobileStore · HubEventStream.swift · RemoteDesktopView.swift · UsageCache.swift",
    width: 2400,
    sections: [
      group("Every list has an empty state", "Icon well, a sentence about what will appear, and the action that creates it.", [
        empties,
      ].join("")),
      group("Loading, errors and recovery", "Skeletons keep the layout; stale data is labelled, never hidden; failures offer a next step.", [
        stateCard("Loading", "Initial loads show skeletons. Refreshes keep the previous rows and never flash an empty state.", loading) +
        stateCard("Banners", "Warning, danger and info banners share one shape; the message names the next action.", banners) +
        stateCard("Permissions", "Remote desktop is explicit about what is missing and what still works.", permissions),
      ].join("")),
      group("Long content and light appearance", "Truncation is intentional, and light mode is a first-class appearance rather than an inverted theme.", [
        longContent +
        F("Col", { flex: "col", gap: 10 }, T("Light panel", { size: 13, weight: "semibold", color: "#2B3038" }), lightPanel),
      ].join("")),
      group("Accessibility notes", "What the design guarantees, in both appearances.", [
        F("Grid", { flex: "row", gap: 12, wrap: true, w: "fill", h: "hug" },
          ["4.5:1 minimum contrast for body text", "Status is icon + label, never color alone", "Tap targets ≥ 44pt on iOS, ≥ 28pt on macOS", "Dynamic Type grows rows; counts stay monospaced", "VoiceOver labels for running, paused, failed and queued", "Reduce Motion respected by transitions"].map((t) =>
            F("A", { flex: "row", items: "start", gap: 6, p: 10, rounded: 10, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: 420, h: "hug" }, I("lucide:check-circle", 12, L.accent) + T(t, { size: 10, color: "#3C4450", lineHeight: 14, w: "fill" }))).join("")),
      ].join("")),
    ],
  });
}
