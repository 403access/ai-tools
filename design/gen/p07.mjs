import { D, F, R, T, I, chip, card, sectionLabel, pageParts, pageHeader, group, bar, notice, emptyState, phone, iconButton } from "./kit.mjs";

const dot = (c = D.accent) => F("Dot", { w: 7, h: 7, rounded: 4, bg: c });

const host = (name, children, title = "Host", sub = "") =>
  phone({ title, sub, active: "Host", name, children: Array.isArray(children) ? children.join("") : children });

const hostDash = host("iOS · Host dashboard", [
  F("Machine", { flex: "row", items: "center", gap: 8, p: 9, rounded: 10, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" },
    F("Icon", { w: 32, h: 32, rounded: 8, bg: D.accent + "1A", items: "center", justify: "center" }, I("lucide:laptop", 15, D.accent)) +
    F("B", { flex: "col", gap: 1, grow: 1 }, T("Oliver’s MacBook Pro", { size: 11, weight: "bold", color: D.text }), T("macOS 26.0 · arm64 · up 3d 14h", { size: 8, color: D.sec })) + chip("hub 0.16.0", D.sec)),
  F("Vitals", { flex: "row", gap: 6, w: "fill" },
    F("V", { flex: "col", gap: 2, p: 8, rounded: 9, bg: D.card, grow: 1 }, F("H", { flex: "row", gap: 4 }, I("lucide:cpu", 9, D.running) + T("CPU", { size: 7, weight: "bold", color: D.sec })), T("18%", { size: 16, weight: "bold", color: D.text }), T("10 cores", { size: 7, color: D.ter })) +
    F("V", { flex: "col", gap: 2, p: 8, rounded: 9, bg: D.card, grow: 1 }, F("H", { flex: "row", gap: 4 }, I("lucide:memory-stick", 9, D.purple) + T("MEMORY", { size: 7, weight: "bold", color: D.sec })), T("11.4", { size: 16, weight: "bold", color: D.text }), T("of 32 GB", { size: 7, color: D.ter }))),
  F("Vitals2", { flex: "row", gap: 6, w: "fill" },
    F("V", { flex: "col", gap: 2, p: 8, rounded: 9, bg: D.card, grow: 1 }, F("H", { flex: "row", gap: 4 }, I("lucide:hard-drive", 9, D.warn) + T("STORAGE", { size: 7, weight: "bold", color: D.sec })), T("412 GB", { size: 16, weight: "bold", color: D.text }), T("free of 1 TB", { size: 7, color: D.ter })) +
    F("V", { flex: "col", gap: 2, p: 8, rounded: 9, bg: D.card, grow: 1 }, F("H", { flex: "row", gap: 4 }, I("lucide:battery-charging", 9, D.accent) + T("BATTERY", { size: 7, weight: "bold", color: D.sec })), T("86%", { size: 16, weight: "bold", color: D.text }), T("charging", { size: 7, color: D.ter }))),
  sectionLabel("Now playing", chip("Music", D.sec)) +
  F("Media", { flex: "row", items: "center", gap: 7, p: 8, rounded: 9, bg: D.card },
    F("Art", { w: 32, h: 32, rounded: 6, bg: "#3B4A6B", items: "center", justify: "center" }, I("lucide:music", 13, "#FFFFFF")) +
    F("B", { flex: "col", gap: 1, grow: 1 }, T("Starry Night", { size: 9, weight: "semibold", color: D.text }), T("Don McLean · American Pie", { size: 7, color: D.sec })) +
    I("lucide:play", 12, D.accent)) +
  sectionLabel("More", chip("4 sections", D.sec)) +
  F("More", { flex: "row", gap: 6, w: "fill" },
    ["Network", "Software", "Terminals", "Files"].map((l) => F("M", { flex: "col", items: "center", gap: 3, p: 8, rounded: 8, bg: D.card, grow: 1 }, I(["lucide:network", "lucide:package", "lucide:terminal", "lucide:folder-open"][["Network", "Software", "Terminals", "Files"].indexOf(l)], 13, D.sec), T(l, { size: 7, color: D.sec }))).join("")),
]);

const performance = host("iOS · Performance", [
  F("H", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:chevron-left", 11, D.accent) + T("Host", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("live", D.running)),
  T("Performance", { size: 18, weight: "bold", color: D.text }),
  F("Tiles", { flex: "row", gap: 6, w: "fill" },
    F("T", { flex: "col", gap: 2, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("CPU", { size: 7, weight: "bold", color: D.sec }), T("18%", { size: 18, weight: "bold", color: D.text }), T("load 1.82", { size: 7, color: D.ter })) +
    F("T", { flex: "col", gap: 2, p: 8, rounded: 8, bg: D.card, grow: 1 }, T("MEMORY", { size: 7, weight: "bold", color: D.sec }), T("11.4 GB", { size: 18, weight: "bold", color: D.text }), T("35% used", { size: 7, color: D.ter }))),
  F("Cores", { flex: "col", gap: 4, p: 8, rounded: 8, bg: D.card, w: "fill" }, T("PER CORE", { size: 7, weight: "bold", color: D.sec }),
    F("G", { flex: "row", gap: 3, w: "fill" },
      [14, 22, 8, 31, 18, 42, 12, 26, 9, 36].map((p) =>
        F("C", { flex: "col", gap: 1, grow: 1 },
          T(`${p}`, { size: 6, color: D.ter, textAlign: "center" }) +
          F("B", { w: "fill", h: 28, rounded: 2, bg: "#2A2A2A", overflow: "hidden" },
            R("Bar fill", { w: "fill", h: Math.round(28 * p / 100), y: 28 - Math.round(28 * p / 100), bg: p > 30 ? D.warn : D.running })))).join(""))),
  sectionLabel("Top processes"),
  [["WindowServer", "12.4%"], ["OpenCode", "9.8%"], ["Xcode", "8.1%"]].map(([n, p]) => F("P", { flex: "row", items: "center", gap: 6, p: 7, rounded: 7, bg: D.card }, T(n, { size: 9, color: D.text, w: "fill" }), T(p, { size: 8, color: D.sec }))).join(""),
]);

const storage = host("iOS · Storage", [
  F("H", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:chevron-left", 11, D.accent) + T("Host", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("3 volumes", D.sec)),
  T("Storage", { size: 18, weight: "bold", color: D.text }),
  F("Card", { flex: "col", gap: 5, p: 9, rounded: 9, bg: D.card, w: "fill" },
    F("H", { flex: "row", justify: "between", w: "fill" }, T("Macintosh HD", { size: 10, weight: "semibold", color: D.text }), T("412 GB free", { size: 8, color: D.sec })) +
    bar(59, D.warn, 5) + T("588 GB of 1 TB · APFS", { size: 7, color: D.ter })) +
  F("Card", { flex: "col", gap: 5, p: 9, rounded: 9, bg: D.card, w: "fill" },
    F("H", { flex: "row", justify: "between", w: "fill" }, T("OpenCodeBar VM images", { size: 10, weight: "semibold", color: D.text }), T("64 GB", { size: 8, color: D.sec })) +
    bar(18, D.accent, 5) + T("3 guests · raw EFI disks", { size: 7, color: D.ter })),
  sectionLabel("Largest folders"),
  [["~/Library/Developer/Xcode", "82 GB"], ["~/Developer", "41 GB"], ["~/.local/share/opencodebar", "6.4 GB"]].map(([n, v]) => F("F", { flex: "row", items: "center", gap: 5, p: 7, rounded: 7, bg: D.card }, I("lucide:folder", 9, D.warn) + T(n, { size: 8, color: D.text, w: "fill" }) + T(v, { size: 8, color: D.sec }))).join(""),
]);

const network = host("iOS · Network", [
  F("H", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:chevron-left", 11, D.accent) + T("Host", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("6 ports", D.sec)),
  T("Network", { size: 18, weight: "bold", color: D.text }),
  F("Card", { flex: "col", gap: 4, p: 9, rounded: 9, bg: D.card, w: "fill" }, T("INTERFACES", { size: 7, weight: "bold", color: D.sec }),
    T("en0 · Wi-Fi · 192.168.1.42", { size: 8, color: D.text }), T("lo0 · 127.0.0.1", { size: 8, color: D.text }), T("utun4 · Tailscale · 100.101.102.103", { size: 8, color: D.text })) +
  F("Card", { flex: "col", gap: 4, p: 9, rounded: 9, bg: D.card, w: "fill" }, T("LISTENING", { size: 7, weight: "bold", color: D.sec }),
    T("8787 · bun · hub", { size: 8, color: D.text }), T("1420 · OpenPencil", { size: 8, color: D.text }), T("3000 · node · website", { size: 8, color: D.text })) +
  T("Default gateway 192.168.1.1 · DNS 1.1.1.1, 8.8.8.8", { size: 7, color: D.ter }),
]);

const software = host("iOS · Software", [
  F("H", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:chevron-left", 11, D.accent) + T("Host", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("238 apps", D.sec)),
  T("Software", { size: 18, weight: "bold", color: D.text }),
  F("Brew", { flex: "row", items: "center", gap: 6, p: 9, rounded: 9, bg: D.card }, I("lucide:package", 12, D.warn) + F("B", { flex: "col", gap: 1, grow: 1 }, T("Homebrew 4.6.2", { size: 9, weight: "semibold", color: D.text }), T("412 formulae · 68 casks", { size: 7, color: D.sec })) + chip("12 outdated", D.warn)),
  sectionLabel("Runtimes"),
  [["Node", "24.10.0"], ["Bun", "1.3.1"], ["Swift", "6.1"], ["Rust", "1.89.0"], ["Docker", "27.4"], ["Go", "1.24"]].map(([n, v]) => F("R", { flex: "row", items: "center", gap: 5, p: 7, rounded: 7, bg: D.card }, I("lucide:code", 9, D.sec) + T(n, { size: 8, color: D.text, w: "fill" }) + T(v, { size: 8, color: D.sec }))).join(""),
  sectionLabel("Apps"),
  [["Xcode", "26.0"], ["OpenPencil", "0.16.0"], ["Figma", "124.6"]].map(([n, v]) => F("A", { flex: "row", items: "center", gap: 5, p: 7, rounded: 7, bg: D.card }, F("I", { w: 18, h: 18, rounded: 4, bg: "#3A3A3A", items: "center", justify: "center" }, T(n.slice(0, 1), { size: 7, weight: "bold", color: D.text })) + T(n, { size: 8, color: D.text, w: "fill" }) + T(v, { size: 8, color: D.sec }))).join(""),
]);

const machine = host("iOS · Machine & health", [
  F("H", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:chevron-left", 11, D.accent) + T("Host", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("healthy", D.accent)),
  T("Machine", { size: 18, weight: "bold", color: D.text }),
  F("Card", { flex: "col", gap: 4, p: 9, rounded: 9, bg: D.card, w: "fill" },
    T("macOS 26.0 · Darwin 25.1.0", { size: 8, color: D.text }), T("MacBookPro18,3 · Apple M1 Pro", { size: 8, color: D.text }), T("10 cores (8P + 2E) · 32 GB", { size: 8, color: D.text }), T("Booted Oct 24, 06:12 · Europe/Berlin", { size: 8, color: D.text })) +
  F("Card", { flex: "col", gap: 4, p: 9, rounded: 9, bg: D.card, w: "fill" },
    T("SECURITY", { size: 7, weight: "bold", color: D.sec }),
    F("S1", { flex: "row", justify: "between", w: "fill" }, T("SIP", { size: 8, color: D.text }), chip("enabled", D.accent)) +
    F("S2", { flex: "row", justify: "between", w: "fill" }, T("FileVault", { size: 8, color: D.text }), chip("on", D.accent)) +
    F("S3", { flex: "row", justify: "between", w: "fill" }, T("Firewall", { size: 8, color: D.text }), chip("on", D.accent)) +
    F("S4", { flex: "row", justify: "between", w: "fill" }, T("Gatekeeper", { size: 8, color: D.text }), chip("on", D.accent))) +
  F("Card", { flex: "col", gap: 4, p: 9, rounded: 9, bg: D.card, w: "fill" },
    T("BATTERY", { size: 7, weight: "bold", color: D.sec }), T("86% · charging · 214 cycles", { size: 8, color: D.text }), T("Condition: normal · 31.2 °C", { size: 8, color: D.sec })),
]);

const terminals = host("iOS · Terminals", [
  F("H", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:chevron-left", 11, D.accent) + T("Host", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("New", D.accent)),
  T("Terminals", { size: 18, weight: "bold", color: D.text }),
  [["zsh · ai-tools", "~/Developer/ai-tools", "running", D.accent], ["zsh · stuttgart", "~/Developer/stuttgart-uni-assistant", "running", D.accent], ["bash · build", "~/Developer/ai-tools", "exited", D.sec], ["Terminal.app · Tab 3", "~/Desktop", "mirror", D.purple]].map(([n, p, s, c]) =>
    F("T", { flex: "row", items: "center", gap: 6, p: 8, rounded: 8, bg: D.card },
      F("I", { w: 24, h: 24, rounded: 6, bg: c + "18", items: "center", justify: "center" }, I("lucide:terminal", 10, c)) +
      F("B", { flex: "col", gap: 1, grow: 1 }, T(n, { size: 9, weight: "semibold", color: D.text }), T(p, { size: 7, color: D.sec })) + chip(s, c))).join(""),
]);

const files = host("iOS · Files", [
  F("H", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:chevron-left", 11, D.accent) + T("Host", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("read-only", D.sec)),
  T("Files", { size: 18, weight: "bold", color: D.text }),
  F("Crumbs", { flex: "row", items: "center", gap: 3, w: "fill" }, I("lucide:home", 9, D.sec) + T("~", { size: 8, color: D.accent }) + T("/", { size: 8, color: D.ter }) + T("Developer", { size: 8, color: D.accent }) + T("/", { size: 8, color: D.ter }) + T("ai-tools", { size: 8, color: D.text })),
  [["..", "folder"], ["design/", "folder"], ["docs/", "folder"], ["server/", "folder"], ["Sources/", "folder"], ["Makefile", "file"], ["README.md", "file"], ["package.json", "file"]].map(([n, k]) =>
    F("F", { flex: "row", items: "center", gap: 6, p: 7, rounded: 7, bg: D.card }, I(k === "folder" ? "lucide:folder" : "lucide:file-text", 10, k === "folder" ? D.warn : D.sec) + T(n, { size: 8, color: D.text, w: "fill" }))).join(""),
  T("Text and images open in a read-only preview.", { size: 7, color: D.ter }),
]);

const remote = F("iOS · Remote desktop", { flex: "col", gap: 8, w: 414, h: 896, bg: "#0C0C0C", rounded: 34, stroke: D.border, strokeWidth: 1, overflow: "hidden" },
  F("Top", { flex: "row", items: "center", gap: 6, w: "fill", px: 16, py: 10 }, I("lucide:chevron-left", 12, D.accent) + T("Host", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("System", D.sec) + chip("Remote", D.accent)),
  F("Screen", { flex: "col", w: "fill", grow: 1, m: 12, rounded: 10, bg: "#1B2433", overflow: "hidden" },
    F("Menu", { flex: "row", items: "center", gap: 6, w: "fill", px: 8, py: 4, bg: "#E8EBF0" }, I("lucide:apple", 7, "#1B1F24") + T("Finder", { size: 6, weight: "bold", color: "#1B1F24" }) + T("File", { size: 6, color: "#3C4450" }) + T("Edit", { size: 6, color: "#3C4450" }) + F("S", { grow: 1 }) + T("20:35", { size: 6, color: "#3C4450" })) +
    F("Desk", { flex: "row", gap: 8, p: 14, w: "fill", grow: 1 },
      F("Window", { flex: "col", gap: 4, w: 210, h: 120, rounded: 6, bg: "#F7F8FA", stroke: "#00000022", strokeWidth: 1, overflow: "hidden" },
        F("Bar", { flex: "row", items: "center", gap: 3, w: "fill", px: 6, py: 3, bg: "#E9ECF0" }, F("R", { w: 5, h: 5, rounded: 3, bg: "#F7666B" }) + F("Y", { w: 5, h: 5, rounded: 3, bg: "#F7B84B" }) + F("G", { w: 5, h: 5, rounded: 3, bg: "#4DD9A0" }) + T("OpenCodeBar", { size: 5, color: "#3C4450", w: "fill", textAlign: "center" })) +
        F("Body", { flex: "col", gap: 3, p: 6 }, T("Live", { size: 6, weight: "bold", color: "#1B1F24" }) + F("Row", { flex: "row", gap: 3, p: 3, rounded: 3, bg: "#FFFFFF" }, F("D", { w: 4, h: 4, rounded: 2, bg: "#0B7DA6" }) + T("Match iPhone dark theme", { size: 5, color: "#1B1F24", w: "fill" })) + F("Row", { flex: "row", gap: 3, p: 3, rounded: 3, bg: "#FFFFFF" }, F("D", { w: 4, h: 4, rounded: 2, bg: "#0B7DA6" }) + T("Exploring potential new features", { size: 5, color: "#1B1F24", w: "fill" }))))),
    F("Toolbar", { flex: "row", items: "center", gap: 5, w: "fill", px: 10, py: 5, bg: "#171717" },
      chip("⌘", D.sec) + chip("⌥", D.sec) + chip("⇧", D.sec) + chip("Esc", D.sec) + chip("Tab", D.sec) + F("S", { grow: 1 }) + chip("Sharp · 42 fps", D.accent) + I("lucide:maximize", 10, D.sec))),
  F("Hint", { flex: "row", gap: 6, p: 8, mx: 12, mb: 8, rounded: 8, bg: D.card, stroke: D.border, strokeWidth: 1, w: "fill" }, I("lucide:hand", 10, D.sec) + T("Pinch to zoom · two-finger pan · two-finger tap toggles fit", { size: 7, color: D.sec, w: "fill" })),
);

const remotePermission = F("iOS · Remote permissions", { flex: "col", gap: 12, w: 414, h: 896, bg: "#0C0C0C", rounded: 34, stroke: D.border, strokeWidth: 1, p: 18, justify: "center" },
  F("Top", { flex: "row", items: "center", gap: 6, w: "fill" }, I("lucide:chevron-left", 12, D.accent) + T("Host", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("Remote", D.accent)),
  F("Icon", { w: 54, h: 54, rounded: 16, bg: D.warn + "18", items: "center", justify: "center" }, I("lucide:monitor-off", 26, D.warn)) +
  T("Screen Recording is off", { size: 18, weight: "bold", color: D.text, textAlign: "center" }) +
  T("The ScreenCaptureKit helper needs Screen Recording to stream this Mac. Accessibility is only needed to send input.", { size: 9, color: D.sec, textAlign: "center", lineHeight: 13, w: 330 }) +
  F("Perms", { flex: "col", gap: 5, p: 10, rounded: 10, bg: D.card, w: "fill" },
    F("P1", { flex: "row", items: "center", gap: 6 }, I("lucide:circle-x", 10, D.danger) + T("Screen Recording", { size: 9, color: D.text }) + F("S", { grow: 1 }) + chip("missing", D.danger)) +
    F("P2", { flex: "row", items: "center", gap: 6 }, I("lucide:circle-x", 10, D.danger) + T("Accessibility", { size: 9, color: D.text }) + F("S", { grow: 1 }) + chip("view-only", D.warn))) +
  F("Open", { flex: "row", items: "center", justify: "center", gap: 5, py: 8, rounded: 9, bg: D.accent }, I("lucide:external-link", 10, "#062017") + T("Open System Settings", { size: 10, weight: "bold", color: "#062017" })),
  T("Without Accessibility the stream stays view-only; taps and keys are not sent.", { size: 8, color: D.ter, textAlign: "center", w: 320 }),
);

const appDetail = host("iOS · App detail", [
  F("H", { flex: "row", items: "center", gap: 5, w: "fill" }, I("lucide:chevron-left", 11, D.accent) + T("Software", { size: 9, color: D.accent }) + F("S", { grow: 1 }) + chip("installed", D.accent)),
  F("App", { flex: "row", items: "center", gap: 8, p: 9, rounded: 9, bg: D.card },
    F("I", { w: 38, h: 38, rounded: 9, bg: "#2F7CF6", items: "center", justify: "center" }, I("lucide:app-window", 18, "#FFFFFF")) +
    F("B", { flex: "col", gap: 1 }, T("OpenPencil", { size: 13, weight: "bold", color: D.text }), T("0.16.0 · net.dannote.open-pencil", { size: 7, color: D.sec }))),
  F("Card", { flex: "col", gap: 3, p: 9, rounded: 9, bg: D.card, w: "fill" },
    T("BUNDLE", { size: 7, weight: "bold", color: D.sec }), T("/Applications/OpenPencil.app", { size: 7, color: D.text }), T("Signed: Dannote · notarized", { size: 7, color: D.sec }), T("Extensions: none · URL schemes: openpencil", { size: 7, color: D.sec })) +
  F("Card", { flex: "col", gap: 3, p: 9, rounded: 9, bg: D.card, w: "fill" },
    T("XCODE · SIMULATORS", { size: 7, weight: "bold", color: D.sec }), T("iOS 18.2 · iPhone 17 Pro · booted", { size: 7, color: D.text }), T("iOS 17.5 · iPad Pro 13-inch · shutdown", { size: 7, color: D.sec })) +
  F("Actions", { flex: "row", gap: 5, w: "fill" }, chip("Boot", D.accent) + chip("Shutdown", D.sec) + chip("Erase", D.warn) + chip("Delete", D.danger)),
]);

export default function () {
  const title = "iOS — Host and Remote desktop";
  const subtitle = "The phone can watch the Mac: vitals, storage, network, software, terminals and files, plus a live remote display with touch and keyboard input.";
  const meta = "Sources: HostView.swift · SystemView.swift · SystemCategoryView.swift · RemoteDesktopView.swift · RemoteDesktopConnection.swift · MobileTerminalViews.swift · MobileFileBrowser.swift · SystemAppDetailView.swift";
  return {
    flat: true,
    sections: [
      R("Page background", { x: 0, y: 0, w: 2400, h: 3342, bg: "#E9ECEF" }),
      F("Header position", { x: 72, y: 72, w: 2256, h: "hug" },
        pageHeader({ title, subtitle, meta })),
      group("Host dashboard and focused pages", "Vitals double as navigation; each focused page keeps the same card rhythm.", [
        F("Col", { flex: "col", gap: 10 }, T("Host · dashboard", { size: 13, weight: "semibold", color: "#2B3038" }), hostDash),
        F("Col", { flex: "col", gap: 10 }, T("Performance", { size: 13, weight: "semibold", color: "#2B3038" }), performance),
        F("Col", { flex: "col", gap: 10 }, T("Storage", { size: 13, weight: "semibold", color: "#2B3038" }), storage),
        F("Col", { flex: "col", gap: 10 }, T("Network", { size: 13, weight: "semibold", color: "#2B3038" }), network),
      ].join(""), { x: 72, y: 250, w: 2256 }),
      group("Software, machine and tools", "Everything is read-only except terminal input and app actions.", [
        F("Col", { flex: "col", gap: 10 }, T("Software", { size: 13, weight: "semibold", color: "#2B3038" }), software),
        F("Col", { flex: "col", gap: 10 }, T("Machine & health", { size: 13, weight: "semibold", color: "#2B3038" }), machine),
        F("Col", { flex: "col", gap: 10 }, T("Terminals", { size: 13, weight: "semibold", color: "#2B3038" }), terminals),
        F("Col", { flex: "col", gap: 10 }, T("Files", { size: 13, weight: "semibold", color: "#2B3038" }), files),
      ].join(""), { x: 72, y: 1300, w: 2256 }),
      group("Remote desktop", "Streaming, permissions and view-only fallback.", [
        F("Col", { flex: "col", gap: 10 }, T("Remote · connected", { size: 13, weight: "semibold", color: "#2B3038" }), remote),
        F("Col", { flex: "col", gap: 10 }, T("Remote · permissions", { size: 13, weight: "semibold", color: "#2B3038" }), remotePermission),
        F("Col", { flex: "col", gap: 10 }, T("App detail", { size: 13, weight: "semibold", color: "#2B3038" }), appDetail),
      ].join(""), { x: 72, y: 2350, w: 2256 }),
    ],
  };
}
