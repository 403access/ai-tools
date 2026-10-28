import { D, F, T, I, chip, card, sectionLabel, pageParts, group, bar, notice, emptyState, panel, macTabs4, iconButton } from "./kit.mjs";

const dot = (c = D.running) => F("Dot", { w: 7, h: 7, rounded: 4, bg: c });

const projectRow = (initials, color, name, path, running, time, extra = "") =>
  F("Project row", { flex: "row", items: "center", gap: 9, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
    F("Icon", { w: 36, h: 36, rounded: 9, bg: color, items: "center", justify: "center" }, T(initials, { size: 12, weight: "bold", color: "#FFFFFF" })) +
    F("Body", { flex: "col", gap: 3, grow: 1 },
      F("Name", { flex: "row", items: "center", gap: 6 }, T(name, { size: 12, weight: "bold", color: D.text }) + chip("git", D.purple) + (extra ? chip(extra, D.sec) : "")) +
      T(path, { size: 9, color: D.sec })) +
    F("Right", { flex: "col", gap: 3, items: "end" },
      running ? F("Run", { flex: "row", items: "center", gap: 3 }, dot(), T(String(running), { size: 9, weight: "bold", color: D.running })) : "",
      T(time, { size: 9, color: D.ter })) +
    I("lucide:chevron-right", 12, D.ter),
  );

const projects = panel({ tabs: macTabs4, active: "Projects", name: "Panel · Projects", children:
  F("Search", { flex: "row", items: "center", gap: 7, px: 10, py: 7, rounded: 10, bg: D.field, stroke: D.border, strokeWidth: 1, w: "fill" }, I("lucide:search", 12, D.sec) + T("Search projects", { size: 11, color: D.ter, w: "fill" })) +
  sectionLabel("Projects", T("13", { size: 9, color: D.ter })) +
  projectRow("SU", "#1F6FEB", "stuttgart-uni-assistant", "~/Developer/stuttgart-uni-assistant", 2, "just now") +
  projectRow("AT", "#2F7CF6", "ai-tools", "~/Developer/ai-tools", 1, "just now") +
  projectRow("CA", "#8B5CF6", "cisco-anyconnect", "~/Developer/cisco-anyconnect", 0, "26m ago") +
  projectRow("ET", "#7C3AED", "expo-tools", "~/Developer/expo-tools", 0, "yesterday") +
  projectRow("WD", "#2563EB", "wow-diary", "~/Desktop/wow-diary", 0, "Aug 27") +
  projectRow("FI", "#10B981", "file_indexer", "~/Desktop/Desktop…objects/file_indexer", 0, "Aug 25", "1 sandbox") +
  projectRow("EN", "#0F172A", "eu-news", "~/Desktop/eu-news", 0, "Aug 11") +
  projectRow("UZ", "#059669", "unicode-zigs", "~/Developer/unicode-zigs", 0, "Jul 24"),
});

const projectsEmpty = panel({ tabs: macTabs4, active: "Projects", name: "Panel · Projects empty", children:
  F("Search", { flex: "row", items: "center", gap: 7, px: 10, py: 7, rounded: 10, bg: D.field, stroke: D.border, strokeWidth: 1, w: "fill" }, I("lucide:search", 12, D.sec) + T("Search projects", { size: 11, color: D.ter, w: "fill" })) +
  emptyState("lucide:folder", "No projects yet", "OpenCode projects appear here after the first session. Start one from the Live tab or open a folder in OpenCode.") +
  F("Actions", { flex: "row", gap: 6, w: "fill" },
    F("A", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 7, rounded: 9, bg: D.accent }, I("lucide:plus", 10, "#062017") + T("New session", { size: 10, weight: "bold", color: "#062017" })) +
    F("B", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 7, rounded: 9, bg: "#FFFFFF0A" }, I("lucide:git-fork", 10, D.sec) + T("Clone repository", { size: 10, color: D.sec }))),
});

