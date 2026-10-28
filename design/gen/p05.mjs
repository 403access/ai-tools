import { D, F, R, T, I, chip, card, sectionLabel, pageParts, pageHeader, group, bar, notice, emptyState, panel, macTabs7, iconButton } from "./kit.mjs";

const dot = (c = D.accent) => F("Dot", { w: 7, h: 7, rounded: 4, bg: c });

const systemPanel = (name, children) => panel({ tabs: macTabs7, active: "System", name, children });
const vmPanel = (name, children) => panel({ tabs: macTabs7, active: "VMs", name, children });

const kv = (k, v, color = D.text) => F("KV", { flex: "row", justify: "between", w: "fill" }, T(k, { size: 9.5, color: D.sec }), T(v, { size: 9.5, color }));
const tile = (label, value, sub, icon, color = D.accent) =>
  F("Tile", { flex: "col", gap: 3, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, grow: 1, w: "fill", h: "hug" },
    F("H", { flex: "row", items: "center", gap: 5 }, I(icon, 10, color) + T(label.toUpperCase(), { size: 8, weight: "bold", color: D.sec, letterSpacing: 0.6 })) +
    T(value, { size: 18, weight: "bold", color: D.text }) + T(sub, { size: 8, color: D.ter }));

const system = systemPanel("System · dashboard",
  F("Machine", { flex: "row", items: "center", gap: 9, p: 11, rounded: 12, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("Icon", { w: 38, h: 38, rounded: 10, bg: D.accent + "1A", items: "center", justify: "center" }, I("lucide:laptop", 18, D.accent)) +
    F("Body", { flex: "col", gap: 2, grow: 1 }, T("Oliver’s MacBook Pro", { size: 14, weight: "bold", color: D.text }), T("macOS 26.0 · arm64 · 14-inch · hub 0.16.0", { size: 9, color: D.sec })) +
    chip("up 3d 14h", D.accent)) +
  F("Vitals", { flex: "row", gap: 8, w: "fill" },
    tile("CPU", "18%", "10 cores · 3.2 GHz", "lucide:cpu", D.running) +
    tile("Memory", "11.4 GB", "of 32 GB · 4.1 GB swap", "lucide:memory-stick", D.purple)) +
  F("Vitals2", { flex: "row", gap: 8, w: "fill" },
    tile("Disk", "412 GB", "free of 1 TB", "lucide:hard-drive", D.warn) +
    tile("Battery", "86%", "charging · 214 cycles", "lucide:battery-charging", D.accent)) +
  sectionLabel("Now playing", chip("Music", D.sec)) +
  F("Media", { flex: "row", items: "center", gap: 9, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("Art", { w: 40, h: 40, rounded: 8, bg: "#3B4A6B", items: "center", justify: "center" }, I("lucide:music", 16, "#FFFFFF")) +
    F("Body", { flex: "col", gap: 2, grow: 1 }, T("Starry Night", { size: 11, weight: "semibold", color: D.text }), T("Don McLean · American Pie", { size: 9, color: D.sec })) +
    I("lucide:skip-back", 12, D.sec) + F("Play", { w: 24, h: 24, rounded: 12, bg: D.accent, items: "center", justify: "center" }, I("lucide:pause", 11, "#062017")) + I("lucide:skip-forward", 12, D.sec)) +
  sectionLabel("More", chip("5 sections", D.sec)) +
  F("Grid", { flex: "row", gap: 6, w: "fill" },
    ["Network", "Software", "Terminals", "Files", "Processes"].map((l) => F("More", { flex: "col", items: "center", gap: 4, p: 9, rounded: 9, bg: D.card, grow: 1 }, I(["lucide:network", "lucide:package", "lucide:terminal", "lucide:folder-open", "lucide:activity"][["Network", "Software", "Terminals", "Files", "Processes"].indexOf(l)], 14, D.sec), T(l, { size: 8, color: D.sec }))).join("")),
);

const performance = systemPanel("System · performance",
  F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, I("lucide:chevron-left", 11, D.accent) + T("System", { size: 10, color: D.accent }) + F("S", { grow: 1 }) + chip("live · 5s", D.running)) +
  T("Performance", { size: 20, weight: "bold", color: D.text }) +
  F("Tiles", { flex: "row", gap: 8, w: "fill" }, tile("CPU", "18%", "load 1.82 · 2.10 · 2.04", "lucide:cpu", D.running) + tile("Memory", "11.4 GB", "35% used · 4.1 GB swap", "lucide:memory-stick", D.purple)) +
  F("Cores", { flex: "col", gap: 5, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    T("PER CORE", { size: 8, weight: "bold", color: D.sec, letterSpacing: 0.6 }) +
    F("Grid", { flex: "row", gap: 4, w: "fill" },
      [14, 22, 8, 31, 18, 42, 12, 26, 9, 36].map((p) =>
        F("Core", { flex: "col", gap: 2, grow: 1 },
          T(`${p}%`, { size: 7, color: D.ter, textAlign: "center" }) +
          F("B", { w: "fill", h: 40, rounded: 3, bg: "#2A2A2A", overflow: "hidden" },
            R("Bar fill", { w: "fill", h: Math.round(40 * p / 100), y: 40 - Math.round(40 * p / 100), bg: p > 30 ? D.warn : D.running })))).join(""))) +
  sectionLabel("Top processes") +
  [["WindowServer", 12.4, "oliver"], ["OpenCode", 9.8, "oliver"], ["Xcode", 8.1, "oliver"], ["Simulator", 5.2, "oliver"]].map(([n, p, u]) =>
    F("Proc", { flex: "row", items: "center", gap: 7, p: 8, rounded: 8, bg: D.card, w: "fill" },
      T(n, { size: 9.5, color: D.text, w: 150 }), T(u, { size: 8, color: D.ter }), F("S", { grow: 1 }),
      T(`${p}%`, { size: 9, color: D.sec }), bar(p * 4, D.running, 4))).join(""),
);

const network = systemPanel("System · network",
  T("Network", { size: 20, weight: "bold", color: D.text }) +
  F("Card", { flex: "col", gap: 6, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    T("INTERFACES", { size: 8, weight: "bold", color: D.sec, letterSpacing: 0.6 }) +
    kv("en0 · Wi-Fi", "192.168.1.42 / fe80::1c2d") + kv("lo0 · loopback", "127.0.0.1") + kv("utun4 · Tailscale", "100.101.102.103")) +
  F("Card", { flex: "col", gap: 6, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    T("ROUTING & DNS", { size: 8, weight: "bold", color: D.sec, letterSpacing: 0.6 }) + kv("Gateway", "192.168.1.1") + kv("DNS", "1.1.1.1 · 8.8.8.8")) +
  sectionLabel("Listening TCP ports", T("6", { size: 9, color: D.sec })) +
  [["8787", "bun", "hub"], ["1420", "OpenPencil", "dev"], ["3000", "node", "website"], ["5432", "postgres", ""]].map(([p, proc, tag]) =>
    F("Port", { flex: "row", items: "center", gap: 7, p: 8, rounded: 8, bg: D.card, w: "fill" }, T(p, { size: 10, weight: "semibold", color: D.text, w: 60 }), T(proc, { size: 9, color: D.sec, w: "fill" }), tag ? chip(tag, D.accent) : "")).join(""),
);

const software = systemPanel("System · software",
  T("Software", { size: 20, weight: "bold", color: D.text }) +
  F("Card", { flex: "row", items: "center", gap: 8, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    I("lucide:package", 14, D.warn) + F("Body", { flex: "col", gap: 2, grow: 1 }, T("Homebrew 4.6.2", { size: 11, weight: "semibold", color: D.text }), T("/opt/homebrew · 412 formulae · 68 casks", { size: 9, color: D.sec })) + chip("12 outdated", D.warn)) +
  sectionLabel("Developer runtimes") +
  [["Node", "24.10.0", "lucide:hexagon"], ["Bun", "1.3.1", "lucide:zap"], ["Swift", "6.1", "lucide:code"], ["Rust", "1.89.0", "lucide:settings"], ["Docker", "27.4", "lucide:container"], ["Go", "1.24", "lucide:code"]].map(([n, v, icon]) =>
    F("Runtime", { flex: "row", items: "center", gap: 7, p: 8, rounded: 8, bg: D.card, w: "fill" }, I(icon, 11, D.sec) + T(n, { size: 9.5, color: D.text, w: "fill" }) + T(v, { size: 9, color: D.sec }))).join("") +
  sectionLabel("Installed apps", T("238", { size: 9, color: D.sec })) +
  [["Xcode", "26.0", "com.apple.dt.Xcode"], ["OpenPencil", "0.16.0", "net.dannote.open-pencil"], ["Figma", "124.6", "com.figma.Desktop"]].map(([n, v, b]) =>
    F("App", { flex: "row", items: "center", gap: 7, p: 8, rounded: 8, bg: D.card, w: "fill" }, F("I", { w: 22, h: 22, rounded: 5, bg: "#3A3A3A", items: "center", justify: "center" }, T(n.slice(0, 1), { size: 9, weight: "bold", color: D.text })) + F("B", { flex: "col", gap: 1, grow: 1 }, T(n, { size: 9.5, color: D.text }), T(b, { size: 8, color: D.ter })) + T(v, { size: 9, color: D.sec }))).join(""),
);

const nowPlaying = systemPanel("System · now playing",
  F("Art", { w: "fill", h: 220, rounded: 14, bg: "#25304A", items: "center", justify: "center" }, I("lucide:disc-3", 64, "#8FA6D8")) +
  T("Starry Night", { size: 20, weight: "bold", color: D.text, textAlign: "center", w: "fill" }) +
  T("Don McLean · American Pie", { size: 11, color: D.sec, textAlign: "center", w: "fill" }) +
  F("Progress", { flex: "col", gap: 4, w: "fill" }, F("B", { w: "fill", h: 4, rounded: 2, bg: "#3A3A3A", overflow: "hidden" }, F("F", { w: "62%", h: 4, rounded: 2, bg: D.accent })) + F("T", { flex: "row", justify: "between", w: "fill" }, T("3:12", { size: 8, color: D.ter }), T("8:33", { size: 8, color: D.ter }))) +
  F("Controls", { flex: "row", items: "center", justify: "center", gap: 18, w: "fill", py: 8 },
    I("lucide:shuffle", 14, D.sec) + I("lucide:skip-back", 18, D.text) + F("Play", { w: 44, h: 44, rounded: 22, bg: D.accent, items: "center", justify: "center" }, I("lucide:pause", 18, "#062017")) + I("lucide:skip-forward", 18, D.text) + I("lucide:repeat", 14, D.sec)) +
  F("Volume", { flex: "row", items: "center", gap: 8, w: "fill" }, I("lucide:volume-2", 12, D.sec) + bar(64, D.sec, 4) + T("64%", { size: 9, color: D.sec })) +
  T("macOS MediaRemote covers Music, Spotify and browsers; assertions catch apps that play without metadata.", { size: 9, color: D.ter, lineHeight: 13, w: "fill" }),
);

const terminals = systemPanel("System · terminals",
  F("H", { flex: "row", items: "center", justify: "between", w: "fill" }, T("Terminals", { size: 18, weight: "bold", color: D.text }) + F("New", { flex: "row", items: "center", gap: 3, px: 7, py: 3, rounded: 99, bg: D.accent + "22" }, I("lucide:plus", 9, D.accent) + T("New shell", { size: 9, weight: "bold", color: D.accent }))) +
  [["zsh · ai-tools", "~/Developer/ai-tools", "running", "lucide:terminal", D.accent], ["zsh · stuttgart", "~/Developer/stuttgart-uni-assistant", "running", "lucide:terminal", D.accent], ["bash · build", "~/Developer/ai-tools", "exited", "lucide:terminal", D.sec], ["Terminal.app · Tab 3", "~/Desktop", "mirror", "lucide:app-window", D.purple]].map(([n, p, s, icon, c]) =>
    F("Term", { flex: "row", items: "center", gap: 8, p: 9, rounded: 9, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("Icon", { w: 26, h: 26, rounded: 7, bg: c + "18", items: "center", justify: "center" }, I(icon, 12, c)) +
      F("Body", { flex: "col", gap: 2, grow: 1 }, T(n, { size: 10, weight: "semibold", color: D.text }), T(p, { size: 8, color: D.sec })) + chip(s, c))).join("") +
  T("The hub proxies the PTY socket, so the same terminals work from the phone over LAN or a tunnel.", { size: 9, color: D.ter, lineHeight: 13, w: "fill" }),
);

const terminal = F("Terminal window", { flex: "col", w: 900, h: 620, bg: "#0F0F0F", rounded: 12, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
  F("Bar", { flex: "row", items: "center", gap: 6, w: "fill", px: 12, py: 8, bg: "#1B1B1B", stroke: "#FFFFFF0E", strokeWidth: 1 },
    F("Dots", { flex: "row", gap: 4 }, F("R", { w: 8, h: 8, rounded: 4, bg: "#F7666B" }) + F("Y", { w: 8, h: 8, rounded: 4, bg: "#F7B84B" }) + F("G", { w: 8, h: 8, rounded: 4, bg: "#4DD9A0" })) +
    T("zsh — ai-tools — 120×32", { size: 9, color: D.sec, w: "fill", textAlign: "center" }) + chip("running", D.accent)) +
  F("Screen", { flex: "col", gap: 3, p: 14, w: "fill", grow: 1 },
    T("Last login: Tue Oct 27 20:31:02 on ttys003", { size: 10, color: "#8A8A8A" }) +
    T("~/Developer/ai-tools % make hub", { size: 10, color: "#D0D0D0" }) +
    T("bun run server/src/index.ts", { size: 10, color: "#8A8A8A" }) +
    T("hub 0.16.0 listening on http://127.0.0.1:8787", { size: 10, color: D.accent }) +
    T("paired: 3 clients · opencode connected", { size: 10, color: D.accent }) +
    T("~/Developer/ai-tools % git status", { size: 10, color: "#D0D0D0" }) +
    T("On branch main", { size: 10, color: "#8A8A8A" }) +
    T("Changes not staged for commit:", { size: 10, color: "#D0D0D0" }) +
    T("  modified: design/OpenCodeBar.fig", { size: 10, color: D.warn }) +
    T("~/Developer/ai-tools % ▊", { size: 10, color: "#D0D0D0" })),
);

const files = systemPanel("System · files",
  F("H", { flex: "row", items: "center", justify: "between", w: "fill" }, T("Files", { size: 18, weight: "bold", color: D.text }) + chip("read-only", D.sec)) +
  F("Crumbs", { flex: "row", items: "center", gap: 4, w: "fill" }, I("lucide:home", 10, D.sec) + T("~", { size: 9, color: D.accent }) + T("/", { size: 9, color: D.ter }) + T("Developer", { size: 9, color: D.accent }) + T("/", { size: 9, color: D.ter }) + T("ai-tools", { size: 9, color: D.text }) + F("S", { grow: 1 }) + I("lucide:eye-off", 11, D.sec)) +
  [["..", "folder", ""], ["design/", "folder", ""], ["docs/", "folder", ""], ["server/", "folder", ""], ["Sources/", "folder", ""], ["Makefile", "file", "8.4 KB"], ["README.md", "file", "64 KB"], ["package.json", "file", "1.2 KB"]].map(([n, k, s]) =>
    F("Row", { flex: "row", items: "center", gap: 7, p: 7, rounded: 7, bg: D.card, w: "fill" }, I(k === "folder" ? "lucide:folder" : "lucide:file-text", 11, k === "folder" ? D.warn : D.sec) + T(n, { size: 9.5, color: D.text, w: "fill" }) + T(s, { size: 8, color: D.ter }))).join("") +
  T("Text and images open in a read-only preview; nothing can be edited or deleted from here.", { size: 9, color: D.ter, lineHeight: 13, w: "fill" }),
);

const vmList = vmPanel("VMs · populated",
  F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, T("Virtual machines", { size: 18, weight: "bold", color: D.text }) + F("S", { grow: 1 }) + chip("1 running", D.running) + iconButton("lucide:plus", D.accent, 12)) +
  [["nixos-dev", "running", "192.168.64.12", "2 CPU · 4 GB · 20 GB", D.accent, "Stop"],
   ["nixos-build", "stopped", "—", "4 CPU · 8 GB · 40 GB", D.sec, "Start"],
   ["nixos-lab", "paused", "192.168.64.18", "2 CPU · 4 GB · 20 GB", D.warn, "Resume"]].map(([n, s, ip, spec, c, action]) =>
    F("VM", { flex: "col", gap: 6, p: 10, rounded: 11, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("H", { flex: "row", items: "center", gap: 7, w: "fill" },
        F("Icon", { w: 28, h: 28, rounded: 8, bg: c + "1A", items: "center", justify: "center" }, I("lucide:server", 13, c)) +
        F("Body", { flex: "col", gap: 1, grow: 1 }, T(n, { size: 11, weight: "bold", color: D.text }), T(`NixOS · ${s} · ${ip}`, { size: 8, color: D.sec })) + chip(action, c)) +
      F("Meta", { flex: "row", items: "center", gap: 8, w: "fill" }, T(spec, { size: 8, color: D.ter }), F("S", { grow: 1 }), T("2 changes pending", { size: 8, color: D.warn })))).join("") +
  F("Setup", { flex: "row", items: "center", gap: 7, p: 9, rounded: 9, bg: D.accent + "0E", stroke: D.accent + "2A", strokeWidth: 1, w: "fill" },
    I("lucide:check-circle", 11, D.accent) + T("Helper signed · Nix installed · aarch64-linux builder ready", { size: 9, color: "#B7D8CA", w: "fill" }) + chip("Setup logs", D.sec)) +
  T("Storage: ~/.local/share/opencodebar/vms · Updated just now", { size: 8, color: D.ter, w: "fill" }),
);

const vmEmpty = vmPanel("VMs · empty",
  F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, T("Virtual machines", { size: 18, weight: "bold", color: D.text }) + F("S", { grow: 1 }) + iconButton("lucide:plus", D.accent, 12)) +
  emptyState("lucide:server", "No virtual machines", "Create a NixOS guest. The hub builds a raw EFI image, runs it with Virtualization.framework, and applies package changes over SSH.", { h: 300 }) +
  F("Build", { flex: "row", items: "center", justify: "center", gap: 5, py: 8, rounded: 9, bg: D.accent, w: "fill" }, I("lucide:wand-sparkles", 11, "#062017") + T("Build a NixOS machine", { size: 11, weight: "bold", color: "#062017" })),
);

const vmUnavailable = vmPanel("VMs · unavailable",
  F("H", { flex: "row", items: "center", gap: 6, w: "fill" }, T("Virtual machines", { size: 18, weight: "bold", color: D.text }) + F("S", { grow: 1 }) + chip("not ready", D.warn)) +
  F("Setup card", { flex: "col", gap: 8, p: 12, rounded: 12, bg: D.warn + "0C", stroke: D.warn + "2E", strokeWidth: 1, w: "fill" },
    F("H", { flex: "row", items: "center", gap: 6 }, I("lucide:triangle-alert", 12, D.warn) + T("Virtual machines are not available yet", { size: 12, weight: "bold", color: D.warn })) +
    T("The VZ helper is not signed with com.apple.security.virtualization, or Nix is missing from the hub's PATH.", { size: 9.5, color: "#D8C4A8", lineHeight: 14, w: "fill" }) +
    F("Checks", { flex: "col", gap: 4, w: "fill" },
      F("C1", { flex: "row", items: "center", gap: 6 }, I("lucide:circle-x", 10, D.danger) + T("Helper entitlement", { size: 9, color: D.text }) + F("S", { grow: 1 }) + chip("missing", D.danger)) +
      F("C2", { flex: "row", items: "center", gap: 6 }, I("lucide:circle-check", 10, D.accent) + T("Nix installed", { size: 9, color: D.text }) + F("S", { grow: 1 }) + chip("ok", D.accent)) +
      F("C3", { flex: "row", items: "center", gap: 6 }, I("lucide:circle-x", 10, D.danger) + T("aarch64-linux builder", { size: 9, color: D.text }) + F("S", { grow: 1 }) + chip("missing", D.danger))) +
    F("Cmd", { flex: "col", gap: 3, p: 8, rounded: 7, bg: "#0F0F0F", w: "fill" }, T("make vz-helper", { size: 9, color: D.output }), T("nix build .#packages.aarch64-linux.default", { size: 9, color: D.output })) +
    F("Run", { flex: "row", items: "center", justify: "center", gap: 5, py: 7, rounded: 8, bg: D.accent }, I("lucide:play", 10, "#062017") + T("Run setup", { size: 10, weight: "bold", color: "#062017" }))),
);

const vmDetail = F("VM detail", { flex: "col", gap: 10, w: 800, h: 1200, bg: D.panel, rounded: 20, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
  F("Top", { flex: "row", items: "center", gap: 8, w: "fill", px: 20, py: 12 }, I("lucide:chevron-left", 12, D.accent) + T("VMs", { size: 11, color: D.accent }) + F("S", { grow: 1 }) + chip("running", D.accent) + iconButton("lucide:more-horizontal", D.sec, 12)) +
  F("Head", { flex: "row", items: "center", gap: 9, p: 12, w: "fill", rounded: 14, bg: D.card, stroke: D.border, strokeWidth: 1 },
    F("Icon", { w: 42, h: 42, rounded: 10, bg: D.accent + "1A", items: "center", justify: "center" }, I("lucide:server", 20, D.accent)) +
    F("Body", { flex: "col", gap: 3, grow: 1 }, T("nixos-dev", { size: 18, weight: "bold", color: D.text }), T("NixOS 26.05 · 192.168.64.12 · up 2h 14m", { size: 9, color: D.sec }), F("Meta", { flex: "row", gap: 5 }, chip("2 CPU", D.sec) + chip("4 GB", D.sec) + chip("20 GB", D.sec))) +
    iconButton("lucide:terminal", D.sec, 12)) +
  F("Tabs", { flex: "row", gap: 2, p: 3, w: "fill", rounded: 10, bg: "#262626" },
    ["Overview", "Console", "Packages", "Logs"].map((l) => F("Tab", { flex: "row", items: "center", justify: "center", grow: 1, py: 6, rounded: 8, bg: l === "Overview" ? "#404040" : "#FFFFFF00" }, T(l, { size: 10, weight: l === "Overview" ? "semibold" : "regular", color: l === "Overview" ? D.text : D.sec }))).join("")) +
  F("Body", { flex: "col", gap: 10, px: 20, py: 6, grow: 1, w: "fill" },
    F("Tiles", { flex: "row", gap: 8, w: "fill" }, tile("CPU", "12%", "guest load 0.42", "lucide:cpu", D.running) + tile("Memory", "1.8 GB", "of 4 GB", "lucide:memory-stick", D.purple)) +
    F("Tiles2", { flex: "row", gap: 8, w: "fill" }, tile("Disk", "6.2 GB", "of 20 GB", "lucide:hard-drive", D.warn) + tile("Uptime", "2h 14m", "generation 42", "lucide:clock", D.accent)) +
    F("Card", { flex: "col", gap: 5, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      T("GUEST", { size: 8, weight: "bold", color: D.sec, letterSpacing: 0.6 }) + kv("Hostname", "nixos-dev") + kv("Kernel", "6.12.4") + kv("SSH", "ssh opencodebar@192.168.64.12") + kv("Generation", "42 (current)")) +
    F("Actions", { flex: "row", gap: 6, w: "fill" },
      F("A", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 7, rounded: 8, bg: D.warn + "18", stroke: D.warn + "2E", strokeWidth: 1 }, I("lucide:pause", 10, D.warn) + T("Pause", { size: 10, color: D.warn })) +
      F("B", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 7, rounded: 8, bg: "#FFFFFF0A" }, I("lucide:rotate-ccw", 10, D.sec) + T("Restart", { size: 10, color: D.sec })) +
      F("C", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 7, rounded: 8, bg: D.danger + "14", stroke: D.danger + "2E", strokeWidth: 1 }, I("lucide:square", 9, D.danger) + T("Stop", { size: 10, color: D.danger }))) +
    F("Config", { flex: "col", gap: 4, p: 10, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
      F("H", { flex: "row", items: "center", gap: 5 }, I("lucide:file-cog", 10, D.sec) + T("CONFIGURATION", { size: 8, weight: "bold", color: D.sec })) +
      T("services.openssh.enable = true;\nusers.users.opencodebar = { isNormalUser = true; extraGroups = [ \"wheel\" ]; };\nnetworking.firewall.allowedTCPPorts = [ 22 8080 ];", { size: 8.5, color: "#C9D1D9", lineHeight: 13, w: "fill" })),
  ),
);

const vmConsole = F("VM console", { flex: "col", gap: 8, w: 900, h: 620, bg: "#0E0E0E", rounded: 12, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
  F("Bar", { flex: "row", items: "center", gap: 6, w: "fill", px: 12, py: 8, bg: "#1B1B1B", stroke: "#FFFFFF0E", strokeWidth: 1 }, I("lucide:terminal", 11, D.accent) + T("nixos-dev · hvc0", { size: 9, color: D.sec, w: "fill" }) + chip("live", D.accent)) +
  F("Log", { flex: "col", gap: 2, p: 12, w: "fill", grow: 1 },
    T("[    0.000000] Booting Linux on physical CPU 0x0", { size: 9, color: "#8A8A8A" }) +
    T("[    0.000000] Linux version 6.12.4 (nixbld@localhost)", { size: 9, color: "#8A8A8A" }) +
    T("[    0.412000] virtio_blk virtio1: [vda] 41943040 512-byte sectors", { size: 9, color: "#8A8A8A" }) +
    T("[    1.208000] systemd[1]: Reached target Local File Systems.", { size: 9, color: "#D0D0D0" }) +
    T("[    2.114000] systemd[1]: Started SSH Daemon.", { size: 9, color: D.accent }) +
    T("nixos-dev login: opencodebar", { size: 9, color: "#D0D0D0" }) +
    T("Last login: Tue Oct 27 18:20:14 from 192.168.64.1", { size: 9, color: "#8A8A8A" }) +
    T("[opencodebar@nixos-dev:~]$ nixos-rebuild switch --flake .#nixos-dev", { size: 9, color: "#D0D0D0" }) +
    T("building the system configuration...", { size: 9, color: D.warn }) +
    T("activation script finished successfully", { size: 9, color: D.accent }) +
    T("[opencodebar@nixos-dev:~]$ ▊", { size: 9, color: "#D0D0D0" })),
);

const builder = F("VM builder", { flex: "col", gap: 10, w: 900, h: 760, p: 18, rounded: 18, bg: D.panel, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
  F("Head", { flex: "row", items: "start", justify: "between", w: "fill" },
    F("T", { flex: "col", gap: 3 }, T("Build a NixOS machine", { size: 20, weight: "bold", color: D.text }), T("Click together users, apps and infrastructure. The hub renders configuration.nix and builds the image.", { size: 9.5, color: D.sec, w: 560, lineHeight: 14 })) + iconButton("lucide:x", D.sec, 12)) +
  F("Presets", { flex: "row", gap: 5, w: "fill" }, chip("Minimal", D.accent) + chip("Development", D.sec) + chip("Desktop", D.sec) + chip("Server", D.sec) + chip("AI", D.sec)) +
  F("Steps", { flex: "row", gap: 5, w: "fill" },
    ["1 · Options", "2 · Users", "3 · Network", "4 · Review"].map((l, i) => F("Step", { flex: "row", items: "center", justify: "center", gap: 4, grow: 1, py: 6, rounded: 8, bg: i === 0 ? D.accent + "1A" : "#FFFFFF06" }, T(l, { size: 9, weight: i === 0 ? "semibold" : "regular", color: i === 0 ? D.accent : D.sec }))).join("")) +
  F("Content", { flex: "row", gap: 10, w: "fill", grow: 1 },
    F("Catalog", { flex: "col", gap: 6, w: 360, h: "fill" },
      F("Search", { flex: "row", items: "center", gap: 6, px: 8, py: 6, rounded: 8, bg: D.field }, I("lucide:search", 10, D.sec) + T("Search options", { size: 9, color: D.ter, w: "fill" })) +
      ["System", "Desktop", "Development", "Containers", "Services", "Networking", "Media", "AI", "Monitoring", "Security"].map((c, i) =>
        F("Cat", { flex: "row", items: "center", gap: 6, p: 6, rounded: 6, bg: i === 2 ? "#FFFFFF0C" : "#FFFFFF00", w: "fill" }, I("lucide:chevron-right", 9, D.sec) + T(c, { size: 9, color: i === 2 ? D.text : D.sec }) + F("S", { grow: 1 }) + T(String([12, 8, 21, 6, 34, 9, 7, 5, 4, 11][i]), { size: 8, color: D.ter }))).join("")) +
    F("Options", { flex: "col", gap: 6, w: "fill", h: "fill" },
      T("DEVELOPMENT", { size: 8, weight: "bold", color: D.sec, letterSpacing: 0.6 }) +
      [["git", true, "Version control"], ["neovim", true, "Editor"], ["nodejs_24", true, "Node.js runtime"], ["bun", true, "Bun runtime"], ["python3", false, "Python"], ["rustc", false, "Rust toolchain"], ["docker", false, "Containers"]].map(([n, on, d]) =>
        F("Opt", { flex: "row", items: "center", gap: 7, p: 7, rounded: 7, bg: on ? D.accent + "0C" : D.card, stroke: on ? D.accent + "2A" : D.border, strokeWidth: 1, w: "fill" },
          F("Box", { w: 13, h: 13, rounded: 3, bg: on ? D.accent : "#00000000", stroke: on ? "#00000000" : D.ter, strokeWidth: 1, items: "center", justify: "center" }, on ? I("lucide:check", 9, "#062017") : "") +
          F("B", { flex: "col", gap: 1, grow: 1 }, T(n, { size: 9.5, weight: "semibold", color: D.text }), T(d, { size: 8, color: D.ter })))).join("")) +
    F("Plan", { flex: "col", gap: 6, w: 300, h: "fill", p: 10, rounded: 10, bg: "#101010", stroke: D.border, strokeWidth: 1 },
      F("H", { flex: "row", items: "center", gap: 5 }, I("lucide:file-code", 10, D.output) + T("configuration.nix", { size: 9, weight: "bold", color: D.text }) + F("S", { grow: 1 }) + chip("live", D.accent)) +
      T("{ config, pkgs, ... }:\n{\n  services.openssh.enable = true;\n  environment.systemPackages = with pkgs; [\n    git neovim nodejs_24 bun\n  ];\n  users.users.opencodebar = {\n    isNormalUser = true;\n    extraGroups = [ \"wheel\" ];\n  };\n}", { size: 8, color: "#C9D1D9", lineHeight: 12, w: "fill" }))) +
  F("Footer", { flex: "row", gap: 6, w: "fill" }, F("S", { grow: 1 }) + F("Cancel", { px: 10, py: 6, rounded: 8, bg: "#FFFFFF0A" }, T("Cancel", { size: 10, color: D.sec })) + F("Build", { flex: "row", items: "center", gap: 4, px: 12, py: 6, rounded: 8, bg: D.accent }, I("lucide:hammer", 10, "#062017") + T("Build machine", { size: 10, weight: "bold", color: "#062017" }))),
);

export default function () {
  const title = "macOS — system and virtual machines";
  const subtitle = "The hub's machine inventory, performance, media, terminals and files, plus the NixOS guest lifecycle: build, boot, console, rebuild and delete.";
  const meta = "Sources: SystemTab.swift · SystemAppDetailView.swift · PerformanceViews.swift · TerminalViews.swift · SystemFileBrowser.swift · VirtualMachinesTab.swift · VirtualMachineDetailView.swift · NewVirtualMachineSheet.swift · NixOSBuilderView.swift";
  return {
    flat: true,
    sections: [
      R("Page background", { x: 0, y: 0, w: 3000, h: 8526, bg: "#E9ECEF" }),
      F("Header position", { x: 72, y: 72, w: 2856, h: "hug" }, pageHeader({ title, subtitle, meta })),
      group("System dashboard", "Vitals double as navigation; Now Playing and the More grid keep the panel short.", [
        F("Col", { flex: "col", gap: 10 }, T("System · dashboard", { size: 13, weight: "semibold", color: "#2B3038" }), system),
        F("Col", { flex: "col", gap: 10 }, T("Performance", { size: 13, weight: "semibold", color: "#2B3038" }), performance),
        F("Col", { flex: "col", gap: 10 }, T("Network", { size: 13, weight: "semibold", color: "#2B3038" }), network),
      ].join(""), { x: 72, y: 249, w: 2856 }),
      group("Software and media", "Everything on the hub host is readable without leaving the app.", [
        F("Col", { flex: "col", gap: 10 }, T("Software", { size: 13, weight: "semibold", color: "#2B3038" }), software),
        F("Col", { flex: "col", gap: 10 }, T("Now playing", { size: 13, weight: "semibold", color: "#2B3038" }), nowPlaying),
      ].join(""), { x: 72, y: 1572, w: 2856 }),
      group("Terminals and files", "OpenCode PTYs and Terminal.app mirrors, plus the read-only host browser.", [
        F("Col", { flex: "col", gap: 10 }, T("Terminals", { size: 13, weight: "semibold", color: "#2B3038" }), terminals),
        F("Col", { flex: "col", gap: 10 }, T("Files", { size: 13, weight: "semibold", color: "#2B3038" }), files),
      ].join(""), { x: 72, y: 2895, w: 2856 }),
      group("Terminal emulator", "A real PTY, proxied by the hub; Terminal.app tabs get a line-based mirror instead.", [
        F("Col", { flex: "col", gap: 10 }, T("Terminal · zsh", { size: 13, weight: "semibold", color: "#2B3038" }), terminal),
      ].join(""), { x: 72, y: 4218, w: 2856 }),
      group("Virtual machines · list states", "Populated, empty and not-ready states.", [
        F("Col", { flex: "col", gap: 10 }, T("VMs · populated", { size: 13, weight: "semibold", color: "#2B3038" }), vmList),
        F("Col", { flex: "col", gap: 10 }, T("VMs · empty", { size: 13, weight: "semibold", color: "#2B3038" }), vmEmpty),
        F("Col", { flex: "col", gap: 10 }, T("VMs · not available", { size: 13, weight: "semibold", color: "#2B3038" }), vmUnavailable),
      ].join(""), { x: 72, y: 4961, w: 2856 }),
      group("Virtual machine detail", "Live metrics, SSH facts, lifecycle actions and the declarative configuration.", [
        F("Col", { flex: "col", gap: 10 }, T("VM · overview", { size: 13, weight: "semibold", color: "#2B3038" }), vmDetail),
      ].join(""), { x: 72, y: 6284, w: 2856 }),
      group("Console and builder", "The serial console recovers a guest before SSH; the builder previews the real configuration.nix.", [
        F("Col", { flex: "col", gap: 10 }, T("VM · serial console", { size: 13, weight: "semibold", color: "#2B3038" }), vmConsole),
        F("Col", { flex: "col", gap: 10 }, T("VM · builder", { size: 13, weight: "semibold", color: "#2B3038" }), builder),
      ].join(""), { x: 72, y: 7607, w: 2856 }),
    ],
  };
}
