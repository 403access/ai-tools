import { D, L, F, T, I, chip, card, sectionLabel, pageParts, group, bar, notice, emptyState, phone, iosTabs, iconButton } from "./kit.mjs";

const dot = (c = D.running) => F("Dot", { w: 7, h: 7, rounded: 4, bg: c });

const runRow = (title, activity, project, model, elapsed, cost, tokens) =>
  F("Running", { flex: "col", gap: 5, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
    F("H", { flex: "row", items: "center", gap: 7, w: "fill" },
      dot() + T(title, { size: 12, weight: "semibold", color: D.text, w: "fill" }) + T(elapsed, { size: 9, color: D.running }) + I("lucide:chevron-right", 10, D.ter)) +
    F("A", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:terminal", 9, D.warn) + T(activity, { size: 9, color: D.warn, w: "fill" }) + T("4s", { size: 8, color: D.ter })) +
    F("M", { flex: "row", items: "center", gap: 4, w: "fill" }, T(project, { size: 8, weight: "medium", color: D.accent, w: "fill" }) + chip(model, D.sec) + chip("build", D.purple, "lucide:user")) +
    F("F", { flex: "row", items: "center", gap: 7, w: "fill" }, T(cost, { size: 8, color: D.accent }) + T(tokens, { size: 8, color: D.ter })),
  );

const recentRow = (title, project, model, time, cost, tokens) =>
  F("Recent", { flex: "col", gap: 4, p: 10, rounded: 11, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
    F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, T(title, { size: 11, weight: "semibold", color: D.text, w: "fill" }) + T(time, { size: 8, color: D.ter }) + I("lucide:chevron-right", 9, D.ter)) +
    F("M", { flex: "row", items: "center", gap: 4, w: "fill" }, T(project, { size: 8, color: D.accent, w: "fill" }) + chip(model, D.sec) + T(cost, { size: 8, weight: "semibold", color: D.accent }) + T(tokens, { size: 8, color: D.ter })),
  );

const live = phone({ title: "Live", sub: "2 running", active: "Live", name: "iOS · Live", children:
  sectionLabel("Running", T("2", { size: 9, weight: "bold", color: D.running })) +
  runRow("Match iPhone dark theme to macOS tray app", "UDID=7AD86EEA-A3-SUDID · “$APP”", "ai-tools", "deepseek-v4.1-flash", "14m 04s", "$0.05", "205k tok") +
  runRow("Mark messages as read on open and add unread button", "run check 2>&1 | tail -12", "stuttgart-uni-assist…", "deepseek-v4.1-flash", "3h 39m", "$0.41", "1.2M tok") +
  sectionLabel("Recent", T("All 90", { size: 9, color: D.accent })) +
  recentRow("Mobile app with shared server and SQLite database", "ai-tools", "deepseek-v4.1-flash", "13m ago", "$0.29", "1.2M tok") +
  recentRow("Add dedicated profile page with sharing and privacy", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "23m ago", "$0.13", "428k tok") +
  recentRow("Central quiz screen with module tiles and badges", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "3h ago", "$0.29", "983k tok") +
  recentRow("Map mail UI and data sources", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "3h ago", "$0.09", "444k tok"),
});

const liveEmpty = phone({ title: "Live", sub: "", active: "Live", name: "iOS · Live empty", children:
  emptyState("lucide:radio", "Nothing running", "Start a session from Tasks or Projects. Live rows show the current tool, cost and tokens.", { h: 260 }) +
  sectionLabel("Recent", T("0", { size: 9, color: D.ter })) +
  emptyState("lucide:history", "No recent sessions", "Sessions you run in OpenCode appear here after the hub syncs.", { h: 180 }),
});

const liveFilters = phone({ title: "Live", sub: "2 running", active: "Live", name: "iOS · filters", children:
  F("Search", { flex: "row", items: "center", gap: 6, px: 9, py: 6, rounded: 9, bg: D.field, stroke: D.border, strokeWidth: 1, w: "fill" }, I("lucide:search", 10, D.sec) + T("Filter sessions", { size: 9, color: D.ter, w: "fill" })) +
  F("Chips", { flex: "row", gap: 4, wrap: true, w: "fill", h: "hug" }, chip("All projects", D.accent) + chip("Today", D.sec) + chip("Last 7 days", D.sec) + chip("All time", D.sec)) +
  F("Chips2", { flex: "row", gap: 4, wrap: true, w: "fill", h: "hug" }, chip("Any status", D.accent) + chip("Finished", D.sec) + chip("Failed", D.danger) + chip("Interrupted", D.warn)) +
  F("Group", { flex: "row", items: "center", justify: "between", w: "fill", p: 8, rounded: 8, bg: D.card }, T("Group by day", { size: 10, color: D.text }) + F("Switch", { w: 30, h: 17, rounded: 9, bg: D.accent, items: "end", justify: "center", px: 2 }, F("Knob", { w: 13, h: 13, rounded: 7, bg: "#FFFFFF" }))) +
  sectionLabel("Today") +
  recentRow("Refresh session on app reactivation; silently l…", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "3m ago", "$0.23", "880k tok") +
  recentRow("Reusable quiz components for linguistics topi…", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "13h ago", "$0.51", "1.6M tok") +
  sectionLabel("Yesterday") +
  recentRow("Adding global and project-specific graphs to…", "ai-tools", "deepseek-v4.1-flash", "1d ago", "$0.08", "325k tok"),
});

const iosSessionTabs = (active) =>
  F("Tabs", { flex: "row", gap: 2, p: 3, rounded: 9, bg: "#262626", w: "fill", h: "hug" },
    ["Chat", "Stats", "Changes", "Git", "Prompts"].map((l) => F("Tab", { flex: "row", items: "center", justify: "center", grow: 1, py: 5, rounded: 7, bg: l === active ? "#404040" : "#FFFFFF00" }, T(l, { size: 8.5, weight: l === active ? "semibold" : "regular", color: l === active ? D.text : D.sec }))).join(""));

const iosSession = ({ name, active, children, title = "Central quiz screen with module tiles and badges", running = false }) =>
  F(name, { flex: "col", gap: 8, w: 414, h: 896, bg: "#121212", rounded: 34, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
    F("Top", { flex: "row", items: "center", gap: 6, w: "fill", px: 16, py: 10 },
      I("lucide:chevron-left", 12, D.accent) + T("Live", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip(running ? "Running" : "Finished", running ? D.running : D.sec)) +
    F("Card", { flex: "col", gap: 5, mx: 16, p: 10, rounded: 11, bg: D.card, stroke: D.border, strokeWidth: 1 },
      T(title, { size: 12, weight: "bold", color: D.text, w: "fill" }) +
      F("Meta", { flex: "row", gap: 4, w: "fill" }, chip("stuttgart-uni-assistant", D.accent) + chip("deepseek-v4.1-flash", D.sec)) +
      F("M2", { flex: "row", gap: 8, w: "fill" }, T("3h ago", { size: 8, color: D.ter }), T("983k tok", { size: 8, color: D.ter }), T("$0.29", { size: 8, color: D.accent }))) +
    F("Tabs wrap", { flex: "row", w: "fill", h: "hug", px: 16 }, iosSessionTabs(active)) +
    F("Body", { flex: "col", gap: 8, px: 16, grow: 1, w: "fill", overflow: "hidden" }, children) +
    F("Composer", { flex: "row", items: "center", gap: 6, mx: 16, mb: 8, p: 8, rounded: 10, bg: D.field, stroke: D.border, strokeWidth: 1 },
      T("Message this session…", { size: 9, color: D.ter, w: "fill" }) + I("lucide:mic", 10, D.sec) + F("Send", { w: 20, h: 20, rounded: 10, bg: D.accent, items: "center", justify: "center" }, I("lucide:arrow-up", 10, "#062017"))),
  );

const msg = (who, tint, icon, time, body, reasoning = "") =>
  F("Msg", { flex: "col", gap: 4, p: 9, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
    F("H", { flex: "row", items: "center", gap: 4, w: "fill" }, I(icon, 9, tint) + T(who, { size: 9, weight: "bold", color: tint }) + F("S", { grow: 1 }) + T(time, { size: 8, color: D.ter })) +
    (reasoning ? F("R", { flex: "col", gap: 2, p: 6, rounded: 7, bg: D.reasoning + "10", w: "fill" }, T("Reasoning", { size: 8, weight: "bold", color: D.reasoning }), T(reasoning, { size: 8, color: "#C9B6D8", lineHeight: 11, w: "fill" })) : "") +
    T(body, { size: 9, color: "#D0D0D0", lineHeight: 13, w: "fill" }),
  );

const sessionChat = iosSession({ name: "iOS · session chat", active: "Chat", children:
  msg("Assistant", D.running, "lucide:sparkles", "3h ago", "Staged cleanly. Typecheck was passing. Commit message: “Move quiz tab controls into drawers”. Include sort removal. Good…", "The plan is to keep the drawer state local and let the tab bar own selection. The sort control moves into the filter drawer.") +
  F("Tool", { flex: "row", items: "center", gap: 5, p: 8, rounded: 8, bg: D.output + "0C", stroke: D.output + "2A", strokeWidth: 1, w: "fill" }, I("lucide:terminal", 9, D.output) + T("shell", { size: 8, weight: "bold", color: D.output }) + T("git add 'app/(tabs)/mail.tsx' 'app…", { size: 8, color: D.sec, w: "fill" }) + I("lucide:check", 9, D.accent)) +
  msg("Assistant", D.running, "lucide:sparkles", "3h ago", "Committed as `8e95bb` — “Move quiz tab controls into drawers”.\n\nIncludes:\n• Quiz menu + filter drawers, sticky search toolbar\n• Shared drawer/toolbar components promoted to `src/components`\n• Sort removed from the quiz tab") +
  msg("Assistant", D.running, "lucide:sparkles", "3h ago", "Working…"),
});

const sessionStats = iosSession({ name: "iOS · session stats", active: "Stats", children:
  F("Tiles", { flex: "row", gap: 8, w: "fill" },
    F("T", { flex: "col", gap: 2, p: 9, rounded: 9, bg: D.card, grow: 1 }, T("STEPS", { size: 8, weight: "bold", color: D.sec }), T("159", { size: 20, weight: "bold", color: D.text }), T("9 prompts", { size: 8, color: D.ter })) +
    F("T", { flex: "col", gap: 2, p: 9, rounded: 9, bg: D.card, grow: 1 }, T("TOOL CALLS", { size: 8, weight: "bold", color: D.sec }), T("175", { size: 20, weight: "bold", color: D.text }), T("0 failed", { size: 8, color: D.ter }))) +
  F("Tiles2", { flex: "row", gap: 8, w: "fill" },
    F("T", { flex: "col", gap: 2, p: 9, rounded: 9, bg: D.card, grow: 1 }, T("FILES", { size: 8, weight: "bold", color: D.sec }), T("13", { size: 20, weight: "bold", color: D.text }), T("+223 −90", { size: 8, color: D.ter })) +
    F("T", { flex: "col", gap: 2, p: 9, rounded: 9, bg: D.card, grow: 1 }, T("DURATION", { size: 8, weight: "bold", color: D.sec }), T("1h 28m", { size: 20, weight: "bold", color: D.text }), T("0 subagents", { size: 8, color: D.ter }))) +
  sectionLabel("Reliability", T("99%", { size: 9, color: D.accent })) +
  card(
    F("H", { flex: "row", justify: "between", w: "fill" }, T("CALLS", { size: 8, weight: "bold", color: D.sec }), T("OK", { size: 8, weight: "bold", color: D.sec }), T("FAIL", { size: 8, weight: "bold", color: D.sec }), T("OPEN", { size: 8, weight: "bold", color: D.sec })) +
    F("V", { flex: "row", justify: "between", w: "fill" }, T("175", { size: 16, weight: "bold", color: D.text }), T("174", { size: 16, weight: "bold", color: D.accent }), T("0", { size: 16, weight: "bold", color: D.text }), T("1", { size: 16, weight: "bold", color: D.warn })) +
    bar(99, D.accent, 5), { p: 10, gap: 6 }) +
  sectionLabel("Tools") +
  [["shell", 99, "111ms · 99×"], ["edit", 60, "9ms · 48×"], ["read", 34, "4ms · 26×"]].map(([n, p, m]) =>
    F("Tool", { flex: "col", gap: 3, p: 8, rounded: 8, bg: D.card, w: "fill" }, F("H", { flex: "row", justify: "between", w: "fill" }, T(n, { size: 9, weight: "semibold", color: D.text }), T(m, { size: 8, color: D.sec })) + bar(p, D.accent, 4))).join(""),
});

const sessionChanges = iosSession({ name: "iOS · session changes", active: "Changes", children:
  F("Summary", { flex: "row", items: "center", gap: 5, w: "fill" }, T("13 files changed", { size: 10, weight: "semibold", color: D.text }) + T("+223", { size: 9, color: D.accent }) + T("−90", { size: 9, color: D.danger }) + F("S", { grow: 1 }) + I("lucide:layout-list", 10, D.sec)) +
  [["app/(tabs)/quiz.tsx", "+82 −14", [["+", "const [drawer, setDrawer] = useState(null)"], ["-", "const [sort, setSort] = useState('recent')"]]],
   ["src/components/quiz-drawer.tsx", "+64 −8", [["+", "export function QuizDrawer({ open, onClose }) {"], ["+", "  return <Drawer.Root open={open}>"]]],
   ["server/mail.mjs", "+22 −41", [["-", "const smtp = createTransport(...)"], ["+", "const mail = await loadMailConfig()"]]]].map(([f, stat, lines]) =>
    F("Patch", { flex: "col", gap: 4, p: 8, rounded: 9, bg: D.card, w: "fill" },
      F("H", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:file-code", 9, D.sec) + T(f, { size: 9, weight: "semibold", color: D.text, w: "fill" }) + T(stat, { size: 8, color: D.accent })) +
      F("Diff", { flex: "col", gap: 1, p: 6, rounded: 6, bg: "#101010", w: "fill" }, lines.map(([k, s]) => T(s, { size: 8, color: k === "+" ? D.output : D.danger, w: "fill" })).join("")))).join(""),
});

const sessionGit = iosSession({ name: "iOS · session git", active: "Git", children:
  F("Repo", { flex: "row", items: "center", gap: 6, w: "fill" }, I("lucide:git-branch", 10, D.purple) + T("feat/design-mirror", { size: 10, weight: "bold", color: D.text }) + chip("clean", D.accent)) +
  F("Head", { flex: "col", gap: 2, p: 9, rounded: 9, bg: D.card, w: "fill" }, T("HEAD · 8e95bb", { size: 8, color: D.sec }), T("Move quiz tab controls into drawers", { size: 9.5, weight: "semibold", color: D.text }), T("38m ago · 4 files changed", { size: 8, color: D.ter })) +
  sectionLabel("Commits") +
  [["8e95bb", "Move quiz tab controls into drawers", "38m ago"], ["1c02fa", "Keep diff cards grouped by file", "52m ago"], ["7a4d10", "Extract patch summary view", "1h ago"]].map(([sha, msg, t]) =>
    F("C", { flex: "row", items: "center", gap: 6, p: 8, rounded: 8, bg: D.card, w: "fill" }, F("Dot", { w: 6, h: 6, rounded: 3, bg: D.purple }) + F("B", { flex: "col", gap: 1, grow: 1 }, T(msg, { size: 9, color: D.text }), T(`${sha} · ${t}`, { size: 8, color: D.ter })) + I("lucide:chevron-right", 9, D.ter))).join(""),
});

const projects = phone({ title: "Projects", sub: "2 running", active: "Projects", name: "iOS · Projects", children:
  F("Search", { flex: "row", items: "center", gap: 6, px: 9, py: 6, rounded: 9, bg: D.field, stroke: D.border, strokeWidth: 1, w: "fill" }, I("lucide:search", 10, D.sec) + T("Search projects", { size: 9, color: D.ter, w: "fill" })) +
  sectionLabel("Projects", T("13", { size: 9, color: D.ter })) +
  [["AT", "#2F7CF6", "ai-tools", "~/Developer/ai-tools", "1", "just now"], ["SU", "#1F6FEB", "stuttgart-uni-assistant", "~/Developer/stuttgart-uni-assistant", "2", "1m ago"], ["CA", "#8B5CF6", "cisco-anyconnect", "~/Developer/cisco-anyconnect", "", "31m ago"], ["ET", "#7C3AED", "expo-tools", "~/Developer/expo-tools", "", "yesterday"], ["WD", "#2563EB", "wow-diary", "~/Desktop/wow-diary", "", "Aug 27"], ["FI", "#10B981", "file_indexer", "~/Desktop/…/file_indexer", "", "Aug 25"], ["EN", "#0F172A", "eu-news", "~/Desktop/eu-news", "", "Aug 11"]].map(([i, c, n, p, run, t]) =>
    F("Project", { flex: "row", items: "center", gap: 8, p: 8, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("I", { w: 32, h: 32, rounded: 8, bg: c, items: "center", justify: "center" }, T(i, { size: 10, weight: "bold", color: "#FFFFFF" })) +
      F("B", { flex: "col", gap: 2, grow: 1 }, F("N", { flex: "row", gap: 4 }, T(n, { size: 10, weight: "bold", color: D.text }), run ? chip(run, D.running) : ""), T(p, { size: 8, color: D.sec })) +
      T(t, { size: 8, color: D.ter }) + I("lucide:chevron-right", 9, D.ter))).join(""),
});

const projectDetail = F("iOS · project detail", { flex: "col", gap: 8, w: 414, h: 896, bg: "#121212", rounded: 34, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
  F("Top", { flex: "row", items: "center", gap: 6, w: "fill", px: 16, py: 10 }, I("lucide:chevron-left", 12, D.accent) + T("Projects", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("2 running", D.running)) +
  F("Head", { flex: "row", gap: 8, p: 10, mx: 16, rounded: 11, bg: D.card, stroke: D.border, strokeWidth: 1 },
    F("I", { w: 38, h: 38, rounded: 9, bg: "#1F6FEB", items: "center", justify: "center" }, T("SU", { size: 11, weight: "bold", color: "#FFFFFF" })) +
    F("B", { flex: "col", gap: 2, grow: 1 }, T("stuttgart-uni-assistant", { size: 12, weight: "bold", color: D.text }), T("~/Developer/stuttgart-uni-assistant", { size: 8, color: D.sec }), F("M", { flex: "row", gap: 4 }, chip("git", D.purple) + chip("176 changed", D.accent)))) +
  F("Tabs", { flex: "row", gap: 2, p: 3, mx: 16, rounded: 9, bg: "#262626" }, ["Overview", "Stats", "Changes", "Files", "Git", "Sessions"].map((l) => F("Tab", { flex: "row", items: "center", justify: "center", grow: 1, py: 5, rounded: 7, bg: l === "Overview" ? "#404040" : "#FFFFFF00" }, T(l, { size: 8, weight: l === "Overview" ? "semibold" : "regular", color: l === "Overview" ? D.text : D.sec }))).join("")) +
  F("Body", { flex: "col", gap: 8, px: 16, grow: 1, w: "fill" },
    sectionLabel("Running") +
    F("Run", { flex: "row", items: "center", gap: 5, p: 8, rounded: 8, bg: D.card }, dot() + T("List tutor and participants when opening ILIAS items", { size: 9, color: D.text, w: "fill" }) + T("1h 21m", { size: 8, color: D.running })) +
    F("Run", { flex: "row", items: "center", gap: 5, p: 8, rounded: 8, bg: D.card }, dot() + T("Add map-based language family quiz", { size: 9, color: D.text, w: "fill" }) + T("48m 49s", { size: 8, color: D.running })) +
    sectionLabel("At a glance") +
    F("Stats", { flex: "row", gap: 6, w: "fill" },
      F("S", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("STEPS", { size: 7, weight: "bold", color: D.sec }), T("12.582", { size: 14, weight: "bold", color: D.text })) +
      F("S", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("COST", { size: 7, weight: "bold", color: D.sec }), T("$14.11", { size: 14, weight: "bold", color: D.accent })) +
      F("S", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("TOOLS", { size: 7, weight: "bold", color: D.sec }), T("15.203", { size: 14, weight: "bold", color: D.text }))) +
    F("Stats2", { flex: "row", gap: 6, w: "fill" },
      F("S", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("FAILURES", { size: 7, weight: "bold", color: D.sec }), T("160", { size: 14, weight: "bold", color: D.danger })) +
      F("S", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("TOKENS", { size: 7, weight: "bold", color: D.sec }), T("51.2M", { size: 14, weight: "bold", color: D.text })) +
      F("S", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("STREAK", { size: 7, weight: "bold", color: D.sec }), T("11", { size: 14, weight: "bold", color: D.warn }))) +
    sectionLabel("Recent sessions", T("All 90", { size: 8, color: D.accent })) +
    recentRow("List tutor and participants when opening ILIAS items", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "1h ago", "$0.12", "512k tok")),
);

const tasks = phone({ title: "Tasks", sub: "2 running", active: "Tasks", name: "iOS · Tasks", children:
  F("Filters", { flex: "row", gap: 4, w: "fill" }, chip("Queued 2", D.purple) + chip("Review 3", D.warn) + chip("Working 2", D.running) + chip("All 7", D.sec)) +
  F("Meta", { flex: "row", items: "center", justify: "between", w: "fill" }, T("Auto-labelled from the request", { size: 8, color: D.ter }) + F("Controls", { flex: "row", items: "center", gap: 4 }, F("Show done", { flex: "row", items: "center", gap: 2, px: 5, py: 3, rounded: 99, bg: D.sec + "18" }, I("lucide:eye", 7, D.sec) + T("Show done", { size: 7, weight: "semibold", color: D.sec })) + F("New", { flex: "row", items: "center", gap: 3, px: 7, py: 3, rounded: 99, bg: D.accent + "22" }, I("lucide:plus", 8, D.accent) + T("New task", { size: 8, weight: "bold", color: D.accent })))) +
  sectionLabel("Queued", T("2", { size: 9, weight: "bold", color: D.purple })) +
  [["Draft release notes for the hub queue", "ai-tools", "Starts in 15m"], ["Pin the remote desktop overlay to the active display", "ai-tools", "Waiting for a slot"]].map(([t, p, time]) =>
    F("Task", { flex: "row", gap: 7, p: 9, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("S", { w: 16, h: 16, rounded: 8, bg: D.purple + "22", items: "center", justify: "center" }, I("lucide:hourglass", 9, D.purple)) +
      F("B", { flex: "col", gap: 3, grow: 1 }, T(t, { size: 10, weight: "semibold", color: D.text, w: "fill" }), T(`${p} · ${time}`, { size: 8, color: D.sec })) +
      F("A", { w: 18, h: 18, rounded: 6, bg: D.purple + "18", items: "center", justify: "center" }, I("lucide:play", 9, D.purple)))).join("") +
  sectionLabel("Needs review", T("3", { size: 9, weight: "bold", color: D.warn })) +
  [["Add map-based language family quiz", "stuttgart-uni-assistant", "48m ago", [["Feature", D.accent], ["Product", D.running]]],
   ["Show actual changes and diffs in session and project views", "ai-tools", "1h ago", [["Feature", D.accent], ["Technical", D.running]]],
   ["Harden VM serial console reconnect path", "ai-tools", "2h ago", [["Bug", D.danger], ["Security-sensitive", D.warn]]]].map(([t, p, time, labels]) =>
    F("Task", { flex: "row", gap: 7, p: 9, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("S", { w: 16, h: 16, rounded: 8, bg: D.warn + "22", items: "center", justify: "center" }, I("lucide:eye", 9, D.warn)) +
      F("B", { flex: "col", gap: 3, grow: 1 }, T(t, { size: 10, weight: "semibold", color: D.text, w: "fill" }), T(`${p} · ${time}`, { size: 8, color: D.sec }), F("L", { flex: "row", gap: 3, w: "fill" }, labels.map(([l, c]) => chip(l, c)).join(""))) +
      F("A", { w: 18, h: 18, rounded: 6, bg: D.warn + "18", items: "center", justify: "center" }, I("lucide:check", 9, D.warn)))).join("") +
  sectionLabel("In progress", T("2", { size: 9, weight: "bold", color: D.running })) +
  F("Task", { flex: "row", gap: 7, p: 9, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("S", { w: 16, h: 16, rounded: 8, bg: D.running + "22", items: "center", justify: "center" }, I("lucide:loader", 9, D.running)) +
    F("B", { flex: "col", gap: 3, grow: 1 }, T("Match iPhone dark theme to macOS tray app", { size: 10, weight: "semibold", color: D.text }), T("ai-tools · 14m", { size: 8, color: D.sec }), F("L", { flex: "row", gap: 3 }, chip("Feature", D.accent) + chip("Product", D.running))),
    F("A", { w: 18, h: 18, rounded: 6, bg: D.running + "18", items: "center", justify: "center" }, I("lucide:arrow-up-right", 9, D.running))),
});

const tasksEmpty = phone({ title: "Tasks", sub: "", active: "Tasks", name: "iOS · Tasks empty", children:
  F("Filters", { flex: "row", gap: 4, w: "fill" }, chip("Queued 0", D.purple) + chip("Review 0", D.warn) + chip("Working 0", D.running) + chip("All 0", D.sec)) +
  emptyState("lucide:list-checks", "No tasks yet", "New sessions become tasks. Finished work lands here for review.", { h: 300 }) +
  F("Hint", { flex: "row", gap: 7, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" }, I("lucide:wand-sparkles", 12, D.purple) + T("Labels are inferred from the request — no model call.", { size: 8, color: D.sec, w: "fill" })),
});

const usage = phone({ title: "Usage", sub: "1 running", active: "Usage", name: "iOS · Usage", children:
  sectionLabel("Plan limits") +
  F("Plan", { flex: "col", gap: 6, p: 9, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    [["Rolling", 14, "resets in 1m"], ["Weekly", 27, "resets in 4d 5h"], ["Monthly", 18, "resets in 26d 18h"]].map(([l, p, r]) =>
      F("P", { flex: "col", gap: 3, w: "fill" }, F("H", { flex: "row", justify: "between", w: "fill" }, T(l, { size: 9, weight: "semibold", color: D.text }), T(`${p}% used · ${r}`, { size: 8, color: D.sec })) + bar(p, D.accent, 4))).join("")) +
  F("Pages", { flex: "row", gap: 2, p: 3, rounded: 9, bg: "#262626", w: "fill" }, ["Overview", "Activity", "Breakdown", "Tools"].map((l) => F("Page", { flex: "row", items: "center", justify: "center", grow: 1, py: 5, rounded: 7, bg: l === "Overview" ? "#404040" : "#FFFFFF00" }, T(l, { size: 8.5, weight: l === "Overview" ? "semibold" : "regular", color: l === "Overview" ? D.text : D.sec }))).join("")) +
  F("Trend", { flex: "col", gap: 5, p: 9, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("H", { flex: "row", items: "center", gap: 4, w: "fill" }, chip("Steps", D.accent) + chip("Cost", D.sec) + chip("Tokens", D.sec) + F("S", { grow: 1 }) + chip("30D", D.sec)) +
    F("Bars", { flex: "row", items: "end", gap: 3, w: "fill", h: 90 }, [18, 30, 22, 40, 35, 48, 28, 55, 42, 66, 34, 58, 62, 38, 72, 50, 78, 60, 86, 64, 80, 92, 68, 84].map((h) => F("B", { w: 8, h, rounded: 2, bg: D.running })).join(""))) +
  F("Stats", { flex: "row", gap: 6, w: "fill" },
    F("S", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("STREAK", { size: 7, weight: "bold", color: D.sec }), T("39", { size: 16, weight: "bold", color: D.warn })) +
    F("S", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("TODAY", { size: 7, weight: "bold", color: D.sec }), T("1.616", { size: 16, weight: "bold", color: D.text }))) +
  F("Stats2", { flex: "row", gap: 6, w: "fill" },
    F("S", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("PROMPTS", { size: 7, weight: "bold", color: D.sec }), T("2.907", { size: 16, weight: "bold", color: D.text })) +
    F("S", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("COST", { size: 7, weight: "bold", color: D.sec }), T("$28.54", { size: 16, weight: "bold", color: D.accent }))),
});

const settings = phone({ title: "Settings", sub: "", active: "Settings", name: "iOS · Settings", children:
  sectionLabel("Hub") +
  F("Hub", { flex: "col", gap: 4, p: 9, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("H", { flex: "row", items: "center", gap: 5 }, dot(D.accent) + T("Connected", { size: 10, weight: "bold", color: D.accent }) + F("S", { grow: 1 }) + T("v0.16.0", { size: 8, color: D.sec })) +
    T("http://192.168.1.42:8787", { size: 8, color: D.sec }) +
    T("OpenCode connected · last sync just now", { size: 8, color: D.ter })) +
  F("QR", { flex: "row", gap: 8, p: 9, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("Code", { w: 70, h: 70, rounded: 6, bg: "#FFFFFF", p: 5 },
      F("Q", { flex: "col", gap: 2, w: "fill", h: "fill" }, Array.from({ length: 7 }, (_, r) => F("R", { flex: "row", gap: 2, w: "fill" }, Array.from({ length: 7 }, (_, c) => F("C", { w: 6, h: 6, bg: (r * 7 + c * 3) % 4 < 2 ? "#111111" : "#FFFFFF" })).join(""))).join(""))) +
    F("B", { flex: "col", gap: 3, grow: 1 }, T("Pair another device", { size: 9, weight: "bold", color: D.text }), T("Scan this code from the Mac app, or paste the pairing link.", { size: 8, color: D.sec, lineHeight: 11 }), chip("Copy link", D.accent))) +
  sectionLabel("Appearance") +
  F("Appearance", { flex: "row", gap: 4, w: "fill" }, chip("System", D.accent) + chip("Dark", D.sec) + chip("Light", D.sec)) +
  sectionLabel("Host") +
  F("Row", { flex: "row", items: "center", justify: "between", p: 9, rounded: 9, bg: D.card, w: "fill" }, T("Keep Mac awake", { size: 9, color: D.text }) + F("Switch", { w: 30, h: 17, rounded: 9, bg: D.accent, items: "end", justify: "center", px: 2 }, F("Knob", { w: 13, h: 13, rounded: 7, bg: "#FFFFFF" }))) +
  sectionLabel("Developer") +
  F("Row", { flex: "row", items: "center", gap: 6, p: 9, rounded: 9, bg: D.card, w: "fill" }, I("lucide:bug", 11, D.purple) + T("Activity log", { size: 9, color: D.text, w: "fill" }) + T("API requests, syncs, events, errors", { size: 7, color: D.ter }) + I("lucide:chevron-right", 9, D.ter)) +
  F("Version", { flex: "row", justify: "between", w: "fill" }, T("OpenCodeBar 1.0 (42)", { size: 8, color: D.ter }), T("Forget hub", { size: 8, color: D.danger })),
});

const pairing = F("iOS · pairing", { flex: "col", gap: 12, w: 414, h: 896, bg: "#121212", rounded: 34, stroke: D.border, strokeWidth: 1, p: 22, items: "center", justify: "center" },
  F("Logo", { w: 54, h: 54, rounded: 16, bg: D.accent, items: "center", justify: "center" }, I("lucide:code-xml", 28, "#0B1F17")) +
  T("Pair with your hub", { size: 20, weight: "bold", color: D.text, textAlign: "center" }) +
  T("Scan the QR code in the Mac app's Settings tab, or paste the hub URL and token.", { size: 9, color: D.sec, textAlign: "center", lineHeight: 13, w: 330 }) +
  F("Scan", { flex: "row", items: "center", justify: "center", gap: 5, py: 9, rounded: 10, bg: D.accent, w: "fill" }, I("lucide:qr-code", 11, "#062017") + T("Scan QR code", { size: 11, weight: "bold", color: "#062017" })) +
  F("Divider", { flex: "row", items: "center", gap: 6, w: "fill" }, F("L", { w: "fill", h: 1, bg: "#FFFFFF14" }) + T("or", { size: 8, color: D.ter }) + F("R", { w: "fill", h: 1, bg: "#FFFFFF14" })) +
  F("Paste", { flex: "col", gap: 4, w: "fill" }, T("PASTE A PAIRING LINK", { size: 8, weight: "bold", color: D.sec }), F("I", { flex: "row", items: "center", gap: 5, p: 8, rounded: 8, bg: D.field, stroke: D.border, strokeWidth: 1 }, T("opencodebar://pair?url=…", { size: 8, color: D.ter, w: "fill" }), chip("Paste", D.accent))) +
  T("The token is stored only on this device.", { size: 8, color: D.ter }),
);

const lightLive = phone({ title: "Live", sub: "2 running", active: "Live", dark: false, name: "iOS · light", children:
  sectionLabel("Running", T("2", { size: 9, weight: "bold", color: L.running })) +
  F("Run", { flex: "col", gap: 5, p: 10, rounded: 12, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: "fill" },
    F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, dot(L.running) + T("Match iPhone dark theme to macOS tray app", { size: 12, weight: "semibold", color: L.text, w: "fill" }) + T("14m 04s", { size: 9, color: L.running })) +
    F("A", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:terminal", 9, L.warn) + T("Running · npm run build --watch", { size: 9, color: L.warn, w: "fill" })) +
    F("M", { flex: "row", gap: 4, w: "fill" }, chip("ai-tools", L.accent) + chip("deepseek-v4.1-flash", L.sec) + chip("build", L.accent))) +
  sectionLabel("Recent", T("All 90", { size: 9, color: L.accent })) +
  F("Recent", { flex: "col", gap: 4, p: 10, rounded: 11, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: "fill" },
    T("Mobile app with shared server and SQLite database", { size: 11, weight: "semibold", color: L.text }) +
    F("M", { flex: "row", gap: 4, w: "fill" }, T("ai-tools", { size: 8, color: L.accent, w: "fill" }) + chip("deepseek-v4.1-flash", L.sec) + T("$0.29", { size: 8, color: L.accent }))) +
  F("Recent", { flex: "col", gap: 4, p: 10, rounded: 11, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w: "fill" },
    T("Add dedicated profile page with sharing and privacy", { size: 11, weight: "semibold", color: L.text }) +
    F("M", { flex: "row", gap: 4, w: "fill" }, T("stuttgart-uni-assistant", { size: 8, color: L.accent, w: "fill" }) + chip("deepseek-v4.1-flash", L.sec) + T("$0.13", { size: 8, color: L.accent }))),
});

export default function () {
  return pageParts({
    title: "iOS — core tabs",
    subtitle: "The same product adapted for touch: Tasks, Live, Projects, Usage and Settings share the compact panel language, a floating dock and a local SQLite cache that renders the last snapshot on launch.",
    meta: "Sources: OpenCodeBarMobileApp.swift · LiveView.swift · SessionDetailView*.swift · ProjectsView.swift · ProjectDetailView.swift · TasksView.swift · UsageView.swift · SettingsView.swift · NewSessionSheet.swift",
    width: 2400,
    sections: [
      group("Live", "Running and recent sessions, filters, and the empty state.", [
        F("Col", { flex: "col", gap: 10 }, T("Live · populated", { size: 13, weight: "semibold", color: "#2B3038" }), live),
        F("Col", { flex: "col", gap: 10 }, T("Live · empty", { size: 13, weight: "semibold", color: "#2B3038" }), liveEmpty),
        F("Col", { flex: "col", gap: 10 }, T("Live · filters", { size: 13, weight: "semibold", color: "#2B3038" }), liveFilters),
        F("Col", { flex: "col", gap: 10 }, T("Live · light", { size: 13, weight: "semibold", color: "#2B3038" }), lightLive),
      ].join("")),
      group("Sessions", "Chat, stats, changes and git on a phone.", [
        F("Col", { flex: "col", gap: 10 }, T("Session · chat", { size: 13, weight: "semibold", color: "#2B3038" }), sessionChat),
        F("Col", { flex: "col", gap: 10 }, T("Session · stats", { size: 13, weight: "semibold", color: "#2B3038" }), sessionStats),
        F("Col", { flex: "col", gap: 10 }, T("Session · changes", { size: 13, weight: "semibold", color: "#2B3038" }), sessionChanges),
        F("Col", { flex: "col", gap: 10 }, T("Session · git", { size: 13, weight: "semibold", color: "#2B3038" }), sessionGit),
      ].join("")),
      group("Projects and Tasks", "Search, scoped analytics and the review board.", [
        F("Col", { flex: "col", gap: 10 }, T("Projects", { size: 13, weight: "semibold", color: "#2B3038" }), projects),
        F("Col", { flex: "col", gap: 10 }, T("Project detail", { size: 13, weight: "semibold", color: "#2B3038" }), projectDetail),
        F("Col", { flex: "col", gap: 10 }, T("Tasks", { size: 13, weight: "semibold", color: "#2B3038" }), tasks),
        F("Col", { flex: "col", gap: 10 }, T("Tasks · empty", { size: 13, weight: "semibold", color: "#2B3038" }), tasksEmpty),
      ].join("")),
      group("Usage, Settings and pairing", "Plan limits, trends, appearance, host sleep and the first-run pairing flow.", [
        F("Col", { flex: "col", gap: 10 }, T("Usage", { size: 13, weight: "semibold", color: "#2B3038" }), usage),
        F("Col", { flex: "col", gap: 10 }, T("Settings", { size: 13, weight: "semibold", color: "#2B3038" }), settings),
        F("Col", { flex: "col", gap: 10 }, T("Pairing", { size: 13, weight: "semibold", color: "#2B3038" }), pairing),
      ].join("")),
    ],
  });
}
