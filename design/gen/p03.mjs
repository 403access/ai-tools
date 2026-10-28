import { D, F, T, I, chip, card, sectionLabel, pageParts, group, bar, notice, emptyState, iconButton } from "./kit.mjs";

const dot = (color = D.running) => F("Dot", { w: 7, h: 7, rounded: 4, bg: color });

const sessionTabs = (active) =>
  F("Session tabs", { flex: "row", gap: 2, p: 3, rounded: 10, bg: "#262626", w: "fill", h: "hug" },
    [["Conversation", "lucide:message-circle"], ["Stats", "lucide:bar-chart-3"], ["Changes", "lucide:file-diff"], ["Prompts", "lucide:message-square"], ["Git", "lucide:git-branch"], ["Subagents", "lucide:git-fork"]]
      .map(([l, i]) => F("Tab", { flex: "row", items: "center", justify: "center", gap: 3, grow: 1, py: 6, rounded: 8, bg: l === active ? "#404040" : "#FFFFFF00" },
        I(i, 10, l === active ? D.text : D.sec) + T(l, { size: 8.5, weight: l === active ? "semibold" : "regular", color: l === active ? D.text : D.sec }))).join(""));

const sessionShell = ({ name, active, children, finished = true, held = "", title = "Show actual changes and diffs in session and project views", sub = "ai-tools · deepseek-v4.1-flash · build" }) =>
  F(name, { flex: "col", gap: 10, w: 800, h: 1200, p: 0, bg: D.panel, rounded: 20, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
    F("Top", { flex: "row", items: "center", gap: 8, w: "fill", px: 20, py: 12 },
      I("lucide:chevron-left", 12, D.accent) + T("Live", { size: 11, color: D.accent }) + F("S", { grow: 1 }) +
      iconButton("lucide:plus", D.accent, 12) +
      chip(finished ? "Finished" : "Running", finished ? D.sec : D.running)) +
    F("Header wrap", { flex: "col", gap: 10, px: 20, w: "fill", h: "hug" },
    F("Header", { flex: "col", gap: 7, p: 12, rounded: 14, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      T(title, { size: 16, weight: "bold", color: D.text, w: "fill" }) +
      F("Meta", { flex: "row", gap: 5, w: "fill" }, chip("ai-tools", D.accent) + chip("deepseek-v4.1-flash", D.sec) + chip("build", D.purple, "lucide:user") + (held ? chip(held, D.warn, "lucide:pause") : "")) +
      F("Stats", { flex: "row", gap: 12, items: "center", w: "fill" },
        I("lucide:clock", 9, D.ter) + T("1h 28m", { size: 9, color: D.sec }) +
        I("lucide:list", 9, D.ter) + T("975k tok", { size: 9, color: D.sec }) +
        T("$0.35", { size: 9, weight: "semibold", color: D.accent }) + F("S", { grow: 1 }) +
        T("fork of ses_7c21", { size: 9, color: D.ter }))) +
    F("Tabs wrap", { flex: "row", w: "fill", h: "hug" }, sessionTabs(active))) +
    F("Body", { flex: "col", gap: 10, px: 20, py: 6, grow: 1, w: "fill", overflow: "hidden" }, children) +
    F("Footer", { flex: "row", items: "center", justify: "between", px: 20, py: 9, w: "fill", bg: "#191919", stroke: "#FFFFFF10", strokeWidth: 1 },
      F("Active", { flex: "row", items: "center", gap: 5 }, dot(D.running), T("2 active", { size: 10, color: D.sec })) + T("Updated just now", { size: 10, color: D.ter })),
  );

const message = (who, tint, icon, time, body, reasoning = "") =>
  F("Message", { flex: "col", gap: 6, p: 11, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
    F("H", { flex: "row", items: "center", gap: 5, w: "fill" }, I(icon, 10, tint) + T(who, { size: 10, weight: "bold", color: tint }) + F("S", { grow: 1 }) + T(time, { size: 9, color: D.ter })) +
    (reasoning ? F("Reason", { flex: "col", gap: 3, p: 8, rounded: 8, bg: D.reasoning + "10", stroke: D.reasoning + "22", strokeWidth: 1, w: "fill" },
      F("RH", { flex: "row", items: "center", gap: 5 }, I("lucide:brain", 9, D.reasoning) + T("Reasoning", { size: 9, weight: "bold", color: D.reasoning }) + F("S", { grow: 1 }) + I("lucide:chevron-down", 9, D.reasoning)) +
      T(reasoning, { size: 9, color: "#C9B6D8", lineHeight: 13, w: "fill" })) : "") +
    T(body, { size: 10, color: "#D0D0D0", lineHeight: 15, w: "fill" }),
  );

const toolCall = (name, cmd, ok = true) =>
  F("Tool call", { flex: "row", items: "center", gap: 6, p: 9, rounded: 9, bg: D.output + "0C", stroke: D.output + "2A", strokeWidth: 1, w: "fill" },
    I("lucide:terminal", 10, D.output) + T(name, { size: 9, weight: "bold", color: D.output }) + T(cmd, { size: 9, color: D.sec, w: "fill" }) + I(ok ? "lucide:check" : "lucide:x", 10, ok ? D.accent : D.danger));

const conversation = sessionShell({ name: "Session · Conversation", active: "Conversation", children:
  message("Assistant", D.running, "lucide:sparkles", "38m ago", "Working…") +
  message("Assistant", D.running, "lucide:sparkles", "38m ago", "The background shell that was streaming the hub exited, but the hub itself is still running detached and healthy:\n\n• PID 78224 (parent PID 1, so it survives the shell)\n• Listening on http://127.0.0.1:8788\n• /api/health → 200\n• /api/session/:id/stats → 200\n• No duplicate hub processes\n\nSo the Stats tab should no longer return 404. No code changes were needed.", "Single hub, detached (PPID 1), stats 200. We can tell the user the background wrapper stopped, but the hub itself is running detached and healthy.") +
  toolCall("shell", "ps -o pid,ppid,command -p 78224") +
  message("Assistant", D.running, "lucide:sparkles", "38m ago", "Working…"),
});

const stats = sessionShell({ name: "Session · Stats", active: "Stats", children:
  F("Tiles", { flex: "row", gap: 10, w: "fill" },
    card(T("STEPS", { size: 9, weight: "bold", color: D.sec }) + T("159", { size: 26, weight: "bold", color: D.text }) + T("9 prompts", { size: 9, color: D.ter }), { p: 11, gap: 3, w: "fill" }) +
    card(T("TOOL CALLS", { size: 9, weight: "bold", color: D.sec }) + T("175", { size: 26, weight: "bold", color: D.text }) + T("0 failed", { size: 9, color: D.ter }), { p: 11, gap: 3, w: "fill" })) +
  F("Tiles2", { flex: "row", gap: 10, w: "fill" },
    card(T("FILES", { size: 9, weight: "bold", color: D.sec }) + T("13", { size: 26, weight: "bold", color: D.text }) + T("+223 −90", { size: 9, color: D.ter }), { p: 11, gap: 3, w: "fill" }) +
    card(T("DURATION", { size: 9, weight: "bold", color: D.sec }) + T("1h 28m", { size: 26, weight: "bold", color: D.text }) + T("0 subagents", { size: 9, color: D.ter }), { p: 11, gap: 3, w: "fill" })) +
  sectionLabel("Reliability", T("99% success", { size: 9, weight: "semibold", color: D.accent })) +
  card(
    F("H", { flex: "row", justify: "between", w: "fill" }, T("CALLS", { size: 9, weight: "bold", color: D.sec }), T("SUCCEEDED", { size: 9, weight: "bold", color: D.sec }), T("FAILED", { size: 9, weight: "bold", color: D.sec }), T("UNFINISHED", { size: 9, weight: "bold", color: D.sec })) +
    F("V", { flex: "row", justify: "between", w: "fill" }, T("175", { size: 18, weight: "bold", color: D.text }), T("174", { size: 18, weight: "bold", color: D.accent }), T("0", { size: 18, weight: "bold", color: D.text }), T("1", { size: 18, weight: "bold", color: D.warn })) +
    bar(99, D.accent, 6),
    { p: 11, gap: 8 }) +
  sectionLabel("Tools", T("4", { size: 9, color: D.ter })) +
  F("Tools", { flex: "col", gap: 6, w: "fill" },
    [["shell", "111ms · 99×", 100], ["edit", "9ms · 48×", 60], ["read", "4ms · 26×", 34], ["todowrite", "2ms · 2×", 4]].map(([n, m, p]) =>
      F("Tool", { flex: "col", gap: 4, w: "fill", p: 9, rounded: 9, bg: D.card, stroke: D.border, strokeWidth: 1 },
        F("H", { flex: "row", justify: "between", w: "fill" }, T(n, { size: 10, weight: "semibold", color: D.text }), T(m, { size: 9, color: D.sec })) + bar(p, D.accent, 4))).join("")) +
  notice("lucide:info", "Totals cover the loaded history window; older pages are read on demand.", D.sec),
});

const diffCard = (file, add, rem, lines) =>
  F("Patch", { flex: "col", gap: 6, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, I("lucide:file-code", 10, D.sec) + T(file, { size: 10, weight: "semibold", color: D.text, w: "fill" }) + T(`+${add}`, { size: 9, color: D.accent }) + T(`−${rem}`, { size: 9, color: D.danger })) +
    F("Diff", { flex: "col", gap: 2, p: 7, rounded: 7, bg: "#101010", w: "fill" },
      lines.map(([kind, s]) => T(s, { size: 8.5, color: kind === "+" ? D.output : kind === "-" ? D.danger : "#8A8A8A", w: "fill" })).join("")));

const changes = sessionShell({ name: "Session · Changes", active: "Changes", children:
  F("Summary", { flex: "row", items: "center", gap: 6, w: "fill" }, T("13 files changed", { size: 11, weight: "semibold", color: D.text }) + T("+223", { size: 10, color: D.accent }) + T("−90", { size: 10, color: D.danger }) + F("S", { grow: 1 }) + chip("Group by file", D.sec) + iconButton("lucide:layout-list", D.sec, 11)) +
  diffCard("Sources/OpenCodeBar/Views/Theme.swift", 12, 4, [[" ", " static let accent = adaptive("], ["+", "   light: (0.043, 0.560, 0.396),"], ["-", "   light: (0.10, 0.62, 0.44),"], [" ", "   dark: (0.30, 0.85, 0.62))"]]) +
  diffCard("Sources/OpenCodeBar/Views/LiveTab.swift", 41, 18, [["+", " ForEach(state.runningSessions) { session in"], ["+", "   LiveRunningRow(session: session)"], ["-", " ForEach(state.sessions.prefix(3)) { session in"], [" ", "   Divider()"]]) +
  diffCard("server/src/hub/sync.ts", 18, 7, [["+", " const delta = await db.sessionsSince(since)"], ["+", " if (delta.length) bus.emit('hub.sessions')"], ["-", " await refreshAllSessions()"]]) +
  F("More", { flex: "row", items: "center", justify: "center", gap: 5, py: 7, rounded: 8, bg: "#FFFFFF08", w: "fill" }, T("Show 10 more files", { size: 10, color: D.sec })) +
  T("Long patches collapse to a preview; the file tree layout shows one file at a time.", { size: 9, color: D.ter, w: "fill" }),
});

const prompts = sessionShell({ name: "Session · Prompts", active: "Prompts", children:
  F("H", { flex: "row", items: "center", justify: "between", w: "fill" }, T("9 prompts", { size: 11, weight: "semibold", color: D.text }) + chip("Newest first", D.sec)) +
  [
    ["Show actual changes and diffs in session and project views", "1h 28m ago", 3],
    ["Make the changes tab survive an OpenCode restart", "1h 12m ago", 2],
    ["Group repeated edits to the same file", "52m ago", 1],
    ["Add a file-tree layout toggle", "38m ago", 1],
    ["Keep the diff readable at panel width", "21m ago", 1],
  ].map(([p, t, n]) =>
    F("Prompt", { flex: "col", gap: 6, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      T(p, { size: 11, weight: "semibold", color: D.text, w: "fill" }) +
      F("Meta", { flex: "row", items: "center", gap: 6, w: "fill" }, T(t, { size: 9, color: D.ter }), chip(`${n} turns`, D.sec), F("S", { grow: 1 }), iconButton("lucide:copy", D.sec, 10), iconButton("lucide:corner-up-left", D.accent, 10)))).join("") +
  T("Copy a prompt to reuse it, or send it again into this conversation.", { size: 9, color: D.ter, w: "fill" }),
});

const git = sessionShell({ name: "Session · Git", active: "Git", children:
  F("Repo", { flex: "row", items: "center", gap: 7, w: "fill" }, I("lucide:git-branch", 12, D.purple) + T("feat/design-mirror", { size: 12, weight: "bold", color: D.text }) + chip("clean", D.accent) + F("S", { grow: 1 }) + T("ai-tools", { size: 9, color: D.sec })) +
  F("Head", { flex: "col", gap: 3, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    T("HEAD · 8e95bb", { size: 9, weight: "bold", color: D.sec }) +
    T("Move quiz tab controls into drawers", { size: 11, weight: "semibold", color: D.text }) +
    T("Oliver · 38m ago · 4 files changed", { size: 9, color: D.ter })) +
  sectionLabel("Commits while this session ran", T("3", { size: 9, color: D.sec })) +
  [
    ["8e95bb", "Move quiz tab controls into drawers", "+41 −18", "38m ago"],
    ["1c02fa", "Keep diff cards grouped by file", "+22 −9", "52m ago"],
    ["7a4d10", "Extract patch summary view", "+61 −12", "1h 04m ago"],
  ].map(([sha, msg, stat, t]) =>
    F("Commit", { flex: "row", items: "start", gap: 7, p: 9, rounded: 9, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("Node", { w: 8, h: 8, rounded: 4, bg: D.purple, mt: 4 }) +
      F("Body", { flex: "col", gap: 2, grow: 1 }, T(msg, { size: 10, weight: "semibold", color: D.text }), T(`${sha} · ${stat} · ${t}`, { size: 9, color: D.ter })) +
      I("lucide:chevron-right", 10, D.ter))).join("") +
  T("Sessions outside a work tree say so instead of showing an empty list.", { size: 9, color: D.ter, w: "fill" }),
});

const subagents = sessionShell({ name: "Session · Subagents", active: "Subagents", children:
  F("Summary", { flex: "row", items: "center", gap: 6, w: "fill" }, T("2 child sessions", { size: 11, weight: "semibold", color: D.text }) + F("S", { grow: 1 }) + chip("running first", D.running)) +
  [
    ["Review diff rendering", "Running · edit Views/ChangeViews.swift", "4m 12s", "$0.04", D.running, "lucide:loader"],
    ["Check panel layout at 800pt", "Finished · 12 tool calls", "9m 40s", "$0.09", D.sec, "lucide:check"],
  ].map(([t, a, e, c, col, icon]) =>
    F("Child", { flex: "row", items: "start", gap: 8, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("Icon", { w: 22, h: 22, rounded: 7, bg: col + "1F", items: "center", justify: "center" }, I(icon, 11, col)) +
      F("Body", { flex: "col", gap: 3, grow: 1 }, T(t, { size: 11, weight: "semibold", color: D.text }), T(a, { size: 9, color: D.sec }), F("Meta", { flex: "row", gap: 8 }, T(e, { size: 9, color: D.ter }), T(c, { size: 9, color: D.accent }))) +
      I("lucide:chevron-right", 11, D.ter))).join("") +
  emptyState("lucide:git-fork", "No deeper children", "Each level loads its own children when you drill in. Back returns to the parent.", { h: 180 }),
});

const failed = sessionShell({ name: "Session · Failed turn", active: "Conversation", finished: false, children:
  message("Assistant", D.running, "lucide:sparkles", "2m ago", "I’ll retry the stats request with a longer timeout and check the cache path.") +
  F("Failure", { flex: "col", gap: 6, p: 11, rounded: 12, bg: D.danger + "0E", stroke: D.danger + "33", strokeWidth: 1, w: "fill" },
    F("H", { flex: "row", items: "center", gap: 6 }, I("lucide:triangle-alert", 12, D.danger) + T("Provider request failed", { size: 11, weight: "bold", color: D.danger }) + F("S", { grow: 1 }) + T("HTTP 429", { size: 9, color: D.danger })) +
    T("Rate limit reached for requests. Please try again in 18s.", { size: 9.5, color: "#E8B4B6", lineHeight: 14, w: "fill" }) +
    F("Actions", { flex: "row", gap: 6, w: "fill" },
      F("Retry", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 6, rounded: 8, bg: D.accent }, I("lucide:refresh-cw", 10, "#062017") + T("Retry here", { size: 10, weight: "bold", color: "#062017" })) +
      F("Options", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 6, rounded: 8, bg: "#FFFFFF0A" }, I("lucide:sliders-horizontal", 10, D.sec) + T("Retry options…", { size: 10, color: D.sec })))) +
  message("User", D.running, "lucide:user", "3m ago", "Why is the Stats tab returning 404 after the hub restart?") +
  F("Queued", { flex: "col", gap: 5, p: 9, rounded: 9, bg: D.warn + "10", stroke: D.warn + "2E", strokeWidth: 1, w: "fill" },
    F("H", { flex: "row", items: "center", gap: 5 }, I("lucide:clock", 10, D.warn) + T("Queued · waits for the current turn", { size: 9, weight: "bold", color: D.warn }) + F("S", { grow: 1 }) + I("lucide:x", 10, D.warn)) +
    T("Also add the retry count to the failure card.", { size: 9, color: "#D8C4A8" })) +
  F("Composer", { flex: "row", items: "center", gap: 8, p: 9, rounded: 10, bg: D.field, stroke: D.border, strokeWidth: 1, w: "fill" },
    T("Message this session…", { size: 10, color: D.ter, w: "fill" }) + I("lucide:mic", 11, D.sec) + F("Send", { w: 22, h: 22, rounded: 11, bg: D.accent, items: "center", justify: "center" }, I("lucide:arrow-up", 11, "#062017"))),
});

const held = sessionShell({ name: "Session · Paused", active: "Conversation", finished: false, held: "Paused until 21:40", children:
  F("Banner", { flex: "row", items: "center", gap: 8, p: 11, rounded: 10, bg: D.warn + "10", stroke: D.warn + "33", strokeWidth: 1, w: "fill" },
    I("lucide:pause", 13, D.warn) +
    F("Body", { flex: "col", gap: 2, grow: 1 }, T("Paused until 21:40", { size: 11, weight: "bold", color: D.warn }), T("The hub continues automatically. Typing a prompt releases the hold now.", { size: 9, color: "#D8C4A8" })) +
    chip("Continue", D.accent)) +
  message("Assistant", D.running, "lucide:sparkles", "14m ago", "I’ll pause here so you can review the diff before the next turn.", "The turn was interrupted by the user. The conversation stays intact; continuing starts a fresh turn.") +
  toolCall("shell", "git diff --stat") +
  F("Composer", { flex: "row", items: "center", gap: 8, p: 9, rounded: 10, bg: D.field, stroke: D.border, strokeWidth: 1, w: "fill" },
    T("Message this session…", { size: 10, color: D.ter, w: "fill" }) + I("lucide:mic", 11, D.sec) + F("Send", { w: 22, h: 22, rounded: 11, bg: D.accent, items: "center", justify: "center" }, I("lucide:arrow-up", 11, "#062017"))),
});

const loading = sessionShell({ name: "Session · Loading", active: "Conversation", children:
  F("Skeleton", { flex: "col", gap: 8, w: "fill" },
    [1, 2, 3].map(() => F("Skel", { flex: "col", gap: 6, p: 11, rounded: 12, bg: D.card },
      F("A", { w: 90, h: 9, rounded: 4, bg: "#3A3A3A" }) + F("B", { w: "fill", h: 9, rounded: 4, bg: "#333333" }) + F("C", { w: "70%", h: 9, rounded: 4, bg: "#333333" }))).join("")) +
  T("Loading messages…", { size: 10, color: D.ter, textAlign: "center", w: "fill" }),
});

export default function () {
  return pageParts({
    title: "macOS — Live and sessions",
    subtitle: "The conversation is the product. Six tabs share one session shell: conversation, reliability, patches, prompts, git and subagents — plus the failure and hold states that keep work recoverable.",
    meta: "Sources: SessionDetailView.swift · SessionDetailView+Composer/Content/Loading.swift · SessionMessageViews.swift · SessionStatsView.swift · ChangeViews.swift · GitViews.swift · SubagentViews.swift",
    width: 3000,
    sections: [
      group("Conversation and reliability", "The newest message first, with reasoning and tool calls folded into cards.", [
        F("Col", { flex: "col", gap: 10 }, T("Conversation · running", { size: 13, weight: "semibold", color: "#2B3038" }), conversation),
        F("Col", { flex: "col", gap: 10 }, T("Stats · reliability", { size: 13, weight: "semibold", color: "#2B3038" }), stats),
        F("Col", { flex: "col", gap: 10 }, T("Changes · patches", { size: 13, weight: "semibold", color: "#2B3038" }), changes),
      ].join("")),
      group("History, prompts and children", "Every tab is reachable without losing the session header.", [
        F("Col", { flex: "col", gap: 10 }, T("Prompts", { size: 13, weight: "semibold", color: "#2B3038" }), prompts),
        F("Col", { flex: "col", gap: 10 }, T("Git", { size: 13, weight: "semibold", color: "#2B3038" }), git),
        F("Col", { flex: "col", gap: 10 }, T("Subagents", { size: 13, weight: "semibold", color: "#2B3038" }), subagents),
      ].join("")),
      group("Failure, hold and loading", "A failed turn is recoverable; a held turn is explicit; a loading turn keeps the layout.", [
        F("Col", { flex: "col", gap: 10 }, T("Failed turn + queued prompt", { size: 13, weight: "semibold", color: "#2B3038" }), failed),
        F("Col", { flex: "col", gap: 10 }, T("Paused session", { size: 13, weight: "semibold", color: "#2B3038" }), held),
        F("Col", { flex: "col", gap: 10 }, T("Loading history", { size: 13, weight: "semibold", color: "#2B3038" }), loading),
      ].join("")),
    ],
  });
}
