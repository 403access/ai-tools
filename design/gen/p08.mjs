import { D, F, T, I, chip, card, sectionLabel, pageParts, group, bar, notice, emptyState, phone, iconButton } from "./kit.mjs";

const dot = (c = D.accent) => F("Dot", { w: 7, h: 7, rounded: 4, bg: c });

const vms = phone({ title: "VMs", sub: "1 running", active: "VMs", name: "iOS · VMs", children:
  F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, T("Virtual machines", { size: 13, weight: "bold", color: D.text }) + F("S", { grow: 1 }) + chip("1 running", D.running) + iconButton("lucide:plus", D.accent, 11)) +
  [["nixos-dev", "running", "192.168.64.12", "2 CPU · 4 GB · 20 GB", D.accent, "Stop"],
   ["nixos-build", "stopped", "—", "4 CPU · 8 GB · 40 GB", D.sec, "Start"],
   ["nixos-lab", "paused", "192.168.64.18", "2 CPU · 4 GB · 20 GB", D.warn, "Resume"]].map(([n, s, ip, spec, c, action]) =>
    F("VM", { flex: "col", gap: 4, p: 9, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("H", { flex: "row", items: "center", gap: 6, w: "fill" },
        F("I", { w: 24, h: 24, rounded: 7, bg: c + "1A", items: "center", justify: "center" }, I("lucide:server", 11, c)) +
        F("B", { flex: "col", gap: 1, grow: 1 }, T(n, { size: 10, weight: "bold", color: D.text }), T(`NixOS · ${s} · ${ip}`, { size: 7, color: D.sec })) + chip(action, c)) +
      F("M", { flex: "row", items: "center", gap: 5, w: "fill" }, T(spec, { size: 7, color: D.ter }), F("S", { grow: 1 }), T("2 changes pending", { size: 7, color: D.warn })))).join("") +
  F("Setup", { flex: "row", items: "center", gap: 5, p: 8, rounded: 8, bg: D.accent + "0E", stroke: D.accent + "2A", strokeWidth: 1, w: "fill" }, I("lucide:check-circle", 9, D.accent) + T("Helper signed · Nix ready · builder ready", { size: 7, color: "#B7D8CA", w: "fill" })) +
  T("Storage: ~/.local/share/opencodebar/vms", { size: 7, color: D.ter }),
});

const vmsEmpty = phone({ title: "VMs", sub: "", active: "VMs", name: "iOS · VMs empty", children:
  F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, T("Virtual machines", { size: 13, weight: "bold", color: D.text }) + F("S", { grow: 1 }) + iconButton("lucide:plus", D.accent, 11)) +
  emptyState("lucide:server", "No virtual machines", "Create a NixOS guest. The hub builds a raw EFI image, runs it with Virtualization.framework, and applies changes over SSH.", { h: 300 }) +
  F("Build", { flex: "row", items: "center", justify: "center", gap: 5, py: 8, rounded: 9, bg: D.accent, w: "fill" }, I("lucide:wand-sparkles", 10, "#062017") + T("Build a NixOS machine", { size: 10, weight: "bold", color: "#062017" })),
});

