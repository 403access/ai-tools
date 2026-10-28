import { D, F, T, I, chip, card, sectionLabel, pageParts, group, bar, notice, emptyState, panel, macTabs3, macTabs4, macTabs5, macTabs7, iconButton } from "./kit.mjs";

const dot = (color = D.running) => F("Dot", { w: 7, h: 7, rounded: 4, bg: color });

const runningRow = (title, activity, actIcon, actColor, project, model, agent, elapsed, cost, tokens) =>
  F("Running row", { flex: "col", gap: 7, p: 12, rounded: 14, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
    F("Top", { flex: "row", items: "center", gap: 8, w: "fill" },
      dot() + T(title, { size: 13, weight: "semibold", color: D.text, w: "fill" }) +
      T(elapsed, { size: 9, color: D.running }) + I("lucide:chevron-right", 12, D.ter)) +
    F("Activity", { flex: "row", items: "center", gap: 6, w: "fill" },
      I(actIcon, 10, actColor) + T(activity, { size: 10, color: actColor, w: "fill" }) + T("4s", { size: 9, color: D.ter })) +
    F("Meta", { flex: "row", items: "center", gap: 5, w: "fill", wrap: true, h: "hug" },
      chip(project, D.accent) + chip(model, D.sec) + chip(agent, D.purple, "lucide:user")) +
    F("Footer", { flex: "row", items: "center", gap: 9, w: "fill" },
      I("lucide:clock", 9, D.ter) + T(elapsed, { size: 9, color: D.ter }) +
      T(cost, { size: 9, weight: "semibold", color: D.accent }) +
      I("lucide:list", 9, D.ter) + T(tokens, { size: 9, color: D.ter })),
  );

const recentRow = (title, project, model, time, cost, tokens, live = false) =>
  F("Recent row", { flex: "col", gap: 6, p: 11, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
    F("Top", { flex: "row", items: "center", gap: 8, w: "fill" },
      (live ? dot() : F("Dot", { w: 6, h: 6, rounded: 3, bg: "#5A5A5A" })) +
      T(title, { size: 12, weight: "semibold", color: D.text, w: "fill" }) +
      T(cost, { size: 10, weight: "semibold", color: live ? D.running : D.accent }) +
      I("lucide:chevron-right", 11, D.ter)) +
    F("Meta", { flex: "row", items: "center", gap: 5, w: "fill" },
      T(project, { size: 9, weight: "medium", color: D.accent, w: "fill" }) +
      chip(model, D.sec) + T(time, { size: 9, color: D.ter }) + T(tokens, { size: 9, color: D.ter })),
  );

const taskCard = (status, icon, tint, title, project, time, labels, action) =>
  F("Task card", { flex: "row", gap: 9, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
    F("Status", { w: 18, h: 18, rounded: 9, bg: tint + "22", items: "center", justify: "center" }, I(icon, 10, tint)) +
    F("Body", { flex: "col", gap: 5, grow: 1, w: "fill" },
      T(title, { size: 12, weight: "semibold", color: D.text, w: "fill" }) +
      T(`${project} · ${time}`, { size: 9, color: D.sec }) +
      F("Labels", { flex: "row", gap: 4, w: "fill", h: "hug" }, labels.map((l) => chip(l[0], l[1], l[2])).join(""))) +
    F("Actions", { flex: "row", gap: 4, items: "center" },
      F("Action", { w: 20, h: 20, rounded: 6, bg: tint + "18", items: "center", justify: "center" }, I(action, 10, tint)) +
      I("lucide:ellipsis", 12, D.sec)),
  );

const projectRow = (initials, color, name, path, running, time, extra = "") =>
  F("Project row", { flex: "row", items: "center", gap: 9, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill", h: "hug" },
    F("Icon", { w: 36, h: 36, rounded: 9, bg: color, items: "center", justify: "center" }, T(initials, { size: 12, weight: "bold", color: "#FFFFFF" })) +
    F("Body", { flex: "col", gap: 3, grow: 1 },
      F("Name", { flex: "row", items: "center", gap: 6 }, T(name, { size: 12, weight: "bold", color: D.text }) + chip("git", D.purple) + (extra ? chip(extra, D.sec) : "")) +
      T(path, { size: 9, color: D.sec })) +
    F("Right", { flex: "col", gap: 3, items: "end" },
      running ? F("Run", { flex: "row", items: "center", gap: 3 }, dot(D.running), T(String(running), { size: 9, weight: "bold", color: D.running })) : "",
      T(time, { size: 9, color: D.ter })) +
    I("lucide:chevron-right", 12, D.ter),
  );

const livePanel = panel({
  tabs: macTabs3,
  active: "Live",
  sub: "Connected · v2.1.4",
  footer: "2 active",
  name: "Panel · Live",
  children:
    sectionLabel("Running", T("2", { size: 10, weight: "bold", color: D.running })) +
    runningRow("Match iPhone dark theme to macOS tray app", "Thinking · The user has an issue: Metro serves on 8081…", "lucide:brain", D.reasoning, "ai-tools", "deepseek-v4.1-flash", "build", "14m 04s", "$0.41", "1.2M tok") +
    runningRow("Exploring potential new features", "Running · sleep 12; echo done", "lucide:terminal", D.warn, "stuttgart-uni-assistant", "deepseek-v4.1-flash", "build", "10m 25s", "$0.07", "227k tok") +
    sectionLabel("Recent", T("All 90", { size: 10, weight: "semibold", color: D.accent })) +
    recentRow("Quiz zur Einführung in Pragmatik: Kontext, Im…", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "1m ago", "$0.08", "331k tok") +
    recentRow("Refresh session on app reactivation; silently l…", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "3m ago", "$0.23", "880k tok") +
    recentRow("Reusable quiz components for linguistics topi…", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "13h ago", "$0.51", "1.6M tok") +
    recentRow("Adding global and project-specific graphs to…", "ai-tools", "deepseek-v4.1-flash", "13h ago", "$0.08", "325k tok") +
    recentRow("Map mail UI and data sources", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "3h ago", "$0.09", "444k tok") +
    recentRow("Central quiz screen with module tiles", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "3h ago", "$0.29", "983k tok") +
    recentRow("Add dedicated profile page with sharing", "stuttgart-uni-assistant", "deepseek-v4.1-flash", "23m ago", "$0.13", "428k tok"),
});

const liveEmpty = panel({
  tabs: macTabs3,
  active: "Live",
  footer: "0 active",
  name: "Panel · Live empty",
  children:
    sectionLabel("Running", T("0", { size: 10, weight: "bold", color: D.sec })) +
    emptyState("lucide:radio", "No sessions running", "Start a session from Projects or New task. Running work appears here with its current tool, cost and tokens.") +
    sectionLabel("Recent", T("All 0", { size: 10, weight: "semibold", color: D.ter })) +
    emptyState("lucide:history", "No recent sessions", "Sessions you run in OpenCode show up here after the hub syncs.", { h: 150 }),
});

const tasksPanel = panel({
  tabs: macTabs5,
  active: "Tasks",
  footer: "2 active",
  name: "Panel · Tasks",
  children:
    F("Filters", { flex: "row", gap: 5, w: "fill", h: "hug" },
      chip("Review 3", D.warn) + chip("Working 2", D.running) + chip("Done 12", D.sec) + chip("All 17", D.sec)) +
    F("Filter meta", { flex: "row", items: "center", justify: "between", w: "fill" },
      T("Auto-labelled from the request", { size: 9, color: D.ter }) +
      F("New", { flex: "row", items: "center", gap: 3, px: 7, py: 3, rounded: 99, bg: D.accent + "22" }, I("lucide:plus", 9, D.accent) + T("New task", { size: 9, weight: "bold", color: D.accent }))) +
    sectionLabel("Needs review", T("3", { size: 10, weight: "bold", color: D.warn })) +
    taskCard("review", "lucide:eye", D.warn, "Add map-based language family quiz", "stuttgart-uni-assistant", "48m ago", [["Feature", D.accent, "lucide:sparkles"], ["Product", D.running], ["Breaking change", D.warn, "lucide:triangle-alert"]], "lucide:check") +
    taskCard("review", "lucide:eye", D.warn, "Show actual changes and diffs in session and project views", "ai-tools", "1h ago", [["Feature", D.accent, "lucide:sparkles"], ["Technical", D.running]], "lucide:check") +
    taskCard("review", "lucide:eye", D.warn, "Harden VM serial console reconnect path", "ai-tools", "2h ago", [["Bug", D.danger, "lucide:bug"], ["Security-sensitive", D.warn, "lucide:shield-alert"]], "lucide:check") +
    sectionLabel("In progress", T("2", { size: 10, weight: "bold", color: D.running })) +
    taskCard("working", "lucide:loader", D.running, "Match iPhone dark theme to macOS tray app", "ai-tools", "14m", [["Feature", D.accent, "lucide:sparkles"], ["Product", D.running]], "lucide:arrow-up-right") +
    taskCard("working", "lucide:loader", D.running, "Central quiz screen with module tiles", "stuttgart-uni-assistant", "39m", [["Refactor", D.purple], ["Technical", D.running]], "lucide:arrow-up-right") +
    sectionLabel("Done", T("12", { size: 10, weight: "bold", color: D.sec })) +
    taskCard("done", "lucide:check", D.accent, "Reusable quiz components for linguistics topics", "stuttgart-uni-assistant", "13h ago", [["Feature", D.accent, "lucide:sparkles"], ["Technical", D.running]], "lucide:undo-2") +
    taskCard("done", "lucide:check", D.accent, "Refresh session on app reactivation", "stuttgart-uni-assistant", "3m ago", [["Bug", D.danger, "lucide:bug"], ["Technical", D.running]], "lucide:undo-2"),
});

const tasksEmpty = panel({
  tabs: macTabs5,
  active: "Tasks",
  footer: "0 active",
  name: "Panel · Tasks empty",
  children:
    F("Filters", { flex: "row", gap: 5, w: "fill", h: "hug" },
      chip("Review 0", D.warn) + chip("Working 0", D.running) + chip("Done 0", D.sec) + chip("All 0", D.sec)) +
    F("Filter meta", { flex: "row", items: "center", justify: "between", w: "fill" },
      T("Auto-labelled from the request", { size: 9, color: D.ter }) +
      F("New", { flex: "row", items: "center", gap: 3, px: 7, py: 3, rounded: 99, bg: D.accent + "22" }, I("lucide:plus", 9, D.accent) + T("New task", { size: 9, weight: "bold", color: D.accent }))) +
    emptyState("lucide:list-checks", "No tasks yet", "New sessions become tasks. Finished work lands here for review.", { h: 320 }) +
    F("Hint", { flex: "row", gap: 8, p: 12, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      I("lucide:wand-sparkles", 14, D.purple) +
      F("Text", { flex: "col", gap: 3 }, T("Labels are free", { size: 11, weight: "semibold", color: D.text }), T("Type, scope and risk are inferred from the request — no model call, no extra tokens.", { size: 9, color: D.sec, w: "fill" }))),
});

const settingsPanel = panel({
  tabs: macTabs4,
  active: "Settings",
  footer: "3 active",
  name: "Panel · Settings",
  children:
    sectionLabel("Connected devices", T("3", { size: 10, weight: "bold", color: D.sec })) +
    F("Device", { flex: "row", gap: 8, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("Icon", { w: 30, h: 30, rounded: 8, bg: D.accent + "1F", items: "center", justify: "center" }, I("lucide:laptop", 14, D.accent)) +
      F("Body", { flex: "col", gap: 2, grow: 1 }, T("Oliver’s MacBook Pro", { size: 11, weight: "semibold", color: D.text }), T("macOS 26.0 · 1.0 (42) · live now", { size: 9, color: D.sec })) + chip("live", D.accent)) +
    F("Device", { flex: "row", gap: 8, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("Icon", { w: 30, h: 30, rounded: 8, bg: D.running + "1F", items: "center", justify: "center" }, I("lucide:smartphone", 14, D.running)) +
      F("Body", { flex: "col", gap: 2, grow: 1 }, T("Oliver’s iPhone", { size: 11, weight: "semibold", color: D.text }), T("iOS 18.2 · 1.0 (42) · live now", { size: 9, color: D.sec })) + chip("live", D.accent)) +
    F("Device", { flex: "row", gap: 8, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("Icon", { w: 30, h: 30, rounded: 8, bg: D.purple + "1F", items: "center", justify: "center" }, I("lucide:tablet", 14, D.purple)) +
      F("Body", { flex: "col", gap: 2, grow: 1 }, T("Oliver’s iPad", { size: 11, weight: "semibold", color: D.text }), T("iPadOS 18.2 · 1.0 (42) · 2h ago", { size: 9, color: D.sec })) + chip("idle", D.ter)) +
    sectionLabel("Server") +
    card(
      F("R1", { flex: "row", justify: "between", w: "fill" }, T("Hub version", { size: 10, color: D.sec }), T("0.16.0", { size: 10, weight: "semibold", color: D.text })) +
      F("R2", { flex: "row", justify: "between", w: "fill" }, T("Address", { size: 10, color: D.sec }), T("http://192.168.1.42:8787", { size: 10, color: D.text })) +
      F("R3", { flex: "row", justify: "between", w: "fill" }, T("Uptime", { size: 10, color: D.sec }), T("3d 14h · OpenCode connected", { size: 10, color: D.accent })) +
      F("R4", { flex: "row", justify: "between", w: "fill" }, T("Cache", { size: 10, color: D.sec }), T("2.907 sessions · 61.2k messages", { size: 10, color: D.text })) +
      F("R5", { flex: "row", justify: "between", w: "fill" }, T("Last sync", { size: 10, color: D.sec }), T("just now", { size: 10, color: D.text })) +
      F("R6", { flex: "row", justify: "between", w: "fill" }, T("Database", { size: 10, color: D.sec }), T("~/Library/…/hub.sqlite", { size: 9, color: D.ter })),
      { p: 10, gap: 5 },
    ) +
    F("Actions", { flex: "row", gap: 6, w: "fill" },
      F("B1", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 6, rounded: 9, bg: D.accent + "22" }, I("lucide:refresh-cw", 10, D.accent) + T("Sync now", { size: 10, weight: "semibold", color: D.accent })) +
      F("B2", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 6, rounded: 9, bg: "#FFFFFF0A" }, I("lucide:rotate-ccw", 10, D.sec) + T("Restart hub", { size: 10, color: D.sec })) +
      F("B3", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 6, rounded: 9, bg: "#FFFFFF0A" }, I("lucide:folder-open", 10, D.sec) + T("Reveal data", { size: 10, color: D.sec }))) +
    F("Power + dev", { flex: "row", gap: 8, w: "fill" },
      card(
        F("H", { flex: "row", items: "center", gap: 5 }, I("lucide:moon", 10, D.warn) + T("KEEP MAC AWAKE", { size: 9, weight: "bold", color: D.sec, letterSpacing: 0.6 })) +
        T("Holds an idle-sleep assertion while the hub runs. The display can still turn off.", { size: 9, color: D.sec, lineHeight: 13 }) +
        F("Toggle", { flex: "row", justify: "between", items: "center", w: "fill" }, T("Prevent sleep", { size: 10, color: D.text }), F("Switch", { w: 32, h: 18, rounded: 9, bg: D.accent, items: "end", justify: "center", px: 2 }, F("Knob", { w: 14, h: 14, rounded: 7, bg: "#FFFFFF" }))),
        { w: 320, p: 10, gap: 6 },
      ) +
      card(
        F("H", { flex: "row", items: "center", gap: 5 }, I("lucide:bug", 10, D.purple) + T("DEVELOPER", { size: 9, weight: "bold", color: D.sec, letterSpacing: 0.6 })) +
        T("Live activity log of hub requests, sync cycles, events and errors. Never includes the token.", { size: 9, color: D.sec, lineHeight: 13 }) +
        F("Link", { flex: "row", items: "center", gap: 4 }, T("Open activity log", { size: 10, weight: "semibold", color: D.accent }) + I("lucide:arrow-right", 10, D.accent)),
        { w: 360, p: 10, gap: 6 },
      )),
});

const sheet = (name, title, sub, children, w = 560, h = 560) =>
  F(name, { flex: "col", gap: 14, w, h, p: 20, rounded: 18, bg: D.panel, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
    F("Sheet header", { flex: "row", items: "start", justify: "between", w: "fill" },
      F("Titles", { flex: "col", gap: 3 }, T(title, { size: 18, weight: "bold", color: D.text }) + (sub ? T(sub, { size: 10, color: D.sec, w: 420 }) : "")) +
      F("Close", { w: 24, h: 24, rounded: 12, bg: "#FFFFFF0A", items: "center", justify: "center" }, I("lucide:x", 11, D.sec))) +
    children,
  );

const field = (label, value, hint = "") =>
  F("Field", { flex: "col", gap: 4, w: "fill", h: "hug" },
    T(label.toUpperCase(), { size: 9, weight: "bold", color: D.sec, letterSpacing: 0.6 }) +
    F("Input", { flex: "row", items: "center", gap: 6, px: 10, py: 7, rounded: 9, bg: D.field, stroke: D.border, strokeWidth: 1, w: "fill" }, T(value, { size: 11, color: D.text, w: "fill" })) +
    (hint ? T(hint, { size: 9, color: D.ter }) : ""),
  );

const newSession = sheet("Sheet · New session", "New session", "Pick a project, choose a workspace, and send the first message in the same step.", 
  F("Project", { flex: "row", items: "center", gap: 9, p: 10, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("Icon", { w: 32, h: 32, rounded: 8, bg: "#2F7CF6", items: "center", justify: "center" }, T("AT", { size: 11, weight: "bold", color: "#FFFFFF" })) +
    F("Body", { flex: "col", gap: 2, grow: 1 }, T("ai-tools", { size: 12, weight: "bold", color: D.text }), T("~/Developer/ai-tools", { size: 9, color: D.sec })) + I("lucide:chevrons-up-down", 12, D.sec)) +
  F("Workspace", { flex: "row", gap: 4, p: 3, rounded: 9, bg: "#FFFFFF08", w: "fill" },
    F("Cur", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 5, rounded: 7, bg: D.accent + "22" }, I("lucide:folder", 10, D.accent) + T("Current folder", { size: 10, weight: "semibold", color: D.accent })) +
    F("Wt", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 5 }, I("lucide:git-branch", 10, D.sec) + T("Git worktree", { size: 10, color: D.sec }))) +
  field("Title", "Match iPhone dark theme", "Optional — OpenCode derives one from the first message.") +
  F("Message", { flex: "col", gap: 4, w: "fill", grow: 1 },
    T("FIRST MESSAGE", { size: 9, weight: "bold", color: D.sec, letterSpacing: 0.6 }) +
    F("Editor", { flex: "col", p: 10, rounded: 10, bg: D.field, stroke: D.border, strokeWidth: 1, w: "fill", grow: 1 },
      T("Bring the phone dark palette in line with the macOS tray panel. Check the running row, chips and dock, then update the screenshots.", { size: 11, color: D.text, lineHeight: 17, w: "fill" }) +
      F("Tools", { flex: "row", items: "center", gap: 6, w: "fill" },
        I("lucide:mic", 12, D.sec) + I("lucide:paperclip", 12, D.sec) + F("S", { grow: 1 }) + T("⌘↵ to start", { size: 9, color: D.ter })))) +
  F("Options", { flex: "row", gap: 8, w: "fill" },
    chip("deepseek-v4.1-flash", D.sec) + chip("build", D.purple, "lucide:user") + chip("variant: high", D.running)) +
  F("Start", { flex: "row", items: "center", justify: "center", gap: 6, py: 8, rounded: 10, bg: D.accent, w: "fill" }, I("lucide:play", 12, "#062017") + T("Start session", { size: 12, weight: "bold", color: "#062017" })),
);

const projectPicker = sheet("Sheet · Project picker", "Choose a project", "13 projects · sort by recent, name or running work.", 
  F("Search", { flex: "row", items: "center", gap: 7, px: 10, py: 7, rounded: 10, bg: D.field, stroke: D.border, strokeWidth: 1, w: "fill" }, I("lucide:search", 12, D.sec) + T("Search projects", { size: 11, color: D.ter, w: "fill" })) +
  F("Sort", { flex: "row", gap: 4, w: "fill" },
    chip("Recent", D.accent) + chip("Name", D.sec) + chip("Running", D.sec) + F("S", { grow: 1 }) + chip("All", D.sec) + chip("Git", D.sec) + chip("Sandbox", D.sec)) +
  F("List", { flex: "col", gap: 6, w: "fill", grow: 1, overflow: "hidden" },
    projectRow("AT", "#2F7CF6", "ai-tools", "~/Developer/ai-tools", 2, "just now") +
    projectRow("SU", "#1F6FEB", "stuttgart-uni-assistant", "~/Developer/stuttgart-uni-assistant", 2, "1m ago") +
    projectRow("CA", "#8B5CF6", "cisco-anyconnect", "~/Developer/cisco-anyconnect", 0, "26m ago") +
    projectRow("ET", "#7C3AED", "expo-tools", "~/Developer/expo-tools", 0, "yesterday") +
    projectRow("WD", "#2563EB", "wow-diary", "~/Desktop/wow-diary", 0, "Aug 27") +
    projectRow("FI", "#10B981", "file_indexer", "~/Desktop/Desktop…objects/file_indexer", 0, "Aug 25", "1 sandbox")) +
  F("Footer", { flex: "row", gap: 6, w: "fill" },
    F("Clone", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 7, rounded: 9, bg: "#FFFFFF0A" }, I("lucide:git-fork", 10, D.sec) + T("Clone repository", { size: 10, color: D.sec })) +
    F("Worktree", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 7, rounded: 9, bg: D.accent + "22" }, I("lucide:git-branch", 10, D.accent) + T("New worktree", { size: 10, weight: "semibold", color: D.accent }))),
);

const modelPicker = sheet("Sheet · Model picker", "Model", "Providers and models available to OpenCode. Cost is per million tokens.", 
  F("Search", { flex: "row", items: "center", gap: 7, px: 10, py: 7, rounded: 10, bg: D.field, stroke: D.border, strokeWidth: 1, w: "fill" }, I("lucide:search", 12, D.sec) + T("Search models", { size: 11, color: D.ter, w: "fill" })) +
  F("Filters", { flex: "row", gap: 4, w: "fill" }, chip("All", D.accent) + chip("Reasoning", D.sec) + chip("Tools", D.sec) + chip("Fast", D.sec)) +
  sectionLabel("OpenCode Go") +
  F("Models", { flex: "col", gap: 5, w: "fill" },
    F("Model", { flex: "row", items: "center", gap: 8, p: 9, rounded: 9, bg: D.accent + "10", stroke: D.accent + "33", strokeWidth: 1, w: "fill" },
      I("lucide:check-circle", 12, D.accent) + F("Body", { flex: "col", gap: 1, grow: 1 }, T("deepseek-v4.1-flash", { size: 11, weight: "semibold", color: D.text }), T("1M context · $0.20 in / $0.80 out", { size: 9, color: D.sec })) + chip("selected", D.accent)) +
    F("Model", { flex: "row", items: "center", gap: 8, p: 9, rounded: 9, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("Circle", { w: 12, h: 12, rounded: 6, stroke: D.ter, strokeWidth: 1 }) + F("Body", { flex: "col", gap: 1, grow: 1 }, T("kimi-k2.5", { size: 11, weight: "semibold", color: D.text }), T("256k context · $0.60 in / $2.50 out", { size: 9, color: D.sec })) + chip("reasoning", D.reasoning)) +
    F("Model", { flex: "row", items: "center", gap: 8, p: 9, rounded: 9, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("Circle", { w: 12, h: 12, rounded: 6, stroke: D.ter, strokeWidth: 1 }) + F("Body", { flex: "col", gap: 1, grow: 1 }, T("qwen3.5-coder", { size: 11, weight: "semibold", color: D.text }), T("128k context · local Ollama · free", { size: 9, color: D.sec })) + chip("local", D.warn))),
  sectionLabel("Anthropic") +
  F("Models", { flex: "col", gap: 5, w: "fill" },
    F("Model", { flex: "row", items: "center", gap: 8, p: 9, rounded: 9, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("Circle", { w: 12, h: 12, rounded: 6, stroke: D.ter, strokeWidth: 1 }) + F("Body", { flex: "col", gap: 1, grow: 1 }, T("claude-sonnet-4.5", { size: 11, weight: "semibold", color: D.text }), T("200k context · $3 in / $15 out", { size: 9, color: D.sec })) + chip("tools", D.running))),
  F("Variant", { flex: "col", gap: 4, w: "fill" },
    T("VARIANT", { size: 9, weight: "bold", color: D.sec, letterSpacing: 0.6 }) +
    F("Row", { flex: "row", gap: 4, w: "fill" }, chip("default", D.sec) + chip("high", D.accent) + chip("max", D.sec))),
);

const retrySheet = sheet("Sheet · Retry turn", "Retry failed turn", "The provider returned 429 after 12.4s. The conversation is unchanged.", 
  F("Error", { flex: "col", gap: 5, p: 12, rounded: 12, bg: D.danger + "10", stroke: D.danger + "33", strokeWidth: 1, w: "fill" },
    F("H", { flex: "row", items: "center", gap: 6 }, I("lucide:triangle-alert", 12, D.danger) + T("HTTP 429 · rate limit exceeded", { size: 11, weight: "bold", color: D.danger })) +
    T("Upstream message: “Rate limit reached for requests. Please try again in 18s.”", { size: 10, color: "#E8B4B6", lineHeight: 15, w: "fill" })) +
  F("Primary", { flex: "row", gap: 6, w: "fill" },
    F("Retry", { flex: "row", items: "center", justify: "center", gap: 5, grow: 1, py: 8, rounded: 9, bg: D.accent }, I("lucide:refresh-cw", 11, "#062017") + T("Retry here", { size: 11, weight: "bold", color: "#062017" })) +
    F("Continue", { flex: "row", items: "center", justify: "center", gap: 5, grow: 1, py: 8, rounded: 9, bg: "#FFFFFF0A" }, I("lucide:skip-forward", 11, D.sec) + T("Send “continue”", { size: 11, color: D.sec }))) +
  sectionLabel("Retry options") +
  field("Model", "deepseek-v4.1-flash", "Used for the retried turn only.") +
  field("Agent", "build", "The agent and variant are remembered for this retry.") +
  F("Fork", { flex: "row", items: "start", gap: 8, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("Check", { w: 16, h: 16, rounded: 4, bg: D.accent, items: "center", justify: "center" }, I("lucide:check", 10, "#062017")) +
    F("Body", { flex: "col", gap: 2, grow: 1 }, T("Fork before the failed prompt", { size: 11, weight: "semibold", color: D.text }), T("Creates a new session from the conversation up to this turn. The original stays untouched and is linked as the source.", { size: 9, color: D.sec, lineHeight: 13, w: "fill" }))) +
  T("Retrying does not duplicate the prompt in the transcript; the failed turn is replaced in place.", { size: 9, color: D.ter, lineHeight: 13, w: "fill" }),
);

const pauseSheet = sheet("Sheet · Pause", "Pause session", "The current turn is interrupted and held. The hub continues it automatically at the deadline, even after a restart.", 
  F("Session", { flex: "col", gap: 3, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    T("Match iPhone dark theme to macOS tray app", { size: 12, weight: "semibold", color: D.text }) +
    T("ai-tools · build · deepseek-v4.1-flash · 14m 04s", { size: 9, color: D.sec })) +
  sectionLabel("Hold for") +
  F("Durations", { flex: "row", gap: 5, w: "fill" }, chip("15 min", D.sec) + chip("1 hour", D.accent) + chip("4 hours", D.sec) + chip("Until I continue", D.sec)) +
  field("Resume at", "21:40", "Or pick a clock time. The hub schedules the continue.") +
  F("Explain", { flex: "col", gap: 4, p: 10, rounded: 10, bg: D.running + "0E", stroke: D.running + "2E", strokeWidth: 1, w: "fill" },
    T("What happens", { size: 10, weight: "bold", color: D.running }) +
    T("The session leaves the Running list and shows a Paused badge in Recent. Continue sends “continue” into the same conversation and starts a fresh turn. Typing a prompt releases the hold too.", { size: 9, color: "#B7C9D2", lineHeight: 14, w: "fill" })) +
  F("Buttons", { flex: "row", gap: 6, w: "fill" },
    F("Pause", { flex: "row", items: "center", justify: "center", gap: 5, grow: 1, py: 8, rounded: 9, bg: D.warn }, I("lucide:pause", 11, "#241A05") + T("Pause session", { size: 11, weight: "bold", color: "#241A05" })) +
    F("Stop", { flex: "row", items: "center", justify: "center", gap: 5, grow: 1, py: 8, rounded: 9, bg: D.danger + "18", stroke: D.danger + "33", strokeWidth: 1 }, I("lucide:square", 10, D.danger) + T("Stop instead", { size: 11, color: D.danger }))),
);

const deviceDetail = F("Device detail", { flex: "col", gap: 14, w: 560, h: 720, p: 20, rounded: 18, bg: D.panel, stroke: D.border, strokeWidth: 1 },
  F("Header", { flex: "row", items: "center", gap: 7 }, I("lucide:chevron-left", 13, D.accent) + T("Settings", { size: 11, color: D.accent }) + F("S", { grow: 1 }) + chip("live", D.accent)) +
  F("Identity", { flex: "row", gap: 10, items: "center", w: "fill" },
    F("Icon", { w: 44, h: 44, rounded: 12, bg: D.running + "1F", items: "center", justify: "center" }, I("lucide:smartphone", 20, D.running)) +
    F("Body", { flex: "col", gap: 2 }, T("Oliver’s iPhone", { size: 18, weight: "bold", color: D.text }), T("iOS 18.2 · OpenCodeBar 1.0 (42)", { size: 10, color: D.sec }))) +
  card(
    F("R1", { flex: "row", justify: "between", w: "fill" }, T("Stable ID", { size: 10, color: D.sec }), T("ios-8F2C-4A1D", { size: 10, color: D.text })) +
    F("R2", { flex: "row", justify: "between", w: "fill" }, T("Platform", { size: 10, color: D.sec }), T("iOS · iPhone17,1", { size: 10, color: D.text })) +
    F("R3", { flex: "row", justify: "between", w: "fill" }, T("First seen", { size: 10, color: D.sec }), T("Sep 14, 2026 · 18:02", { size: 10, color: D.text })) +
    F("R4", { flex: "row", justify: "between", w: "fill" }, T("Last seen", { size: 10, color: D.sec }), T("just now", { size: 10, color: D.accent })) +
    F("R5", { flex: "row", justify: "between", w: "fill" }, T("Connection", { size: 10, color: D.sec }), T("live · SSE subscribed", { size: 10, color: D.accent })) +
    F("R6", { flex: "row", justify: "between", w: "fill" }, T("Cache", { size: 10, color: D.sec }), T("2.907 sessions · 61.2k messages", { size: 10, color: D.text })),
    { p: 10, gap: 6 },
  ) +
  F("Activity", { flex: "col", gap: 5, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    T("RECENT ACTIVITY", { size: 9, weight: "bold", color: D.sec, letterSpacing: 0.6 }) +
    F("A1", { flex: "row", justify: "between", w: "fill" }, T("GET /api/sync?since=…", { size: 9, color: D.text }), T("2s ago", { size: 9, color: D.ter })) +
    F("A2", { flex: "row", justify: "between", w: "fill" }, T("POST /api/session/:id/prompt", { size: 9, color: D.text }), T("4m ago", { size: 9, color: D.ter })) +
    F("A3", { flex: "row", justify: "between", w: "fill" }, T("SSE hub.sessions", { size: 9, color: D.text }), T("4m ago", { size: 9, color: D.ter }))) +
  F("Danger", { flex: "row", items: "center", justify: "center", gap: 5, py: 8, rounded: 9, bg: D.danger + "14", stroke: D.danger + "2E", strokeWidth: 1, w: "fill" }, I("lucide:trash-2", 11, D.danger) + T("Forget this device", { size: 11, weight: "semibold", color: D.danger })),
);

const developerLog = F("Developer log", { flex: "col", gap: 10, w: 700, h: 760, p: 20, rounded: 18, bg: D.panel, stroke: D.border, strokeWidth: 1 },
  F("Header", { flex: "row", items: "center", gap: 7 },
    I("lucide:chevron-left", 13, D.accent) + T("Settings", { size: 11, color: D.accent }) + F("S", { grow: 1 }) + chip("paused", D.warn) + iconButton("lucide:copy", D.sec, 11) + iconButton("lucide:trash-2", D.danger, 11)) +
  T("Activity log", { size: 20, weight: "bold", color: D.text }) +
  T("Hub requests, sync cycles, event-stream changes and errors. Bodies and the hub token are never recorded.", { size: 10, color: D.sec, w: 600, lineHeight: 15 }) +
  F("Filters", { flex: "row", gap: 4, w: "fill" }, chip("All 214", D.accent) + chip("Requests 168", D.sec) + chip("Sync 22", D.sec) + chip("Events 18", D.sec) + chip("Errors 6", D.danger)) +
  F("Rows", { flex: "col", gap: 3, w: "fill", grow: 1, overflow: "hidden" },
    [["20:35:12", "sync", "hub.sessions · 2 changed · 41ms", D.accent],
     ["20:35:10", "event", "session.tool.updated · ses_9f2c · shell", D.running],
     ["20:35:08", "request", "GET /api/session?limit=50 · 200 · 18ms", D.sec],
     ["20:35:02", "error", "GET /api/usage · upstream 503 · stale cache served", D.danger],
     ["20:34:58", "sync", "hub.usage · windows updated", D.accent],
     ["20:34:51", "request", "POST /api/session/:id/prompt · 202 · 6ms", D.sec],
     ["20:34:40", "event", "hub.connected · clients 3", D.running],
     ["20:34:32", "request", "GET /api/project · 200 · 12ms", D.sec],
     ["20:34:20", "sync", "delta · 12 sessions · 240 messages", D.accent],
     ["20:34:11", "error", "SSE reconnect · backoff 2s", D.danger],
     ["20:34:02", "request", "GET /api/health · 200 · 2ms", D.sec]]
      .map(([time, type, msg, color]) =>
        F("Log row", { flex: "row", gap: 8, items: "start", w: "fill", py: 4, stroke: "#FFFFFF08", strokeWidth: 1 },
          T(time, { size: 9, color: D.ter }) + chip(type, color) + T(msg, { size: 9.5, color: D.sec, w: "fill" }))).join("")),
);

const menuArt = F("Menu bar", { flex: "col", gap: 16, w: 900, h: "hug", p: 20, rounded: 18, bg: "#DDE1E7", stroke: "#00000012", strokeWidth: 1 },
  F("Bar", { flex: "row", items: "center", gap: 14, w: "fill", h: 30, px: 12, rounded: 8, bg: "#F7F8FA", stroke: "#00000010", strokeWidth: 1 },
    I("lucide:apple", 13, "#1B1F24") + T("OpenCodeBar", { size: 10, weight: "bold", color: "#1B1F24" }) + T("File", { size: 10, color: "#3C4450" }) + T("Edit", { size: 10, color: "#3C4450" }) + T("View", { size: 10, color: "#3C4450" }) + T("Window", { size: 10, color: "#3C4450" }) + T("Help", { size: 10, color: "#3C4450" }) + F("S", { grow: 1 }) +
    I("lucide:wifi", 11, "#3C4450") + I("lucide:battery-full", 13, "#3C4450") +
    F("Glyph", { flex: "row", items: "center", gap: 2, px: 4, py: 2, rounded: 4, bg: "#1B1F24" }, I("lucide:terminal", 13, "#FFFFFF") + T("3", { size: 9, weight: "bold", color: "#4DD9A0" }))) +
  F("Note", { flex: "row", gap: 10, w: "fill" },
    F("Left", { flex: "col", gap: 5, w: 440 }, T("LEFT CLICK", { size: 9, weight: "bold", color: "#7A828C", letterSpacing: 0.8 }) + T("Desktop window", { size: 15, weight: "bold", color: "#1B1F24" }) + T("Opens the resizable three-column app, or brings it to the front if it is already open. Closing it returns to menu-bar-only mode.", { size: 10, color: "#4C545E", lineHeight: 15, w: 440 })) +
    F("Right", { flex: "col", gap: 5, w: 400 }, T("RIGHT / CONTROL CLICK", { size: 9, weight: "bold", color: "#7A828C", letterSpacing: 0.8 }) + T("Compact panel", { size: 15, weight: "bold", color: "#1B1F24" }) + T("The tray popover with Live, Usage, Projects and Settings. It shares live state with the desktop window.", { size: 10, color: "#4C545E", lineHeight: 15, w: 400 }))) +
  F("Menu", { flex: "col", gap: 4, w: 300, p: 8, rounded: 10, bg: "#FFFFFF", stroke: "#00000014", strokeWidth: 1 },
    F("M1", { flex: "row", justify: "between", items: "center", w: "fill", px: 6, py: 4 }, T("Open panel", { size: 10, color: "#1B1F24" }), T("⌥⌘P", { size: 9, color: "#8A919B" })) +
    F("M2", { flex: "row", justify: "between", items: "center", w: "fill", px: 6, py: 4 }, T("Open desktop window", { size: 10, color: "#1B1F24" }), T("⌘O", { size: 9, color: "#8A919B" })) +
    F("M3", { flex: "row", justify: "between", items: "center", w: "fill", px: 6, py: 4 }, T("Start session…", { size: 10, color: "#1B1F24" }), T("⌘N", { size: 9, color: "#8A919B" })) +
    F("Sep", { w: "fill", h: 1, bg: "#00000010" }) +
    F("M4", { flex: "row", justify: "between", items: "center", w: "fill", px: 6, py: 4 }, T("Keep Mac awake", { size: 10, color: "#1B1F24" }), I("lucide:check", 10, "#0B8F65")) +
    F("M5", { flex: "row", justify: "between", items: "center", w: "fill", px: 6, py: 4 }, T("Quit OpenCodeBar", { size: 10, color: "#1B1F24" }), T("⌘Q", { size: 9, color: "#8A919B" }))),
);

const desktop = F("Desktop window", { flex: "row", w: 1440, h: 900, bg: "#171717", rounded: 14, stroke: "#FFFFFF18", strokeWidth: 1, overflow: "hidden" },
  F("Sidebar", { flex: "col", gap: 14, w: 260, h: "fill", p: 16, bg: "#141414", stroke: "#FFFFFF0E", strokeWidth: 1 },
    F("Brand", { flex: "row", items: "center", gap: 8 }, F("Logo", { w: 30, h: 30, rounded: 9, bg: D.accent, items: "center", justify: "center" }, I("lucide:code-xml", 16, "#0B1F17")), T("OpenCodeBar", { size: 14, weight: "bold", color: D.text })) +
    F("Nav", { flex: "col", gap: 2, w: "fill" },
      ["Tasks", "Live", "Projects", "Usage", "System", "VMs", "Settings"].map((l, i) =>
        F("Nav item", { flex: "row", items: "center", gap: 8, px: 9, py: 7, rounded: 8, bg: i === 2 ? "#FFFFFF12" : "#FFFFFF00", w: "fill" },
          I(["lucide:list-checks", "lucide:radio", "lucide:folder", "lucide:bar-chart-3", "lucide:monitor", "lucide:server", "lucide:settings"][i], 13, i === 2 ? D.text : D.sec) +
          T(l, { size: 11, weight: i === 2 ? "semibold" : "regular", color: i === 2 ? D.text : D.sec }) + F("S", { grow: 1 }) +
          (i === 1 ? chip("2", D.running) : i === 5 ? chip("1", D.accent) : ""))).join("")) +
    sectionLabel("Projects", T("13", { size: 9, color: D.ter })) +
    F("Projects", { flex: "col", gap: 2, w: "fill" },
      [["AT", "#2F7CF6", "ai-tools", true], ["SU", "#1F6FEB", "stuttgart-uni-assistant", true], ["CA", "#8B5CF6", "cisco-anyconnect", false], ["ET", "#7C3AED", "expo-tools", false], ["WD", "#2563EB", "wow-diary", false]]
        .map(([i, c, n, on]) => F("P", { flex: "row", items: "center", gap: 7, px: 6, py: 5, rounded: 7, bg: on ? "#FFFFFF0A" : "#FFFFFF00", w: "fill" },
          F("I", { w: 20, h: 20, rounded: 5, bg: c, items: "center", justify: "center" }, T(i, { size: 8, weight: "bold", color: "#FFFFFF" })) +
          T(n, { size: 10, color: on ? D.text : D.sec, w: "fill" }) + (on ? dot() : ""))).join("")) +
    F("S", { grow: 1 }) +
    F("Footer", { flex: "row", items: "center", gap: 6, w: "fill" }, dot(D.accent) + T("Connected · v2.1.4", { size: 9, color: D.sec }))),
  F("Middle", { flex: "col", gap: 10, w: 380, h: "fill", p: 16, bg: "#191919", stroke: "#FFFFFF0E", strokeWidth: 1 },
    F("Head", { flex: "row", items: "center", gap: 6 }, T("stuttgart-uni-assistant", { size: 14, weight: "bold", color: D.text, w: "fill" }) + chip("2 running", D.running)) +
    F("Tabs", { flex: "row", gap: 4, w: "fill" }, chip("Overview", D.accent) + chip("Stats", D.sec) + chip("Changes", D.sec) + chip("Files", D.sec) + chip("Git", D.sec) + chip("Sessions", D.sec)) +
    sectionLabel("Running", T("2", { size: 9, weight: "bold", color: D.running })) +
    F("Run rows", { flex: "col", gap: 5, w: "fill" },
      [["List tutor and participants when opening ILIAS items", "1h 21m"], ["Add map-based language family quiz", "48m 49s"]].map(([t, e]) =>
        F("Run", { flex: "row", items: "center", gap: 6, p: 8, rounded: 8, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
          dot() + T(t, { size: 10, color: D.text, w: "fill" }) + T(e, { size: 9, color: D.running }) + I("lucide:chevron-right", 10, D.ter))).join("")) +
    sectionLabel("At a glance") +
    F("Stats", { flex: "row", gap: 6, w: "fill" },
      F("S1", { flex: "col", gap: 2, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("STEPS", { size: 8, weight: "bold", color: D.sec }), T("12.582", { size: 15, weight: "bold", color: D.text })) +
      F("S2", { flex: "col", gap: 2, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("COST", { size: 8, weight: "bold", color: D.sec }), T("$14.11", { size: 15, weight: "bold", color: D.accent })) +
      F("S3", { flex: "col", gap: 2, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("TOOLS", { size: 8, weight: "bold", color: D.sec }), T("15.203", { size: 15, weight: "bold", color: D.text }))) +
    sectionLabel("Recent sessions", T("All 90", { size: 9, color: D.accent })) +
    F("Recent", { flex: "col", gap: 4, w: "fill" },
      [["List tutor and participants when opening ILIAS items", "1h 21m"], ["Add map-based language family quiz", "48m 49s"], ["Syntax I: Grundlagenquiz zu Grammatik", "1h ago"], ["Checking access to studies we aren’t enrolled…", "2h ago"]]
        .map(([t, e]) => F("R", { flex: "row", items: "center", gap: 5, p: 7, rounded: 7, bg: D.card, w: "fill" }, T(t, { size: 9, color: D.text, w: "fill" }), T(e, { size: 8, color: D.ter }))).join(""))),
  F("Detail", { flex: "col", gap: 10, w: "fill", h: "fill", p: 16, bg: "#1B1B1B" },
    F("Back", { flex: "row", items: "center", gap: 5 }, I("lucide:chevron-left", 11, D.accent) + T("Projects", { size: 10, color: D.accent }) + F("S", { grow: 1 }) + chip("Finished", D.sec)) +
    card(
      T("Show actual changes and diffs in session and project views", { size: 16, weight: "bold", color: D.text, w: "fill" }) +
      F("Meta", { flex: "row", gap: 5, w: "fill" }, chip("ai-tools", D.accent) + chip("deepseek-v4.1-flash", D.sec) + chip("build", D.purple, "lucide:user")) +
      F("Meta2", { flex: "row", gap: 10, w: "fill" }, T("1h 28m", { size: 9, color: D.sec }), T("975k tok", { size: 9, color: D.sec }), T("$0.35", { size: 9, color: D.accent })),
      { p: 12, gap: 7, bg: D.card },
    ) +
    F("Tabs", { flex: "row", gap: 4, w: "fill" }, chip("Conversation", D.accent) + chip("Stats", D.sec) + chip("Changes", D.sec) + chip("Prompts", D.sec)) +
    F("Messages", { flex: "col", gap: 6, w: "fill", grow: 1 },
      F("Msg", { flex: "col", gap: 5, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
        F("H", { flex: "row", items: "center", gap: 5 }, I("lucide:sparkles", 10, D.running) + T("Assistant", { size: 9, weight: "bold", color: D.running }) + F("S", { grow: 1 }) + T("38m ago", { size: 8, color: D.ter })) +
        F("Reason", { flex: "col", gap: 3, p: 7, rounded: 7, bg: D.reasoning + "10", stroke: D.reasoning + "22", strokeWidth: 1, w: "fill" }, T("Reasoning", { size: 9, weight: "bold", color: D.reasoning }), T("Single hub, detached (PPID 1), stats 200. We can tell the user the background wrapper stopped, but the hub is healthy…", { size: 9, color: "#C9B6D8", lineHeight: 13, w: "fill" })) +
        T("The background shell that was streaming the hub exited, but the hub itself is still running detached and healthy:", { size: 10, color: D.sec, lineHeight: 15, w: "fill" }) +
        T("• PID 78224 (parent PID 1, survives the shell)\n• Listening on http://127.0.0.1:8788\n• /api/health → 200 · /api/session/:id/stats → 200\n• No duplicate hub processes", { size: 9.5, color: "#D0D0D0", lineHeight: 15, w: "fill" })) +
      F("Msg2", { flex: "col", gap: 4, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
        F("H", { flex: "row", items: "center", gap: 5 }, I("lucide:sparkles", 10, D.running) + T("Assistant", { size: 9, weight: "bold", color: D.running }) + F("S", { grow: 1 }) + T("38m ago", { size: 8, color: D.ter })) +
        T("Working…", { size: 10, color: D.sec }))) +
    F("Composer", { flex: "row", items: "center", gap: 8, p: 9, rounded: 10, bg: D.field, stroke: D.border, strokeWidth: 1, w: "fill" },
      T("Message this session…", { size: 10, color: D.ter, w: "fill" }) + I("lucide:mic", 11, D.sec) + F("Send", { w: 22, h: 22, rounded: 11, bg: D.accent, items: "center", justify: "center" }, I("lucide:arrow-up", 11, "#062017")))),
);

export default function () {
  return pageParts({
    title: "macOS — shell and navigation",
    subtitle: "The menu bar item, the compact panel and the optional desktop window. Same state, three form factors: the panel for a glance, the desktop window for deep work, and the menu for quick actions.",
    meta: "Sources: StatusItemController.swift · DesktopWindowController.swift · PanelView.swift · DesktopView.swift · TasksTab.swift · SettingsTab.swift",
    width: 3000,
    sections: [
      group("Entry points", "One status item, two click behaviours. The terminal glyph shows the number of running sessions.", [
        F("Col", { flex: "col", gap: 10 }, T("Menu bar", { size: 13, weight: "semibold", color: "#2B3038" }), menuArt),
        F("Col", { flex: "col", gap: 10 }, T("Desktop window", { size: 13, weight: "semibold", color: "#2B3038" }), T("Three columns on wide windows: projects, sessions, detail.", { size: 10, color: "#6B7079" }), desktop),
      ].join("")),
      group("Live and Tasks", "Populated and empty. Empty states explain what will appear and how to create it.", [
        F("Col", { flex: "col", gap: 10 }, T("Live · populated", { size: 13, weight: "semibold", color: "#2B3038" }), livePanel),
        F("Col", { flex: "col", gap: 10 }, T("Live · empty", { size: 13, weight: "semibold", color: "#2B3038" }), liveEmpty),
        F("Col", { flex: "col", gap: 10 }, T("Tasks · board", { size: 13, weight: "semibold", color: "#2B3038" }), tasksPanel),
        F("Col", { flex: "col", gap: 10 }, T("Tasks · empty", { size: 13, weight: "semibold", color: "#2B3038" }), tasksEmpty),
      ].join("")),
      group("Settings and sheets", "Everything the panel can present without leaving the current context.", [
        F("Col", { flex: "col", gap: 10 }, T("Settings", { size: 13, weight: "semibold", color: "#2B3038" }), settingsPanel),
        F("Col", { flex: "col", gap: 10 }, T("Device detail", { size: 13, weight: "semibold", color: "#2B3038" }), deviceDetail),
        F("Col", { flex: "col", gap: 10 }, T("Developer activity log", { size: 13, weight: "semibold", color: "#2B3038" }), developerLog),
      ].join("")),
      group("Session creation and recovery", "The same sheets are shared with the desktop window and reachable from every empty state.", [
        F("Col", { flex: "col", gap: 10 }, T("New session", { size: 13, weight: "semibold", color: "#2B3038" }), newSession),
        F("Col", { flex: "col", gap: 10 }, T("Project picker", { size: 13, weight: "semibold", color: "#2B3038" }), projectPicker),
        F("Col", { flex: "col", gap: 10 }, T("Model picker", { size: 13, weight: "semibold", color: "#2B3038" }), modelPicker),
        F("Col", { flex: "col", gap: 10 }, T("Retry failed turn", { size: 13, weight: "semibold", color: "#2B3038" }), retrySheet),
        F("Col", { flex: "col", gap: 10 }, T("Pause session", { size: 13, weight: "semibold", color: "#2B3038" }), pauseSheet),
      ].join("")),
    ],
  });
}