const projectShell = ({ name, active, children, title = "stuttgart-uni-assistant", running = 2, extra = "176 changed" }) =>
  F(name, { flex: "col", gap: 10, w: 800, h: 1200, p: 0, bg: D.panel, rounded: 20, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
    F("Top", { flex: "row", items: "center", gap: 8, w: "fill", px: 20, py: 12 },
      I("lucide:chevron-left", 12, D.accent) + T("Projects", { size: 11, color: D.accent }) + F("S", { grow: 1 }) + F("Run", { flex: "row", items: "center", gap: 4 }, dot(), T(`${running} running`, { size: 10, weight: "semibold", color: D.running }))) +
    F("Head wrap", { flex: "col", gap: 10, px: 20, w: "fill", h: "hug" },
      F("Head", { flex: "row", items: "center", gap: 9, p: 12, rounded: 14, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
        F("Icon", { w: 44, h: 44, rounded: 10, bg: "#1F6FEB", items: "center", justify: "center" }, T("SU", { size: 14, weight: "bold", color: "#FFFFFF" })) +
        F("Body", { flex: "col", gap: 4, grow: 1 },
          T(title, { size: 17, weight: "bold", color: D.text }) +
          T("~/Developer/stuttgart-uni-assistant", { size: 9, color: D.sec }) +
          F("Meta", { flex: "row", gap: 5 }, chip("git", D.purple) + chip(extra, D.accent) + chip("Active 1m ago", D.sec))) +
        iconButton("lucide:plus", D.accent, 12) + iconButton("lucide:folder", D.sec, 12) + iconButton("lucide:terminal", D.sec, 12) + iconButton("lucide:copy", D.sec, 12)) +
      F("Tabs", { flex: "row", gap: 2, p: 3, rounded: 10, bg: "#262626", w: "fill", h: "hug" },
        ["Overview", "Stats", "Changes", "Files", "Git", "Sessions"].map((l) =>
          F("Tab", { flex: "row", items: "center", justify: "center", grow: 1, py: 6, rounded: 8, bg: l === active ? "#404040" : "#FFFFFF00" },
            T(l, { size: 9, weight: l === active ? "semibold" : "regular", color: l === active ? D.text : D.sec }))).join(""))) +
    F("Body", { flex: "col", gap: 10, px: 20, py: 6, grow: 1, w: "fill", overflow: "hidden" }, children) +
    F("Footer", { flex: "row", items: "center", justify: "between", px: 20, py: 9, w: "fill", bg: "#191919", stroke: "#FFFFFF10", strokeWidth: 1 },
      F("Active", { flex: "row", items: "center", gap: 5 }, dot(), T("3 active", { size: 10, color: D.sec })) + T("Updated just now", { size: 10, color: D.ter })),
  );

const runRow = (title, time) =>
  F("Run", { flex: "row", items: "center", gap: 6, p: 9, rounded: 9, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    dot() + T(title, { size: 10, color: D.text, w: "fill" }) + T(time, { size: 9, color: D.running }) + I("lucide:chevron-right", 10, D.ter));

const projectOverview = projectShell({ name: "Project · Overview", active: "Overview", children:
  sectionLabel("Running", T("2", { size: 9, weight: "bold", color: D.running })) +
  runRow("List tutor and participants when opening ILIAS items", "1h 21m") +
  runRow("Add map-based language family quiz", "48m 49s") +
  sectionLabel("At a glance") +
  F("Tiles", { flex: "row", gap: 8, w: "fill" },
    F("T1", { flex: "col", gap: 2, p: 9, rounded: 9, bg: D.card, grow: 1 }, T("STEPS", { size: 8, weight: "bold", color: D.sec }), T("12.582", { size: 17, weight: "bold", color: D.text }), T("642 prompts", { size: 8, color: D.ter })) +
    F("T2", { flex: "col", gap: 2, p: 9, rounded: 9, bg: D.card, grow: 1 }, T("COST", { size: 8, weight: "bold", color: D.sec }), T("$14.11", { size: 17, weight: "bold", color: D.accent }), T("85 sessions", { size: 8, color: D.ter })) +
    F("T3", { flex: "col", gap: 2, p: 9, rounded: 9, bg: D.card, grow: 1 }, T("TOOL CALLS", { size: 8, weight: "bold", color: D.sec }), T("15.203", { size: 17, weight: "bold", color: D.text }), T("15.043 succeeded", { size: 8, color: D.ter }))) +
  F("Tiles2", { flex: "row", gap: 8, w: "fill" },
    F("T1", { flex: "col", gap: 2, p: 9, rounded: 9, bg: D.card, grow: 1 }, T("FAILURES", { size: 8, weight: "bold", color: D.sec }), T("160", { size: 17, weight: "bold", color: D.danger }), T("0 unfinished", { size: 8, color: D.ter })) +
    F("T2", { flex: "col", gap: 2, p: 9, rounded: 9, bg: D.card, grow: 1 }, T("TOKENS", { size: 8, weight: "bold", color: D.sec }), T("51.2M", { size: 17, weight: "bold", color: D.text }), T("2.5B cache read", { size: 8, color: D.ter })) +
    F("T3", { flex: "col", gap: 2, p: 9, rounded: 9, bg: D.card, grow: 1 }, T("STREAK", { size: 8, weight: "bold", color: D.sec }), T("11", { size: 17, weight: "bold", color: D.warn }), T("11 active days", { size: 8, color: D.ter }))) +
  sectionLabel("Recent sessions", T("All 90", { size: 9, color: D.accent })) +
  [["List tutor and participants when opening ILIAS items", "1h 21m"], ["Add map-based language family quiz", "48m 49s"], ["Syntax I: Grundlagenquiz zu Grammatik, Wo…", "$0.05 · 1h ago"], ["Checking access to studies we aren’t enrolled…", "$0.15 · 2h ago"]]
    .map(([t, e]) => F("Recent", { flex: "row", items: "center", gap: 6, p: 8, rounded: 8, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" }, (e.includes("$") ? F("Dot", { w: 6, h: 6, rounded: 3, bg: "#5A5A5A" }) : dot()) + T(t, { size: 9, color: D.text, w: "fill" }) + T(e, { size: 9, color: e.includes("$") ? D.accent : D.running }))).join(""),
});

const projectStats = projectShell({ name: "Project · Stats", active: "Stats", children:
  F("H", { flex: "row", items: "center", justify: "between", w: "fill" }, T("Scoped to this project", { size: 10, color: D.sec }) + chip("30D", D.accent)) +
  F("Chart", { flex: "col", gap: 6, p: 11, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("H", { flex: "row", justify: "between", w: "fill" }, T("STEPS · DAILY", { size: 9, weight: "bold", color: D.sec }), T("12.582 total", { size: 9, color: D.text })) +
    F("Bars", { flex: "row", items: "end", gap: 3, w: "fill", h: 100 },
      [18, 30, 22, 40, 35, 48, 28, 55, 42, 66, 34, 58, 62, 38, 72, 50, 78, 60, 86, 64, 80, 92, 68, 84, 56, 74, 48, 66, 40, 52].map((h) => F("B", { w: 14, h, rounded: 3, bg: D.accent })).join(""))) +
  F("Mix", { flex: "col", gap: 6, p: 11, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    T("MODEL MIX", { size: 9, weight: "bold", color: D.sec }) +
    [["deepseek-v4.1-flash", 78, D.accent], ["kimi-k2.5", 14, D.reasoning], ["claude-sonnet-4.5", 8, D.running]].map(([n, p, c]) =>
      F("M", { flex: "col", gap: 4, w: "fill" }, F("H", { flex: "row", justify: "between", w: "fill" }, T(n, { size: 9, color: D.text }), T(`${p}%`, { size: 9, color: D.sec })) + bar(p, c, 5))).join("")) +
  sectionLabel("Tool reliability") +
  [["shell", 9420, 9401, 12, 7, 111], ["edit", 3180, 3172, 6, 2, 9], ["read", 1702, 1702, 0, 0, 4], ["grep", 901, 898, 3, 0, 12]].map(([n, calls, ok, fail, unf, ms]) =>
    F("Tool", { flex: "row", items: "center", gap: 8, p: 9, rounded: 9, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      T(n, { size: 10, weight: "semibold", color: D.text, w: 90 }) + T(`${calls} calls`, { size: 9, color: D.sec, w: "fill" }) + T(`${ok} ok`, { size: 9, color: D.accent }) + T(`${fail} fail`, { size: 9, color: D.danger }) + T(`${ms}ms`, { size: 9, color: D.ter }))).join(""),
});

const projectChanges = projectShell({ name: "Project · Changes", active: "Changes", children:
  F("Summary", { flex: "row", items: "center", gap: 6, w: "fill" }, T("176 files changed", { size: 11, weight: "semibold", color: D.text }) + T("across 10 sessions", { size: 9, color: D.sec }) + F("S", { grow: 1 }) + chip("Files", D.sec)) +
  [["src/app/(tabs)/quiz.tsx", 82, 14, "Add map-based language family quiz"], ["src/components/quiz-drawer.tsx", 64, 8, "Move quiz tab controls into drawers"], ["server/mail.mjs", 22, 41, "Map mail UI and data sources"], ["app/(tabs)/profile.tsx", 18, 6, "Add dedicated profile page"]].map(([f, a, r, s]) =>
    F("Change", { flex: "col", gap: 4, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, I("lucide:file-code", 10, D.sec) + T(f, { size: 10, weight: "semibold", color: D.text, w: "fill" }) + T(`+${a}`, { size: 9, color: D.accent }) + T(`−${r}`, { size: 9, color: D.danger })) +
      T(s, { size: 9, color: D.ter }))).join("") +
  F("Pages", { flex: "row", items: "center", justify: "center", gap: 5, py: 7, rounded: 8, bg: "#FFFFFF08", w: "fill" }, T("Load 20 more files", { size: 10, color: D.sec })),
});

const projectFiles = projectShell({ name: "Project · Files", active: "Files", children:
  F("Toolbar", { flex: "row", items: "center", gap: 6, w: "fill" },
    F("Search", { flex: "row", items: "center", gap: 6, px: 8, py: 6, rounded: 8, bg: D.field, grow: 1 }, I("lucide:search", 10, D.sec) + T("Filter by path", { size: 9, color: D.ter, w: "fill" })) +
    chip("Changed 176", D.accent) + iconButton("lucide:layout-list", D.sec, 11)) +
  [["src/", "folder"], ["  app/", "folder"], ["    (tabs)/", "folder"], ["      quiz.tsx", "file"], ["      profile.tsx", "file"], ["  components/", "folder"], ["    quiz-drawer.tsx", "file"], ["server/", "folder"], ["  mail.mjs", "file"], ["README.md", "file"], ["package.json", "file"]]
    .map(([f, kind]) => F("File", { flex: "row", items: "center", gap: 6, py: 5, px: 6, rounded: 6, bg: "#FFFFFF00", w: "fill" },
      I(kind === "folder" ? "lucide:folder" : "lucide:file", 10, kind === "folder" ? D.warn : D.sec) +
      T(f, { size: 9.5, color: f.includes("quiz") || f.includes("profile") ? D.text : D.sec, w: "fill" }) +
      (f.includes("quiz") || f.includes("profile") ? chip("M", D.warn) : f.includes("mail") ? chip("A", D.accent) : ""))).join("") +
  T("Includes untracked files; M/A/D marks working-tree changes.", { size: 9, color: D.ter, w: "fill" }),
});

const projectGit = projectShell({ name: "Project · Git", active: "Git", children:
  F("Branch", { flex: "row", items: "center", gap: 7, w: "fill" }, I("lucide:git-branch", 12, D.purple) + T("main", { size: 13, weight: "bold", color: D.text }) + chip("clean", D.accent) + F("S", { grow: 1 }) + T("4 branches · 2 tags", { size: 9, color: D.sec })) +
  F("Head", { flex: "col", gap: 3, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    T("HEAD · 8e95bb · main", { size: 9, weight: "bold", color: D.sec }) + T("Move quiz tab controls into drawers", { size: 11, weight: "semibold", color: D.text }) + T("Oliver · 38m ago", { size: 9, color: D.ter })) +
  sectionLabel("Commit graph") +
  F("Graph", { flex: "col", gap: 4, w: "fill" },
    [["8e95bb", "Move quiz tab controls into drawers", "main", 0], ["1c02fa", "Keep diff cards grouped by file", "main", 0], ["7a4d10", "Extract patch summary view", "main", 0], ["3c9f21", "Merge branch 'quiz-drawer'", "merge", 1], ["2b1e08", "Add drawer primitives", "quiz-drawer", 1], ["9d4c11", "Initial quiz screen", "main", 0]]
      .map(([sha, msg, ref, lane]) => F("Commit", { flex: "row", items: "center", gap: 7, p: 8, rounded: 8, bg: D.card, w: "fill" },
        F("Lanes", { flex: "row", items: "center", gap: 3, w: 34 },
          F("L1", { w: 7, h: 7, rounded: 4, bg: lane === 0 ? D.accent : "#333333" }) +
          (lane === 1 ? F("L2", { w: 7, h: 7, rounded: 4, bg: D.purple }) : F("L2", { w: 7, h: 7, rounded: 4, bg: "#00000000" }))) +
        F("Body", { flex: "col", gap: 1, grow: 1 }, T(msg, { size: 9.5, color: D.text }), T(`${sha} · ${ref}`, { size: 8, color: D.ter })) + I("lucide:chevron-right", 9, D.ter))).join("")),
});

const projectGitEmpty = projectShell({ name: "Project · Git empty", active: "Git", title: "file_indexer", running: 0, extra: "no git", children:
  emptyState("lucide:git-branch", "Not a git repository", "This folder is not a work tree. Git information is unavailable, but files, sessions and analytics still work.", { h: 300 }) +
  F("Hint", { flex: "row", gap: 7, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" }, I("lucide:info", 12, D.sec) + T("Non-repository folders show this instead of an empty commit list.", { size: 9, color: D.sec, w: "fill" })),
});

const usageShell = (name, activePage, children) =>
  panel({ tabs: macTabs4, active: "Usage", name, children:
    F("Plan", { flex: "col", gap: 7, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, I("lucide:circle-gauge", 11, D.accent) + T("PLAN LIMITS", { size: 9, weight: "bold", color: D.sec, letterSpacing: 0.6 }) + F("S", { grow: 1 }) + T("next reset in 2h 40m", { size: 9, color: D.ter }) + I("lucide:chevron-down", 10, D.ter)) +
      F("Rows", { flex: "row", gap: 10, w: "fill" },
        [["Rolling", 4], ["Weekly", 16], ["Monthly", 49]].map(([l, p]) =>
          F("W", { flex: "col", gap: 4, grow: 1 }, F("H", { flex: "row", justify: "between", w: "fill" }, T(l, { size: 9, color: D.sec }), T(`${p}%`, { size: 9, weight: "bold", color: p > 40 ? D.warn : D.accent })) + bar(p, p > 40 ? D.warn : D.accent, 4))).join(""))) +
    F("Pages", { flex: "row", gap: 2, p: 3, rounded: 9, bg: "#262626", w: "fill" },
      ["Overview", "Activity", "Breakdown", "Tools"].map((l) => F("Page", { flex: "row", items: "center", justify: "center", grow: 1, py: 6, rounded: 7, bg: l === activePage ? "#404040" : "#FFFFFF00" }, T(l, { size: 10, weight: l === activePage ? "semibold" : "regular", color: l === activePage ? D.text : D.sec }))).join("")) +
    children,
  });

const usageOverview = usageShell("Usage · Overview", "Overview",
  sectionLabel("At a glance") +
  F("Tiles", { flex: "row", gap: 8, w: "fill" },
    F("T1", { flex: "col", gap: 2, p: 10, rounded: 10, bg: D.card, grow: 1 }, T("STREAK", { size: 8, weight: "bold", color: D.sec }), T("39", { size: 22, weight: "bold", color: D.warn }), T("54 active days", { size: 8, color: D.ter })) +
    F("T2", { flex: "col", gap: 2, p: 10, rounded: 10, bg: D.card, grow: 1 }, T("TODAY", { size: 8, weight: "bold", color: D.sec }), T("4.026", { size: 22, weight: "bold", color: D.text }), T("steps", { size: 8, color: D.ter }))) +
  F("Tiles2", { flex: "row", gap: 8, w: "fill" },
    F("T1", { flex: "col", gap: 2, p: 10, rounded: 10, bg: D.card, grow: 1 }, T("PROMPTS", { size: 8, weight: "bold", color: D.sec }), T("3.301", { size: 22, weight: "bold", color: D.text }), T("387 sessions", { size: 8, color: D.ter })) +
    F("T2", { flex: "col", gap: 2, p: 10, rounded: 10, bg: D.card, grow: 1 }, T("TOTAL COST", { size: 8, weight: "bold", color: D.sec }), T("$50.42", { size: 22, weight: "bold", color: D.accent }), T("60.3k steps", { size: 8, color: D.ter }))) +
  F("Tiles3", { flex: "row", gap: 8, w: "fill" },
    F("T1", { flex: "col", gap: 2, p: 10, rounded: 10, bg: D.card, grow: 1 }, T("TOKENS", { size: 8, weight: "bold", color: D.sec }), T("223.0M", { size: 22, weight: "bold", color: D.text }), T("9.5B cache read", { size: 8, color: D.ter })) +
    F("T2", { flex: "col", gap: 2, p: 10, rounded: 10, bg: D.card, grow: 1 }, T("TOOL CALLS", { size: 8, weight: "bold", color: D.sec }), T("74.248", { size: 22, weight: "bold", color: D.text }), T("274 subagents", { size: 8, color: D.ter }))) +
  F("Trend", { flex: "col", gap: 6, p: 11, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, chip("Steps", D.accent) + chip("Cost", D.sec) + chip("Tokens", D.sec) + F("S", { grow: 1 }) + chip("30D", D.sec)) +
    F("Bars", { flex: "row", items: "end", gap: 3, w: "fill", h: 110 }, [20, 32, 24, 44, 38, 52, 30, 60, 46, 70, 36, 58, 66, 42, 74, 54, 80, 62, 90, 68, 84, 96, 72, 88, 60, 78, 54, 70, 46, 58].map((h) => F("B", { w: 15, h, rounded: 3, bg: D.running })).join(""))),
);

const usageActivity = usageShell("Usage · Activity", "Activity",
  F("H", { flex: "row", items: "center", justify: "between", w: "fill" }, T("Daily agent steps", { size: 11, weight: "semibold", color: D.text }) + chip("90D", D.sec)) +
  F("Heat", { flex: "col", gap: 3, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    Array.from({ length: 7 }, (_, r) => F("Week", { flex: "row", gap: 3, w: "fill" },
      Array.from({ length: 18 }, (_, c) => F("D", { w: 16, h: 16, rounded: 3, bg: ["#242424", "#1E4A38", "#2B6B4E", "#3AA877", "#4DD9A0"][(r * 5 + c * 3) % 5] })).join(""))).join("")) +
  sectionLabel("Top projects by cost") +
  [["stuttgart-uni-assistant", "$28.14", 72], ["ai-tools", "$14.11", 36], ["cisco-anyconnect", "$4.20", 11], ["expo-tools", "$2.60", 7]].map(([n, c, p]) =>
    F("Project", { flex: "col", gap: 4, p: 9, rounded: 9, bg: D.card, w: "fill" }, F("H", { flex: "row", justify: "between", w: "fill" }, T(n, { size: 10, color: D.text }), T(c, { size: 10, weight: "semibold", color: D.accent })) + bar(p, D.accent, 4))).join("") +
  T("The same windows drive the Overview trend and the heatmap.", { size: 9, color: D.ter, w: "fill" }),
);

const usageBreakdown = usageShell("Usage · Breakdown", "Breakdown",
  sectionLabel("Token mix") +
  F("Mix", { flex: "col", gap: 7, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    [["Input", 42.1, D.input], ["Output", 18.4, D.output], ["Reasoning", 6.2, D.reasoning], ["Cache read", 149.8, D.cacheRead], ["Cache write", 6.5, D.cacheWrite]].map(([n, v, c]) =>
      F("Row", { flex: "col", gap: 4, w: "fill" }, F("H", { flex: "row", justify: "between", w: "fill" }, T(n, { size: 9, color: D.text }), T(`${v}M`, { size: 9, color: c })) + bar((v / 150) * 100, c, 4))).join("")) +
  sectionLabel("Per model") +
  [["deepseek-v4.1-flash", "3.180 steps", "$38.10"], ["kimi-k2.5", "612 steps", "$7.90"], ["claude-sonnet-4.5", "208 steps", "$4.42"]].map(([n, s, c]) =>
    F("Model", { flex: "row", items: "center", gap: 7, p: 9, rounded: 9, bg: D.card, w: "fill" }, I("lucide:sparkles", 10, D.purple) + T(n, { size: 10, weight: "semibold", color: D.text, w: "fill" }) + T(s, { size: 9, color: D.sec }) + T(c, { size: 10, weight: "semibold", color: D.accent }))).join(""),
);

const usageTools = usageShell("Usage · Tools", "Tools",
  F("Summary", { flex: "row", gap: 8, w: "fill" },
    F("S1", { flex: "col", gap: 2, p: 10, rounded: 10, bg: D.card, grow: 1 }, T("CALLS", { size: 8, weight: "bold", color: D.sec }), T("74.248", { size: 20, weight: "bold", color: D.text })) +
    F("S2", { flex: "col", gap: 2, p: 10, rounded: 10, bg: D.card, grow: 1 }, T("SUCCESS", { size: 8, weight: "bold", color: D.sec }), T("99.1%", { size: 20, weight: "bold", color: D.accent })) +
    F("S3", { flex: "col", gap: 2, p: 10, rounded: 10, bg: D.card, grow: 1 }, T("FAILED", { size: 8, weight: "bold", color: D.sec }), T("642", { size: 20, weight: "bold", color: D.danger }))) +
  sectionLabel("Per tool") +
  [["shell", 38240, 99.8, "111ms"], ["edit", 12820, 99.6, "9ms"], ["read", 9820, 100, "4ms"], ["grep", 6100, 99.9, "12ms"], ["write", 3204, 99.2, "6ms"], ["todowrite", 1102, 100, "2ms"]].map(([n, c, p, ms]) =>
    F("Tool", { flex: "col", gap: 4, p: 9, rounded: 9, bg: D.card, w: "fill" },
      F("H", { flex: "row", justify: "between", w: "fill" }, T(n, { size: 10, weight: "semibold", color: D.text }), T(`${c} calls · ${p}% · ${ms}`, { size: 9, color: D.sec })) + bar(p, p > 99.5 ? D.accent : D.warn, 4))).join(""),
);

const usageNoKey = panel({ tabs: macTabs4, active: "Usage", name: "Usage · no Go key", children:
  F("Pages", { flex: "row", gap: 2, p: 3, rounded: 9, bg: "#262626", w: "fill" },
    ["Overview", "Activity", "Breakdown", "Tools"].map((l) => F("Page", { flex: "row", items: "center", justify: "center", grow: 1, py: 6, rounded: 7, bg: l === "Overview" ? "#404040" : "#FFFFFF00" }, T(l, { size: 10, weight: l === "Overview" ? "semibold" : "regular", color: l === "Overview" ? D.text : D.sec }))).join("")) +
  F("Tiles", { flex: "row", gap: 8, w: "fill" },
    F("T1", { flex: "col", gap: 2, p: 10, rounded: 10, bg: D.card, grow: 1 }, T("TODAY", { size: 8, weight: "bold", color: D.sec }), T("1.616", { size: 22, weight: "bold", color: D.text }), T("steps", { size: 8, color: D.ter })) +
    F("T2", { flex: "col", gap: 2, p: 10, rounded: 10, bg: D.card, grow: 1 }, T("TOTAL COST", { size: 8, weight: "bold", color: D.sec }), T("$28.54", { size: 22, weight: "bold", color: D.accent }), T("last known", { size: 8, color: D.ter }))) +
  notice("lucide:cloud-off", "Showing the last known usage from disk. The usage API is unreachable; values may be stale.", D.warn) +
  T("Plan limits are hidden when no OpenCode Go key is configured. Everything else still works from the hub cache.", { size: 9, color: D.ter, lineHeight: 14, w: "fill" }) +
  emptyState("lucide:key-round", "No Go plan key", "Add a usage key in ~/.config/opencode/opencodebar.json or OPENCODE_GO_USAGE_KEY to see rolling, weekly and monthly limits.", { h: 220 }),
});

export default function () {
  return pageParts({
    title: "macOS — projects and usage",
    subtitle: "Projects keep each kind of content on its own tab; Usage splits one long dashboard into four pages. Both show the last known numbers when the service is away.",
    meta: "Sources: ProjectsTab.swift · ProjectDetailView.swift · ProjectDetailAnalytics.swift · ProjectSessions.swift · ProjectFilesView.swift · GitViews.swift · UsageTab.swift · UsageCharts.swift",
    width: 3000,
    sections: [
      group("Projects", "Running work first, then most recently active. Search, empty and non-repository states included.", [
        F("Col", { flex: "col", gap: 10 }, T("Projects · populated", { size: 13, weight: "semibold", color: "#2B3038" }), projects),
        F("Col", { flex: "col", gap: 10 }, T("Projects · empty", { size: 13, weight: "semibold", color: "#2B3038" }), projectsEmpty),
        F("Col", { flex: "col", gap: 10 }, T("Project · Overview", { size: 13, weight: "semibold", color: "#2B3038" }), projectOverview),
      ].join("")),
      group("Project tabs · analytics", "Scoped stats, aggregated patches and the file browser.", [
        F("Col", { flex: "col", gap: 10 }, T("Project · Stats", { size: 13, weight: "semibold", color: "#2B3038" }), projectStats),
        F("Col", { flex: "col", gap: 10 }, T("Project · Changes", { size: 13, weight: "semibold", color: "#2B3038" }), projectChanges),
        F("Col", { flex: "col", gap: 10 }, T("Project · Files", { size: 13, weight: "semibold", color: "#2B3038" }), projectFiles),
      ].join("")),
      group("Project tabs · history", "The commit graph keeps parent links, merges and side branches; non-repositories explain themselves.", [
        F("Col", { flex: "col", gap: 10 }, T("Project · Git", { size: 13, weight: "semibold", color: "#2B3038" }), projectGit),
        F("Col", { flex: "col", gap: 10 }, T("Project · non-git empty", { size: 13, weight: "semibold", color: "#2B3038" }), projectGitEmpty),
      ].join("")),
      group("Usage · overview and activity", "Four pages, plan limits pinned above, stale data labelled rather than hidden.", [
        F("Col", { flex: "col", gap: 10 }, T("Usage · Overview", { size: 13, weight: "semibold", color: "#2B3038" }), usageOverview),
        F("Col", { flex: "col", gap: 10 }, T("Usage · Activity", { size: 13, weight: "semibold", color: "#2B3038" }), usageActivity),
      ].join("")),
      group("Usage · breakdown, tools and fallbacks", "Token mix, per-model and per-tool breakdowns, plus the no-key and stale states.", [
        F("Col", { flex: "col", gap: 10 }, T("Usage · Breakdown", { size: 13, weight: "semibold", color: "#2B3038" }), usageBreakdown),
        F("Col", { flex: "col", gap: 10 }, T("Usage · Tools", { size: 13, weight: "semibold", color: "#2B3038" }), usageTools),
        F("Col", { flex: "col", gap: 10 }, T("Usage · no Go key + stale", { size: 13, weight: "semibold", color: "#2B3038" }), usageNoKey),
      ].join("")),
    ],
  });
}