const vmDetail = F("iOS · VM detail", { flex: "col", gap: 8, w: 414, h: 896, bg: "#121212", rounded: 34, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
  F("Top", { flex: "row", items: "center", gap: 6, w: "fill", px: 16, py: 10 },
    I("lucide:chevron-left", 12, D.accent) + T("VMs", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("running", D.accent) + I("lucide:ellipsis", 11, D.sec)),
  F("Head", { flex: "row", items: "center", gap: 8, p: 9, w: "fill", rounded: 11, bg: D.card, stroke: D.border, strokeWidth: 1 },
    F("I", { w: 36, h: 36, rounded: 9, bg: D.accent + "1A", items: "center", justify: "center" }, I("lucide:server", 17, D.accent)) +
    F("B", { flex: "col", gap: 1, grow: 1 },
      T("nixos-dev", { size: 13, weight: "bold", color: D.text }) +
      T("NixOS 26.05 · 192.168.64.12", { size: 7, color: D.sec }) +
      F("M", { flex: "row", gap: 3 }, chip("2 CPU", D.sec) + chip("4 GB", D.sec) + chip("20 GB", D.sec)))),
  F("Tabs", { flex: "row", gap: 2, p: 3, w: "fill", rounded: 9, bg: "#262626" },
    ["Overview", "Console", "Packages", "Logs"].map((l) =>
      F("Tab", { flex: "row", items: "center", justify: "center", grow: 1, py: 5, rounded: 7, bg: l === "Overview" ? "#404040" : "#FFFFFF00" },
        T(l, { size: 8, weight: l === "Overview" ? "semibold" : "regular", color: l === "Overview" ? D.text : D.sec }))).join("")),
  F("Body", { flex: "col", gap: 8, px: 16, grow: 1, w: "fill" },
    F("Tiles", { flex: "row", gap: 6, w: "fill" },
      F("T", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("CPU", { size: 7, weight: "bold", color: D.sec }), T("12%", { size: 15, weight: "bold", color: D.text }), T("load 0.42", { size: 7, color: D.ter })) +
      F("T", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("MEMORY", { size: 7, weight: "bold", color: D.sec }), T("1.8 GB", { size: 15, weight: "bold", color: D.text }), T("of 4 GB", { size: 7, color: D.ter }))) +
    F("Tiles2", { flex: "row", gap: 6, w: "fill" },
      F("T", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("DISK", { size: 7, weight: "bold", color: D.sec }), T("6.2 GB", { size: 15, weight: "bold", color: D.text }), T("of 20 GB", { size: 7, color: D.ter })) +
      F("T", { flex: "col", gap: 1, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("UPTIME", { size: 7, weight: "bold", color: D.sec }), T("2h 14m", { size: 15, weight: "bold", color: D.text }), T("generation 42", { size: 7, color: D.ter }))) +
    F("Card", { flex: "col", gap: 3, p: 9, rounded: 9, bg: D.card, w: "fill" },
      T("GUEST", { size: 7, weight: "bold", color: D.sec }) +
      T("Hostname nixos-dev · kernel 6.12.4", { size: 7, color: D.text }) +
      T("ssh opencodebar@192.168.64.12", { size: 7, color: D.accent }) +
      T("Generation 42 (current)", { size: 7, color: D.sec })) +
    F("Actions", { flex: "row", gap: 5, w: "fill" },
      F("A", { flex: "row", items: "center", justify: "center", gap: 3, grow: 1, py: 7, rounded: 8, bg: D.warn + "18", stroke: D.warn + "2E", strokeWidth: 1 }, I("lucide:pause", 9, D.warn) + T("Pause", { size: 9, color: D.warn })) +
      F("B", { flex: "row", items: "center", justify: "center", gap: 3, grow: 1, py: 7, rounded: 8, bg: "#FFFFFF0A" }, I("lucide:rotate-ccw", 9, D.sec) + T("Restart", { size: 9, color: D.sec })) +
      F("C", { flex: "row", items: "center", justify: "center", gap: 3, grow: 1, py: 7, rounded: 8, bg: D.danger + "14", stroke: D.danger + "2E", strokeWidth: 1 }, I("lucide:square", 8, D.danger) + T("Stop", { size: 9, color: D.danger })))),
);

const console = F("iOS · VM console", { flex: "col", gap: 6, w: 414, h: 700, bg: "#0E0E0E", rounded: 20, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
  F("Bar", { flex: "row", items: "center", gap: 5, w: "fill", px: 12, py: 8, bg: "#1B1B1B" }, I("lucide:terminal", 10, D.accent) + T("nixos-dev · hvc0", { size: 8, color: D.sec, w: "fill" }) + chip("live", D.accent)),
  F("Log", { flex: "col", gap: 2, p: 10, w: "fill", grow: 1 },
    T("[    0.000000] Booting Linux on physical CPU 0x0", { size: 8, color: "#8A8A8A" }) +
    T("[    0.412000] virtio_blk virtio1: [vda] 41943040 sectors", { size: 8, color: "#8A8A8A" }) +
    T("[    2.114000] systemd[1]: Started SSH Daemon.", { size: 8, color: D.accent }) +
    T("nixos-dev login: opencodebar", { size: 8, color: "#D0D0D0" }) +
    T("[opencodebar@nixos-dev:~]$ nixos-rebuild switch --flake .#nixos-dev", { size: 8, color: "#D0D0D0" }) +
    T("building the system configuration...", { size: 8, color: D.warn }) +
    T("activation script finished successfully", { size: 8, color: D.accent }) +
    T("[opencodebar@nixos-dev:~]$ ▊", { size: 8, color: "#D0D0D0" })),
);

const builder = F("iOS · VM builder", { flex: "col", gap: 8, w: 414, h: 896, bg: "#121212", rounded: 34, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
  F("Top", { flex: "row", items: "center", gap: 6, w: "fill", px: 16, py: 10 }, I("lucide:x", 12, D.sec) + T("New VM", { size: 10, weight: "bold", color: D.text, w: "fill" }) + chip("Step 1 of 4", D.sec)),
  F("Body", { flex: "col", gap: 8, px: 16, grow: 1, w: "fill" },
    T("Build a NixOS machine", { size: 16, weight: "bold", color: D.text }) +
    T("Pick a preset, then add options, users and ports.", { size: 8, color: D.sec }) +
    F("Presets", { flex: "row", gap: 4, w: "fill" }, chip("Minimal", D.accent) + chip("Development", D.sec) + chip("Desktop", D.sec) + chip("Server", D.sec)) +
    F("Search", { flex: "row", items: "center", gap: 5, px: 8, py: 6, rounded: 8, bg: D.field }, I("lucide:search", 9, D.sec) + T("Search options", { size: 8, color: D.ter, w: "fill" })) +
    F("Cats", { flex: "row", gap: 4, wrap: true, w: "fill", h: "hug" }, chip("System", D.sec) + chip("Development", D.accent) + chip("Services", D.sec) + chip("Networking", D.sec) + chip("AI", D.sec)) +
    [["git", true], ["neovim", true], ["nodejs_24", true], ["bun", true], ["python3", false], ["docker", false]].map(([n, on]) =>
      F("Opt", { flex: "row", items: "center", gap: 6, p: 7, rounded: 7, bg: on ? D.accent + "0C" : D.card, stroke: on ? D.accent + "2A" : D.border, strokeWidth: 1, w: "fill" },
        F("B", { w: 12, h: 12, rounded: 3, bg: on ? D.accent : "#00000000", stroke: on ? "#00000000" : D.ter, strokeWidth: 1, items: "center", justify: "center" }, on ? I("lucide:check", 8, "#062017") : "") +
        T(n, { size: 8.5, weight: "semibold", color: D.text, w: "fill" }))).join("")),
  F("Footer", { flex: "row", gap: 5, w: "fill", p: 16 }, F("S", { grow: 1 }) + F("Next", { flex: "row", items: "center", gap: 4, px: 12, py: 7, rounded: 8, bg: D.accent }, T("Next · Users", { size: 9, weight: "bold", color: "#062017" }) + I("lucide:chevron-right", 9, "#062017"))),
);

const widget = (name, w, h, children) =>
  F(name, { flex: "col", gap: 6, w, h, p: 10, rounded: 18, bg: "#151515", stroke: D.border, strokeWidth: 1, overflow: "hidden" }, children);

const liveSmall = widget("Widget · Live small", 170, 170,
  F("H", { flex: "row", items: "center", gap: 4, w: "fill" }, F("Logo", { w: 18, h: 18, rounded: 5, bg: D.accent, items: "center", justify: "center" }, I("lucide:code-xml", 10, "#0B1F17")) + T("OpenCode", { size: 7, weight: "bold", color: D.text, w: "fill" }) + dot()) +
  T("2", { size: 40, weight: "bold", color: D.text }) + T("running", { size: 8, color: D.sec }) +
  T("Match iPhone dark theme", { size: 7, color: D.text, w: "fill", maxLines: 1, truncate: true }) +
  T("ai-tools · 14m", { size: 6, color: D.sec }),
);

const liveMedium = widget("Widget · Live medium", 360, 170,
  F("H", { flex: "row", items: "center", gap: 4, w: "fill" }, F("Logo", { w: 18, h: 18, rounded: 5, bg: D.accent, items: "center", justify: "center" }, I("lucide:code-xml", 10, "#0B1F17")) + T("OpenCode", { size: 8, weight: "bold", color: D.text, w: "fill" }) + dot() + T("2 running", { size: 7, color: D.accent })) +
  F("Row", { flex: "col", gap: 2, p: 6, rounded: 6, bg: D.card, w: "fill" }, T("Match iPhone dark theme", { size: 7.5, weight: "semibold", color: D.text }), T("ai-tools · 14m 04s · $0.05", { size: 6, color: D.sec })) +
  F("Row", { flex: "col", gap: 2, p: 6, rounded: 6, bg: D.card, w: "fill" }, T("Mark messages as read on open", { size: 7.5, weight: "semibold", color: D.text }), T("stuttgart · 3h 39m · $0.41", { size: 6, color: D.sec })),
);

const liveLarge = widget("Widget · Live large", 360, 380,
  F("H", { flex: "row", items: "center", gap: 4, w: "fill" }, F("Logo", { w: 20, h: 20, rounded: 6, bg: D.accent, items: "center", justify: "center" }, I("lucide:code-xml", 11, "#0B1F17")) + T("OpenCode", { size: 9, weight: "bold", color: D.text, w: "fill" }) + dot() + T("2 running", { size: 8, color: D.accent })) +
  [["Match iPhone dark theme", "ai-tools · 14m 04s · $0.05"], ["Mark messages as read on open", "stuttgart · 3h 39m · $0.41"]].map(([t, m]) =>
    F("Run", { flex: "col", gap: 2, p: 7, rounded: 7, bg: D.card, w: "fill" }, T(t, { size: 8, weight: "semibold", color: D.text }), T(m, { size: 6.5, color: D.sec }))).join("") +
  T("RECENT", { size: 6, weight: "bold", color: D.ter, letterSpacing: 0.5 }) +
  [["Mobile app with shared server", "13m ago"], ["Add dedicated profile page", "23m ago"], ["Central quiz screen", "3h ago"]].map(([t, m]) =>
    F("R", { flex: "row", items: "center", gap: 4, w: "fill" }, F("Dot", { w: 4, h: 4, rounded: 2, bg: "#5A5A5A" }) + T(t, { size: 6.5, color: D.text, w: "fill" }) + T(m, { size: 6, color: D.ter }))).join(""),
);

const usageSmall = widget("Widget · Usage small", 170, 170,
  T("TODAY", { size: 7, weight: "bold", color: D.sec, letterSpacing: 0.5 }) + T("1.616", { size: 30, weight: "bold", color: D.text }) + T("steps", { size: 7, color: D.ter }) +
  F("Row", { flex: "row", gap: 8, w: "fill" }, T("$28.54", { size: 8, color: D.accent }) + T("2.907 prompts", { size: 6, color: D.sec })),
);

const usageMedium = widget("Widget · Usage medium", 360, 170,
  F("H", { flex: "row", items: "center", gap: 4, w: "fill" }, T("OpenCode", { size: 8, weight: "bold", color: D.text }) + F("S", { grow: 1 }) + T("30D", { size: 6, color: D.ter })) +
  F("Row", { flex: "row", gap: 10, w: "fill" },
    F("A", { flex: "col", gap: 1, grow: 1 }, T("TODAY", { size: 6, weight: "bold", color: D.sec }), T("1.616", { size: 20, weight: "bold", color: D.text }), T("steps", { size: 6, color: D.ter })) +
    F("B", { flex: "col", gap: 1, grow: 1 }, T("COST", { size: 6, weight: "bold", color: D.sec }), T("$28.54", { size: 20, weight: "bold", color: D.accent }), T("total", { size: 6, color: D.ter }))) +
  F("Bars", { flex: "row", items: "end", gap: 2, w: "fill", h: 40 }, [20, 30, 22, 40, 35, 48, 28, 55, 42, 66, 34, 58, 62, 38].map((h) => F("B", { w: 8, h, rounded: 1, bg: D.running })).join("")),
);

const usageLarge = widget("Widget · Usage large", 360, 380,
  F("H", { flex: "row", items: "center", gap: 4, w: "fill" }, T("OpenCode", { size: 9, weight: "bold", color: D.text }) + F("S", { grow: 1 }) + T("30 days", { size: 6, color: D.ter })) +
  F("Row", { flex: "row", gap: 8, w: "fill" },
    F("A", { flex: "col", gap: 1, grow: 1 }, T("TODAY", { size: 6, weight: "bold", color: D.sec }), T("1.616", { size: 22, weight: "bold", color: D.text })) +
    F("B", { flex: "col", gap: 1, grow: 1 }, T("COST", { size: 6, weight: "bold", color: D.sec }), T("$28.54", { size: 22, weight: "bold", color: D.accent }))) +
  F("Bars", { flex: "row", items: "end", gap: 2, w: "fill", h: 70 }, [18, 30, 22, 40, 35, 48, 28, 55, 42, 66, 34, 58, 62, 38, 72, 50, 78, 60, 86, 64].map((h) => F("B", { w: 8, h, rounded: 1, bg: D.running })).join("")) +
  T("PLAN LIMITS", { size: 6, weight: "bold", color: D.ter, letterSpacing: 0.5 }) +
  [["Rolling", 14], ["Weekly", 27], ["Monthly", 18]].map(([l, p]) => F("P", { flex: "row", items: "center", gap: 4, w: "fill" }, T(l, { size: 6, color: D.sec, w: 40 }) + bar(p, D.accent, 3) + T(`${p}%`, { size: 6, color: D.sec }))).join(""),
);

const ipad = F("iPad", { flex: "row", w: 820, h: 1180, bg: "#121212", rounded: 24, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
  F("Sidebar", { flex: "col", gap: 10, w: 240, h: "fill", p: 16, bg: "#171717", stroke: "#FFFFFF0E", strokeWidth: 1 },
    F("Brand", { flex: "row", items: "center", gap: 7 }, F("Logo", { w: 28, h: 28, rounded: 8, bg: D.accent, items: "center", justify: "center" }, I("lucide:code-xml", 15, "#0B1F17")) + T("OpenCodeBar", { size: 12, weight: "bold", color: D.text })) +
    ["Tasks", "Live", "Projects", "Usage", "Host", "VMs", "Settings"].map((l, i) => F("N", { flex: "row", items: "center", gap: 6, px: 8, py: 6, rounded: 7, bg: i === 1 ? "#FFFFFF12" : "#FFFFFF00", w: "fill" }, I(["lucide:list-checks", "lucide:radio", "lucide:folder", "lucide:bar-chart-3", "lucide:monitor", "lucide:server", "lucide:settings"][i], 12, i === 1 ? D.text : D.sec) + T(l, { size: 9, color: i === 1 ? D.text : D.sec, w: "fill" }) + (i === 1 ? chip("2", D.running) : ""))).join("")),
  F("Main", { flex: "col", gap: 8, w: "fill", h: "fill", p: 16 },
    F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, T("Live", { size: 18, weight: "bold", color: D.text }) + F("S", { grow: 1 }) + chip("2 running", D.running)) +
    F("Run", { flex: "col", gap: 3, p: 9, rounded: 9, bg: D.card, w: "fill" }, T("Match iPhone dark theme to macOS tray app", { size: 10, weight: "semibold", color: D.text }), T("ai-tools · deepseek-v4.1-flash · 14m 04s · $0.05", { size: 7, color: D.sec })) +
    F("Run", { flex: "col", gap: 3, p: 9, rounded: 9, bg: D.card, w: "fill" }, T("Mark messages as read on open", { size: 10, weight: "semibold", color: D.text }), T("stuttgart-uni-assistant · 3h 39m · $0.41", { size: 7, color: D.sec })) +
    sectionLabel("Recent") +
    [1, 2, 3, 4].map(() => F("R", { flex: "col", gap: 2, p: 8, rounded: 8, bg: D.card, w: "fill" }, T("Mobile app with shared server and SQLite database", { size: 8, color: D.text }), T("ai-tools · 13m ago · $0.29", { size: 7, color: D.sec }))).join("")),
);

export default function () {
  return pageParts({
    title: "iOS — VMs, widgets and iPad",
    subtitle: "NixOS guests from the phone, the Home Screen widgets that keep status visible, and the iPad layout that reuses the same state in a wider canvas.",
    meta: "Sources: VirtualMachinesView.swift · VirtualMachineMobileDetailView.swift · NewVirtualMachineSheet.swift · LiveWidget.swift · UsageWidget.swift · WidgetTheme.swift · RootView landscape/iPad",
    width: 2400,
    sections: [
      group("Virtual machines", "List, empty and guest detail with the serial console and builder.", [
        F("Col", { flex: "col", gap: 10 }, T("VMs · populated", { size: 13, weight: "semibold", color: "#2B3038" }), vms),
        F("Col", { flex: "col", gap: 10 }, T("VMs · empty", { size: 13, weight: "semibold", color: "#2B3038" }), vmsEmpty),
        F("Col", { flex: "col", gap: 10 }, T("VM · detail", { size: 13, weight: "semibold", color: "#2B3038" }), vmDetail),
      ].join("")),
      group("Console and builder", "A typeable virtio console and a touch-friendly option browser.", [
        F("Col", { flex: "col", gap: 10 }, T("VM · console", { size: 13, weight: "semibold", color: "#2B3038" }), console),
        F("Col", { flex: "col", gap: 10 }, T("VM · builder", { size: 13, weight: "semibold", color: "#2B3038" }), builder),
      ].join("")),
      group("Home Screen widgets", "Live and Usage in small, medium and large families; they fall back to the last snapshot.", [
        F("Col", { flex: "col", gap: 10 }, T("Live · small", { size: 13, weight: "semibold", color: "#2B3038" }), liveSmall),
        F("Col", { flex: "col", gap: 10 }, T("Live · medium", { size: 13, weight: "semibold", color: "#2B3038" }), liveMedium),
        F("Col", { flex: "col", gap: 10 }, T("Live · large", { size: 13, weight: "semibold", color: "#2B3038" }), liveLarge),
        F("Col", { flex: "col", gap: 10 }, T("Usage · small", { size: 13, weight: "semibold", color: "#2B3038" }), usageSmall),
      ].join("")),
      group("Usage widgets and iPad", "Usage medium/large and the wide layout.", [
        F("Col", { flex: "col", gap: 10 }, T("Usage · medium", { size: 13, weight: "semibold", color: "#2B3038" }), usageMedium),
        F("Col", { flex: "col", gap: 10 }, T("Usage · large", { size: 13, weight: "semibold", color: "#2B3038" }), usageLarge),
        F("Col", { flex: "col", gap: 10 }, T("iPad · landscape-capable layout", { size: 13, weight: "semibold", color: "#2B3038" }), ipad),
      ].join("")),
    ],
  });
}
