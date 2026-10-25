/**
 * The NixOS configuration catalog.
 *
 * Every entry is a small, declarative unit the apps can render as a card:
 * metadata for the UI plus the NixOS module lines and nixpkgs attributes the
 * hub writes into `configuration.nix`. Keeping the catalog here (instead of in
 * Swift) means the macOS app, the iPhone app, and the REST API always offer the
 * same options and the same rendered result.
 */

import { VMValidationError } from "./errors.ts";
import { DEFAULT_PACKAGES, effectivePackages, normalizePackages } from "./packages.ts";
import type {
  NixOSBuilderConfig,
  NixOSBuilderSettings,
  NixOSManagedUser,
  VMConfigCatalog,
  VMConfigCategory,
  VMConfigCategoryID,
  VMConfigOption,
  VMConfigPreset,
} from "./types.ts";

interface CatalogOption extends VMConfigOption {
  /** NixOS module body. It is indented and inserted into the guest module. */
  nix: string;
}

export const CATEGORIES: VMConfigCategory[] = [
  {
    id: "system",
    name: "System",
    summary: "Boot, shell, and quality-of-life basics",
    icon: "gearshape.fill",
    tint: "accent",
  },
  {
    id: "desktop",
    name: "Desktop",
    summary: "A graphical session, browsers, and audio",
    icon: "display",
    tint: "reasoning",
  },
  {
    id: "development",
    name: "Development",
    summary: "Languages, editors, and build tools",
    icon: "hammer.fill",
    tint: "input",
  },
  {
    id: "containers",
    name: "Containers",
    summary: "Docker, Podman, Kubernetes, and virtual machines",
    icon: "shippingbox.fill",
    tint: "output",
  },
  {
    id: "services",
    name: "Services",
    summary: "Self-hosted apps and databases",
    icon: "server.rack",
    tint: "accent",
  },
  {
    id: "networking",
    name: "Networking",
    summary: "Remote access, discovery, and web servers",
    icon: "network",
    tint: "running",
  },
  {
    id: "media",
    name: "Media",
    summary: "Streaming, photos, and file sharing",
    icon: "play.rectangle.fill",
    tint: "warn",
  },
  {
    id: "ai",
    name: "AI",
    summary: "Local models, notebooks, and assistants",
    icon: "sparkles",
    tint: "reasoning",
  },
  {
    id: "observability",
    name: "Monitoring",
    summary: "Metrics, dashboards, and logs",
    icon: "chart.xyaxis.line",
    tint: "cacheRead",
  },
  {
    id: "security",
    name: "Security",
    summary: "Hardening, secrets, and privacy",
    icon: "lock.shield.fill",
    tint: "danger",
  },
  {
    id: "gaming",
    name: "Gaming",
    summary: "Steam, emulators, and game servers",
    icon: "gamecontroller.fill",
    tint: "output",
  },
  {
    id: "advanced",
    name: "Advanced",
    summary: "Ports, raw packages, and custom Nix",
    icon: "slider.horizontal.3",
    tint: "secondary",
  },
];

const option = (
  value: Omit<CatalogOption, "description" | "tint" | "tags" | "badge" | "packages" | "requires" | "recommends" | "conflicts" | "ports" | "services" | "defaultOn" | "locked" | "sizeMB" | "unfree" | "nix"> &
    Partial<CatalogOption>,
): CatalogOption => ({
  description: value.summary,
  tint: "accent",
  tags: [],
  badge: null,
  packages: [],
  requires: [],
  recommends: [],
  conflicts: [],
  ports: [],
  services: [],
  defaultOn: false,
  locked: false,
  sizeMB: 0,
  unfree: false,
  nix: "",
  ...value,
});

export const OPTIONS: CatalogOption[] = [
  // ── System ────────────────────────────────────────────────────────────────
  option({
    id: "ssh",
    category: "system",
    name: "OpenSSH",
    summary: "Key-only remote login, used by the hub to apply changes",
    description:
      "OpenSSH is always enabled. The hub authorizes its generated ed25519 key for the opencodebar admin and never enables password logins unless you ask for them.",
    icon: "terminal.fill",
    tint: "running",
    locked: true,
    defaultOn: true,
    sizeMB: 18,
    services: ["OpenSSH"],
  }),
  option({
    id: "flakes",
    category: "system",
    name: "Flakes & nix-command",
    summary: "The modern Nix CLI that the generated flake uses",
    description:
      "Enables `nix-command` and `flakes`. The hub's flake and every in-guest rebuild depend on these experimental features.",
    icon: "snowflake",
    tint: "input",
    locked: true,
    defaultOn: true,
    sizeMB: 0,
  }),
  option({
    id: "optimise",
    category: "system",
    name: "Store optimisation",
    summary: "Deduplicate the Nix store automatically",
    description:
      "Runs the Nix store optimiser after builds. It keeps the guest image smaller with no runtime cost.",
    icon: "arrow.triangle.merge",
    tint: "output",
    locked: true,
    defaultOn: true,
    sizeMB: 0,
  }),
  option({
    id: "zram",
    category: "system",
    name: "zram swap",
    summary: "Compressed RAM swap for a small, fast guest",
    description:
      "Creates a compressed swap device in memory. It makes a 4 GB guest feel larger without growing the disk.",
    icon: "memorychip.fill",
    tint: "reasoning",
    defaultOn: true,
    sizeMB: 0,
    nix: `zramSwap = {
  enable = true;
  memoryPercent = 50;
};`,
  }),
  option({
    id: "nix-ld",
    category: "system",
    name: "nix-ld",
    summary: "Run prebuilt Linux binaries that expect /lib64",
    description:
      "Provides a dynamic loader shim so downloaded binaries, VS Code extensions, and language toolchains can run without patching.",
    icon: "link",
    tint: "input",
    sizeMB: 4,
    nix: `programs.nix-ld.enable = true;`,
  }),
  option({
    id: "fish",
    category: "system",
    name: "Fish shell",
    summary: "Friendly interactive shell with completions",
    description:
      "Enables Fish system-wide. Choose it as a login shell for any managed user in the Users step.",
    icon: "fish.fill",
    tint: "output",
    sizeMB: 22,
    nix: `programs.fish.enable = true;`,
  }),
  option({
    id: "zsh",
    category: "system",
    name: "Zsh",
    summary: "A powerful, extensible login shell",
    description:
      "Enables Zsh system-wide. Pair it with a managed user whose shell is set to zsh.",
    icon: "terminal",
    tint: "running",
    sizeMB: 18,
    nix: `programs.zsh.enable = true;`,
  }),
  option({
    id: "avahi",
    category: "system",
    name: "mDNS discovery",
    summary: "Advertise the guest as hostname.local",
    description:
      "Runs Avahi so the guest is discoverable as `<hostname>.local` on the LAN. Useful for services, printing, and Syncthing.",
    icon: "dot.radiowaves.left.and.right",
    tint: "running",
    sizeMB: 3,
    services: ["Avahi / mDNS"],
    nix: `services.avahi = {
  enable = true;
  nssmdns4 = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "flatpak",
    category: "system",
    name: "Flatpak",
    summary: "Install sandboxed desktop apps from Flathub",
    description:
      "Enables Flatpak and its portals. Useful on desktop guests, and harmless on headless ones.",
    icon: "square.stack.3d.up.fill",
    tint: "reasoning",
    sizeMB: 26,
    nix: `services.flatpak.enable = true;`,
  }),
  option({
    id: "printing",
    category: "system",
    name: "Printing",
    summary: "CUPS with mDNS printer discovery",
    description:
      "Enables CUPS and the Avahi printing helpers so network printers appear in desktop apps.",
    icon: "printer.fill",
    tint: "warn",
    sizeMB: 34,
    services: ["CUPS"],
    nix: `services.printing.enable = true;
services.avahi.enable = true;
services.avahi.nssmdns4 = true;`,
  }),
  option({
    id: "bluetooth",
    category: "system",
    name: "Bluetooth",
    summary: "Bluetooth stack and firmware hooks",
    description:
      "Enables the Bluetooth service. Virtualized guests only see a radio when the host passes one through.",
    icon: "wave.3.right.circle.fill",
    tint: "input",
    sizeMB: 12,
    nix: `hardware.bluetooth = {
  enable = true;
  powerOnBoot = true;
};`,
  }),
  option({
    id: "fstrim",
    category: "system",
    name: "Weekly trim",
    summary: "Discard unused blocks on the guest disk",
    description:
      "Runs fstrim on a timer. It keeps the sparse raw image small on the Mac.",
    icon: "scissors",
    tint: "output",
    sizeMB: 0,
    nix: `services.fstrim.enable = true;`,
  }),
  option({
    id: "locate",
    category: "system",
    name: "locate database",
    summary: "Fast filename search with updatedb",
    description:
      "Enables the locate database and a daily updatedb timer.",
    icon: "magnifyingglass",
    tint: "cacheRead",
    sizeMB: 4,
    nix: `services.locate.enable = true;`,
  }),

  // ── Desktop ───────────────────────────────────────────────────────────────
  option({
    id: "gnome",
    category: "desktop",
    name: "GNOME",
    summary: "A complete, beginner-friendly GNOME desktop",
    description:
      "GDM, GNOME Shell, and the standard GNOME app set. Pick a desktop guest when you need a graphical session inside the VM.",
    icon: "display",
    tint: "reasoning",
    tags: ["GUI", "Wayland"],
    badge: "Popular",
    conflicts: ["kde", "xfce", "hyprland"],
    recommends: ["audio", "fonts"],
    sizeMB: 2_400,
    services: ["GDM", "GNOME Shell"],
    nix: `services.xserver.enable = true;
services.displayManager.gdm.enable = true;
services.desktopManager.gnome.enable = true;`,
  }),
  option({
    id: "kde",
    category: "desktop",
    name: "KDE Plasma",
    summary: "Plasma 6 with SDDM and a familiar desktop",
    description:
      "KDE Plasma 6, SDDM, and the KDE application suite. It is heavier than GNOME but very configurable.",
    icon: "rectangle.3.group.fill",
    tint: "input",
    tags: ["GUI", "Wayland"],
    conflicts: ["gnome", "xfce", "hyprland"],
    recommends: ["audio", "fonts"],
    sizeMB: 2_800,
    services: ["SDDM", "Plasma 6"],
    nix: `services.xserver.enable = true;
services.displayManager.sddm.enable = true;
services.desktopManager.plasma6.enable = true;`,
  }),
  option({
    id: "xfce",
    category: "desktop",
    name: "XFCE",
    summary: "A light desktop for small VMs",
    description:
      "XFCE with LightDM. It is the best choice when the guest has 4 GB of memory or less.",
    icon: "rectangle.split.3x3.fill",
    tint: "output",
    tags: ["GUI", "Lightweight"],
    conflicts: ["gnome", "kde", "hyprland"],
    recommends: ["audio", "fonts"],
    sizeMB: 1_100,
    services: ["LightDM", "XFCE"],
    nix: `services.xserver.enable = true;
services.xserver.desktopManager.xfce.enable = true;
services.xserver.displayManager.lightdm.enable = true;`,
  }),
  option({
    id: "hyprland",
    category: "desktop",
    name: "Hyprland",
    summary: "A tiling Wayland compositor",
    description:
      "Hyprland with SDDM's Wayland session. Bring your own dotfiles; the default keymap is intentionally spartan.",
    icon: "rectangle.split.2x2.fill",
    tint: "reasoning",
    tags: ["GUI", "Wayland", "Tiling"],
    conflicts: ["gnome", "kde", "xfce"],
    recommends: ["audio", "fonts"],
    sizeMB: 950,
    services: ["SDDM", "Hyprland"],
    nix: `programs.hyprland.enable = true;
services.xserver.enable = true;
services.displayManager.sddm.enable = true;
services.displayManager.sddm.wayland.enable = true;`,
  }),
  option({
    id: "audio",
    category: "desktop",
    name: "PipeWire audio",
    summary: "Modern audio and screen-sharing support",
    description:
      "PipeWire with ALSA and PulseAudio compatibility. Desktop apps and browsers expect it.",
    icon: "speaker.wave.2.fill",
    tint: "warn",
    sizeMB: 38,
    services: ["PipeWire"],
    nix: `services.pipewire = {
  enable = true;
  alsa.enable = true;
  alsa.support32Bit = true;
  pulse.enable = true;
};`,
  }),
  option({
    id: "fonts",
    category: "desktop",
    name: "Font pack",
    summary: "DejaVu, Liberation, Noto, and emoji",
    description:
      "A broad font set that makes a graphical guest, browser, and office suite look right out of the box.",
    icon: "textformat",
    tint: "cacheWrite",
    sizeMB: 320,
    nix: `fonts.packages = with pkgs; [
  dejavu_fonts
  liberation_ttf
  noto-fonts
  noto-fonts-emoji
];`,
  }),
  option({
    id: "firefox",
    category: "desktop",
    name: "Firefox",
    summary: "The privacy-friendly browser",
    description: "Installs Mozilla Firefox with the standard NixOS wrapper.",
    icon: "globe",
    tint: "warn",
    tags: ["App"],
    packages: ["firefox"],
    sizeMB: 310,
  }),
  option({
    id: "chromium",
    category: "desktop",
    name: "Chromium",
    summary: "A second browser for testing",
    description: "Installs Chromium for web testing and a Chrome-like profile.",
    icon: "globe.americas.fill",
    tint: "running",
    tags: ["App"],
    packages: ["chromium"],
    sizeMB: 370,
  }),
  option({
    id: "libreoffice",
    category: "desktop",
    name: "LibreOffice",
    summary: "Documents, spreadsheets, and slides",
    description: "Installs the full LibreOffice suite.",
    icon: "doc.richtext.fill",
    tint: "input",
    tags: ["App", "Office"],
    packages: ["libreoffice"],
    sizeMB: 720,
  }),
  option({
    id: "gimp",
    category: "desktop",
    name: "GIMP",
    summary: "Photo editing and image manipulation",
    description: "Installs GIMP and its common plugins.",
    icon: "photo.fill",
    tint: "output",
    tags: ["App", "Creative"],
    packages: ["gimp"],
    sizeMB: 350,
  }),
  option({
    id: "obs",
    category: "desktop",
    name: "OBS Studio",
    summary: "Screen recording and streaming",
    description: "Installs OBS Studio. Screen capture inside a VM may be limited by the guest GPU.",
    icon: "record.circle",
    tint: "danger",
    tags: ["App", "Creative"],
    packages: ["obs-studio"],
    sizeMB: 390,
  }),
  option({
    id: "vlc",
    category: "desktop",
    name: "VLC",
    summary: "Play almost any media format",
    description: "Installs VLC media player.",
    icon: "play.circle.fill",
    tint: "warn",
    tags: ["App", "Media"],
    packages: ["vlc"],
    sizeMB: 180,
  }),

  // ── Development ───────────────────────────────────────────────────────────
  option({
    id: "git-tools",
    category: "development",
    name: "Git toolbox",
    summary: "git, GitHub CLI, LFS, lazygit, and delta",
    description:
      "The everyday Git stack: the CLI, GitHub CLI, large-file support, a TUI, and a readable diff pager.",
    icon: "arrow.triangle.branch",
    tint: "output",
    tags: ["Git", "CLI"],
    badge: "Popular",
    defaultOn: true,
    packages: ["git", "gh", "git-lfs", "lazygit", "delta"],
    sizeMB: 120,
  }),
  option({
    id: "neovim",
    category: "development",
    name: "Neovim",
    summary: "Neovim with ripgrep, fd, and tree-sitter",
    description:
      "The editor plus the search and parsing tools most Neovim distributions expect.",
    icon: "chevron.left.forwardslash.chevron.right",
    tint: "accent",
    tags: ["Editor", "CLI"],
    defaultOn: true,
    packages: ["neovim", "ripgrep", "fd", "tree-sitter"],
    sizeMB: 110,
  }),
  option({
    id: "vscode",
    category: "development",
    name: "VS Code",
    summary: "The editor with the biggest extension ecosystem",
    description: "Installs VS Code. Extensions can be added from the editor after first boot.",
    icon: "Chevron.left.slash.Chevron.right",
    tint: "input",
    tags: ["Editor", "GUI"],
    packages: ["vscode"],
    sizeMB: 480,
  }),
  option({
    id: "tmux",
    category: "development",
    name: "Terminal multiplexers",
    summary: "tmux and zellij for long-running shells",
    description: "Installs tmux and zellij. They are ideal for SSH sessions and background builds.",
    icon: "rectangle.split.3x1.fill",
    tint: "running",
    tags: ["CLI"],
    packages: ["tmux", "zellij"],
    sizeMB: 26,
  }),
  option({
    id: "nodejs",
    category: "development",
    name: "Node.js",
    summary: "Node, pnpm, and Yarn",
    description: "The JavaScript runtime and both common package managers.",
    icon: "hexagon.fill",
    tint: "output",
    tags: ["Language", "Web"],
    packages: ["nodejs", "pnpm", "yarn"],
    sizeMB: 280,
  }),
  option({
    id: "python",
    category: "development",
    name: "Python",
    summary: "Python 3, pip, and virtualenv",
    description: "Python 3 with the packaging tools needed for isolated environments.",
    icon: "chevron.left.forwardslash.chevron.right",
    tint: "input",
    tags: ["Language"],
    packages: ["python3", "python3Packages.pip", "python3Packages.virtualenv"],
    sizeMB: 210,
  }),
  option({
    id: "rust",
    category: "development",
    name: "Rust",
    summary: "rustc, Cargo, rustfmt, and Clippy",
    description: "A complete stable Rust toolchain.",
    icon: "gearshape.2.fill",
    tint: "warn",
    tags: ["Language"],
    packages: ["rustc", "cargo", "rustfmt", "clippy"],
    sizeMB: 620,
  }),
  option({
    id: "go",
    category: "development",
    name: "Go",
    summary: "Go, gopls, and gotools",
    description: "The Go toolchain plus language-server support.",
    icon: "hare.fill",
    tint: "running",
    tags: ["Language"],
    packages: ["go", "gopls", "gotools"],
    sizeMB: 540,
  }),
  option({
    id: "cc",
    category: "development",
    name: "C / C++ toolchain",
    summary: "GCC, GNU Make, CMake, and pkg-config",
    description: "Everything needed for native extensions, kernels, and systems projects.",
    icon: "wrench.and.screwdriver.fill",
    tint: "cacheRead",
    tags: ["Language", "Build"],
    packages: ["gcc", "gnumake", "cmake", "pkg-config"],
    sizeMB: 720,
  }),
  option({
    id: "jvm",
    category: "development",
    name: "Java / JVM",
    summary: "JDK, Maven, and Gradle",
    description: "A modern JDK and the two most common JVM build tools.",
    icon: "cup.and.saucer.fill",
    tint: "danger",
    tags: ["Language"],
    packages: ["jdk", "maven", "gradle"],
    sizeMB: 680,
  }),
  option({
    id: "databases",
    category: "development",
    name: "Database clients",
    summary: "sqlite, psql, and redis-cli",
    description: "Client tools for SQLite, PostgreSQL, and Redis without running the servers.",
    icon: "cylinder.split.1x2.fill",
    tint: "reasoning",
    tags: ["CLI", "Data"],
    packages: ["sqlite", "postgresql", "redis"],
    sizeMB: 120,
  }),
  option({
    id: "kubernetes",
    category: "development",
    name: "Kubernetes CLI",
    summary: "kubectl, k9s, Helm, and Kustomize",
    description: "The standard toolkit for working with clusters from the guest.",
    icon: "helm",
    tint: "input",
    tags: ["CLI", "Infra"],
    packages: ["kubectl", "k9s", "helm", "kustomize"],
    sizeMB: 190,
  }),
  option({
    id: "terraform",
    category: "development",
    name: "Terraform",
    summary: "Terraform, tflint, and Terragrunt",
    description: "Infrastructure-as-code tooling for cloud and homelab projects.",
    icon: "square.stack.3d.up.fill",
    tint: "reasoning",
    tags: ["CLI", "Infra"],
    packages: ["terraform", "tflint", "terragrunt"],
    sizeMB: 240,
  }),
  option({
    id: "nix-tools",
    category: "development",
    name: "Nix tooling",
    summary: "nixd, nil, and nixpkgs-fmt",
    description: "Language servers and a formatter for editing the generated NixOS configuration.",
    icon: "snowflake",
    tint: "input",
    tags: ["Nix", "Editor"],
    packages: ["nixd", "nil", "nixpkgs-fmt"],
    sizeMB: 140,
  }),
  option({
    id: "direnv",
    category: "development",
    name: "direnv + nix-direnv",
    summary: "Per-project environments that load automatically",
    description:
      "Enables direnv and nix-direnv, which caches Nix development environments per project.",
    icon: "arrow.down.right.circle.fill",
    tint: "output",
    tags: ["Nix", "CLI"],
    packages: [],
    sizeMB: 6,
    nix: `programs.direnv = {
  enable = true;
  nix-direnv.enable = true;
};`,
  }),
  option({
    id: "web-tools",
    category: "development",
    name: "HTTP & data tools",
    summary: "httpie, jq, and yq",
    description: "Small command-line tools for inspecting APIs and structured data.",
    icon: "network.badge.shield.half.filled",
    tint: "running",
    tags: ["CLI"],
    packages: ["httpie", "jq", "yq"],
    sizeMB: 55,
  }),

  // ── Containers ────────────────────────────────────────────────────────────
  option({
    id: "docker",
    category: "containers",
    name: "Docker",
    summary: "Docker Engine with the opencodebar user in the docker group",
    description:
      "Runs Docker at boot and grants the admin user access. Containers are the quickest way to try a service without a rebuild.",
    icon: "shippingbox.fill",
    tint: "output",
    tags: ["Containers", "Infra"],
    badge: "Popular",
    conflicts: ["podman"],
    recommends: ["containers-tools"],
    services: ["Docker Engine"],
    sizeMB: 380,
    nix: `virtualisation.docker = {
  enable = true;
  enableOnBoot = true;
};
users.users.opencodebar.extraGroups = [ "docker" ];`,
  }),
  option({
    id: "podman",
    category: "containers",
    name: "Podman",
    summary: "Daemonless containers with a Docker-compatible socket",
    description:
      "Runs rootless Podman and exposes a Docker socket for tools that expect one. Pick this or Docker, not both.",
    icon: "cube.fill",
    tint: "reasoning",
    tags: ["Containers", "Infra"],
    conflicts: ["docker"],
    services: ["Podman"],
    sizeMB: 340,
    nix: `virtualisation.podman = {
  enable = true;
  dockerSocket.enable = true;
};`,
  }),
  option({
    id: "containers-tools",
    category: "containers",
    name: "Compose & registry tools",
    summary: "docker-compose, podman-compose, and skopeo",
    description: "Helpers for multi-container stacks and copying images between registries.",
    icon: "square.stack.3d.down.right.fill",
    tint: "input",
    tags: ["CLI", "Containers"],
    packages: ["docker-compose", "podman-compose", "skopeo"],
    sizeMB: 95,
  }),
  option({
    id: "k3s",
    category: "containers",
    name: "K3s server",
    summary: "A single-node Kubernetes cluster",
    description:
      "Runs a lightweight Kubernetes control plane. It opens the API on 6443 and is perfect for learning or a small homelab.",
    icon: "helm",
    tint: "running",
    tags: ["Kubernetes", "Infra"],
    recommends: ["kubernetes"],
    ports: [6443],
    services: ["K3s"],
    sizeMB: 900,
    nix: `services.k3s = {
  enable = true;
  role = "server";
};
networking.firewall.allowedTCPPorts = [ 6443 ];`,
  }),
  option({
    id: "libvirt",
    category: "containers",
    name: "libvirt + virt-manager",
    summary: "Run nested virtual machines",
    description:
      "The libvirt daemon and the virt-manager GUI. Nested virtualization needs the host to pass the CPU feature through; it is best used as an experiment.",
    icon: "server.rack",
    tint: "warn",
    tags: ["VMs", "GUI"],
    services: ["libvirtd"],
    sizeMB: 260,
    nix: `virtualisation.libvirtd.enable = true;
programs.virt-manager.enable = true;`,
  }),

  // ── Services ──────────────────────────────────────────────────────────────
  option({
    id: "postgresql",
    category: "services",
    name: "PostgreSQL",
    summary: "A local database with an `app` database and owner",
    description:
      "Runs PostgreSQL, creates the `app` database, and makes it reachable on port 5432 from the host-only network.",
    icon: "cylinder.split.1x2.fill",
    tint: "input",
    tags: ["Database"],
    ports: [5432],
    services: ["PostgreSQL"],
    sizeMB: 260,
    nix: `services.postgresql = {
  enable = true;
  enableTCPIP = true;
  ensureDatabases = [ "app" ];
  ensureUsers = [
    {
      name = "app";
      ensureDBOwnership = true;
    }
  ];
};
networking.firewall.allowedTCPPorts = [ 5432 ];`,
  }),
  option({
    id: "redis",
    category: "services",
    name: "Redis",
    summary: "An in-memory cache and queue",
    description: "Runs a Redis server on 6379 with the default `default` instance.",
    icon: "bolt.fill",
    tint: "danger",
    tags: ["Database", "Cache"],
    ports: [6379],
    services: ["Redis"],
    sizeMB: 32,
    nix: `services.redis.servers."default" = {
  enable = true;
  port = 6379;
};
networking.firewall.allowedTCPPorts = [ 6379 ];`,
  }),
  option({
    id: "mariadb",
    category: "services",
    name: "MariaDB",
    summary: "A MySQL-compatible SQL server",
    description: "Runs MariaDB on 3306. It is a good fit for web apps that expect MySQL.",
    icon: "cylinder.fill",
    tint: "warn",
    tags: ["Database"],
    ports: [3306],
    services: ["MariaDB"],
    sizeMB: 290,
    nix: `services.mysql = {
  enable = true;
  package = pkgs.mariadb;
};
networking.firewall.allowedTCPPorts = [ 3306 ];`,
  }),
  option({
    id: "gitea",
    category: "services",
    name: "Gitea",
    summary: "A lightweight self-hosted Git forge",
    description:
      "Runs Gitea on port 3000 with SQLite storage. Create the first admin account in the browser.",
    icon: "arrow.triangle.branch",
    tint: "output",
    tags: ["Git", "Self-hosted"],
    ports: [3000],
    services: ["Gitea"],
    sizeMB: 210,
    nix: `services.gitea = {
  enable = true;
  settings.server = {
    DOMAIN = "localhost";
    HTTP_PORT = 3000;
    ROOT_URL = "http://localhost:3000/";
  };
};
networking.firewall.allowedTCPPorts = [ 3000 ];`,
  }),
  option({
    id: "syncthing",
    category: "services",
    name: "Syncthing",
    summary: "Peer-to-peer file sync with a web UI",
    description:
      "Runs Syncthing for the admin user with its discovery and relay ports open. Pair it with a folder on the Mac.",
    icon: "arrow.triangle.2.circlepath",
    tint: "running",
    tags: ["Files", "Self-hosted"],
    ports: [8384, 22000],
    services: ["Syncthing"],
    sizeMB: 140,
    nix: `services.syncthing = {
  enable = true;
  openDefaultPorts = true;
};`,
  }),
  option({
    id: "samba",
    category: "services",
    name: "Samba share",
    summary: "A guest-writable SMB share at /srv/share",
    description:
      "Runs Samba with a permissive `share` export. Use it to move files between the Mac and the guest.",
    icon: "folder.badge.gearshape",
    tint: "warn",
    tags: ["Files", "SMB"],
    ports: [139, 445],
    services: ["Samba"],
    sizeMB: 180,
    nix: `services.samba = {
  enable = true;
  openFirewall = true;
  settings = {
    global = {
      workgroup = "WORKGROUP";
      "server string" = "OpenCodeBar";
      "map to guest" = "Bad User";
    };
    share = {
      path = "/srv/share";
      browseable = "yes";
      "read only" = "no";
      "guest ok" = "yes";
    };
  };
};
systemd.tmpfiles.rules = [ "d /srv/share 0775 root root -" ];`,
  }),
  option({
    id: "home-assistant",
    category: "services",
    name: "Home Assistant",
    summary: "Local home automation on port 8123",
    description:
      "Runs Home Assistant with its onboarding wizard. It is happiest with at least 2 GB of guest memory.",
    icon: "house.fill",
    tint: "accent",
    tags: ["Home", "Self-hosted"],
    ports: [8123],
    services: ["Home Assistant"],
    sizeMB: 460,
    nix: `services.home-assistant = {
  enable = true;
  openFirewallForComponents = true;
};
networking.firewall.allowedTCPPorts = [ 8123 ];`,
  }),
  option({
    id: "vaultwarden",
    category: "services",
    name: "Vaultwarden",
    summary: "A tiny Bitwarden-compatible password vault",
    description:
      "Runs Vaultwarden on 8222 with signups enabled for first-run setup. Put it behind Tailscale or Caddy for remote use.",
    icon: "key.fill",
    tint: "danger",
    tags: ["Security", "Self-hosted"],
    ports: [8222],
    services: ["Vaultwarden"],
    sizeMB: 120,
    nix: `services.vaultwarden = {
  enable = true;
  config = {
    ROCKET_ADDRESS = "0.0.0.0";
    ROCKET_PORT = 8222;
    SIGNUPS_ALLOWED = "true";
  };
};
networking.firewall.allowedTCPPorts = [ 8222 ];`,
  }),
  option({
    id: "n8n",
    category: "services",
    name: "n8n",
    summary: "Workflow automation with a visual editor",
    description: "Runs n8n on port 5678. It is a local Zapier-style automation server.",
    icon: "point.3.connected.trianglepath.dotted",
    tint: "reasoning",
    tags: ["Automation", "Self-hosted"],
    ports: [5678],
    services: ["n8n"],
    sizeMB: 330,
    nix: `services.n8n = {
  enable = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "minio",
    category: "services",
    name: "MinIO",
    summary: "S3-compatible object storage",
    description:
      "Runs MinIO with the API on 9000 and the console on 9001. The default credentials are shown in its docs; change them before exposing it.",
    icon: "externaldrive.fill.badge.icloud",
    tint: "output",
    tags: ["Storage", "Self-hosted"],
    ports: [9000, 9001],
    services: ["MinIO"],
    sizeMB: 210,
    nix: `services.minio = {
  enable = true;
  listenAddress = "0.0.0.0:9000";
  consoleAddress = "0.0.0.0:9001";
};
networking.firewall.allowedTCPPorts = [ 9000 9001 ];`,
  }),

  // ── Networking ────────────────────────────────────────────────────────────
  option({
    id: "tailscale",
    category: "networking",
    name: "Tailscale",
    summary: "Private mesh access from anywhere",
    description:
      "Enables Tailscale and trusts its interface. Run `tailscale up` in the guest console once to join your tailnet.",
    icon: "point.3.connected.trianglepath.dotted",
    tint: "running",
    tags: ["VPN", "Remote"],
    badge: "Popular",
    services: ["Tailscale"],
    sizeMB: 60,
    nix: `services.tailscale = {
  enable = true;
  openFirewall = true;
};
networking.firewall.trustedInterfaces = [ "tailscale0" ];`,
  }),
  option({
    id: "nginx",
    category: "networking",
    name: "Nginx",
    summary: "A production web server on port 80",
    description:
      "Runs Nginx with a small default page. Edit the generated configuration to add real virtual hosts.",
    icon: "server.rack",
    tint: "output",
    tags: ["Web", "Reverse proxy"],
    ports: [80, 443],
    conflicts: ["caddy"],
    services: ["Nginx"],
    sizeMB: 42,
    nix: `services.nginx = {
  enable = true;
  recommendedGzipSettings = true;
  recommendedOptimisation = true;
  recommendedProxySettings = true;
  recommendedTlsSettings = true;
};
services.nginx.virtualHosts."default" = {
  listen = [ { addr = "0.0.0.0"; port = 80; } ];
  locations."/" = {
    return = "200 'OpenCodeBar NixOS is ready'";
  };
};`,
  }),
  option({
    id: "caddy",
    category: "networking",
    name: "Caddy",
    summary: "Automatic HTTPS and a simple reverse proxy",
    description:
      "Runs Caddy with a starter virtual host. It is a compact alternative to Nginx and handles TLS automatically.",
    icon: "lock.rectangle.stack.fill",
    tint: "accent",
    tags: ["Web", "Reverse proxy"],
    ports: [80, 443],
    conflicts: ["nginx"],
    services: ["Caddy"],
    sizeMB: 55,
    nix: `services.caddy = {
  enable = true;
  virtualHosts.":80".extraConfig = ''
    respond "OpenCodeBar NixOS is ready"
  '';
};
networking.firewall.allowedTCPPorts = [ 80 443 ];`,
  }),

  // ── Media ─────────────────────────────────────────────────────────────────
  option({
    id: "jellyfin",
    category: "media",
    name: "Jellyfin",
    summary: "A self-hosted media server",
    description:
      "Runs Jellyfin on 8096 with its setup wizard. Add media folders under /srv/media from the console.",
    icon: "play.rectangle.fill",
    tint: "warn",
    tags: ["Media", "Self-hosted"],
    ports: [8096],
    services: ["Jellyfin"],
    sizeMB: 380,
    nix: `services.jellyfin = {
  enable = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "navidrome",
    category: "media",
    name: "Navidrome",
    summary: "A personal music streaming server",
    description:
      "Runs Navidrome on 4533. Point it at a music folder in the web UI after first boot.",
    icon: "music.note.house.fill",
    tint: "reasoning",
    tags: ["Music", "Self-hosted"],
    ports: [4533],
    services: ["Navidrome"],
    sizeMB: 95,
    nix: `services.navidrome = {
  enable = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "ffmpeg",
    category: "media",
    name: "Media toolkit",
    summary: "ffmpeg, ImageMagick, and Plex-style transcoding tools",
    description: "Command-line tools for converting video, audio, and images.",
    icon: "film.stack.fill",
    tint: "output",
    tags: ["CLI", "Media"],
    packages: ["ffmpeg", "imagemagick"],
    sizeMB: 340,
  }),
  option({
    id: "yt-dlp",
    category: "media",
    name: "yt-dlp",
    summary: "Download media from the command line",
    description: "Installs yt-dlp, the actively maintained youtube-dl fork.",
    icon: "arrow.down.circle.fill",
    tint: "danger",
    tags: ["CLI", "Media"],
    packages: ["yt-dlp"],
    sizeMB: 38,
  }),

  // ── AI ────────────────────────────────────────────────────────────────────
  option({
    id: "ollama",
    category: "ai",
    name: "Ollama",
    summary: "Run local language models on the guest",
    description:
      "Runs the Ollama API on 11434 with CPU acceleration. Large models need a lot of RAM and disk; start with a small 3B model.",
    icon: "brain.head.profile",
    tint: "reasoning",
    tags: ["LLM", "Local"],
    badge: "Popular",
    ports: [11434],
    services: ["Ollama"],
    sizeMB: 620,
    nix: `services.ollama = {
  enable = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "open-webui",
    category: "ai",
    name: "Open WebUI",
    summary: "A polished chat UI for local models",
    description:
      "Runs Open WebUI on 8080. Pair it with Ollama for a fully local ChatGPT-style interface.",
    icon: "bubble.left.and.bubble.right.fill",
    tint: "input",
    tags: ["LLM", "GUI"],
    ports: [8080],
    recommends: ["ollama"],
    services: ["Open WebUI"],
    sizeMB: 280,
    nix: `services.open-webui = {
  enable = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "jupyter",
    category: "ai",
    name: "JupyterLab + data stack",
    summary: "Notebooks, NumPy, pandas, and scikit-learn",
    description:
      "A ready-to-use Python data science environment. Start JupyterLab from a shell with `jupyter lab --ip=0.0.0.0`.",
    icon: "book.pages.fill",
    tint: "cacheRead",
    tags: ["Python", "Data", "Notebooks"],
    requires: ["python"],
    ports: [8888],
    packages: [
      "python3Packages.jupyterlab",
      "python3Packages.numpy",
      "python3Packages.pandas",
      "python3Packages.matplotlib",
      "python3Packages.scikit-learn",
    ],
    sizeMB: 1_150,
  }),
  option({
    id: "ai-cli",
    category: "ai",
    name: "AI command-line tools",
    summary: "llm and aichat for terminal assistants",
    description: "Small terminal clients for querying models from scripts and SSH sessions.",
    icon: "terminal.fill",
    tint: "reasoning",
    tags: ["CLI", "LLM"],
    packages: ["llm", "aichat"],
    sizeMB: 85,
  }),

  // ── Monitoring ────────────────────────────────────────────────────────────
  option({
    id: "prometheus",
    category: "observability",
    name: "Prometheus",
    summary: "Metrics collection with a node exporter",
    description:
      "Runs Prometheus on 9090 and exports host metrics. It is the standard metrics backend for Grafana dashboards.",
    icon: "chart.xyaxis.line",
    tint: "warn",
    tags: ["Metrics", "Self-hosted"],
    ports: [9090],
    recommends: ["grafana"],
    services: ["Prometheus", "node_exporter"],
    sizeMB: 240,
    nix: `services.prometheus = {
  enable = true;
  port = 9090;
  exporters.node.enable = true;
};
networking.firewall.allowedTCPPorts = [ 9090 ];`,
  }),
  option({
    id: "grafana",
    category: "observability",
    name: "Grafana",
    summary: "Dashboards for metrics and logs",
    description:
      "Runs Grafana on 3001. Its default admin login is admin/admin; change it on first sign-in.",
    icon: "gauge.with.dots.needle.67percent",
    tint: "warn",
    tags: ["Dashboards", "Self-hosted"],
    ports: [3001],
    recommends: ["prometheus"],
    services: ["Grafana"],
    sizeMB: 210,
    nix: `services.grafana = {
  enable = true;
  settings.server = {
    http_addr = "0.0.0.0";
    http_port = 3001;
  };
};
networking.firewall.allowedTCPPorts = [ 3001 ];`,
  }),
  option({
    id: "netdata",
    category: "observability",
    name: "Netdata",
    summary: "Live, zero-config system dashboards",
    description:
      "Runs Netdata on 19999 with per-second CPU, memory, disk, and network charts.",
    icon: "waveform.path.ecg.rectangle.fill",
    tint: "running",
    tags: ["Metrics", "Dashboards"],
    ports: [19999],
    services: ["Netdata"],
    sizeMB: 180,
    nix: `services.netdata.enable = true;
networking.firewall.allowedTCPPorts = [ 19999 ];`,
  }),
  option({
    id: "glances",
    category: "observability",
    name: "Glances + btop",
    summary: "Two great terminal system monitors",
    description: "Installs Glances and btop for quick CPU, memory, disk, and process inspection over SSH.",
    icon: "activity",
    tint: "cacheRead",
    tags: ["CLI", "Metrics"],
    packages: ["glances", "btop"],
    sizeMB: 40,
  }),

  // ── Security ──────────────────────────────────────────────────────────────
  option({
    id: "fail2ban",
    category: "security",
    name: "Fail2ban",
    summary: "Ban repeated SSH authentication failures",
    description:
      "Watches the journal and bans abusive addresses. It is low-cost insurance for a guest reachable on a LAN or tailnet.",
    icon: "shield.lefthalf.filled",
    tint: "danger",
    tags: ["Hardening", "SSH"],
    services: ["Fail2ban"],
    sizeMB: 18,
    nix: `services.fail2ban.enable = true;`,
  }),
  option({
    id: "clamav",
    category: "security",
    name: "ClamAV",
    summary: "Antivirus scanning with freshclam updates",
    description:
      "Runs the ClamAV daemon and signature updater. It adds a sizeable signature database to the image.",
    icon: "ant.fill",
    tint: "warn",
    tags: ["Hardening", "Antivirus"],
    services: ["ClamAV"],
    sizeMB: 520,
    nix: `services.clamav = {
  daemon.enable = true;
  updater.enable = true;
};`,
  }),
  option({
    id: "tor",
    category: "security",
    name: "Tor",
    summary: "Route traffic through the Tor network",
    description:
      "Runs the Tor client service. Applications must be configured to use the SOCKS proxy on 9050.",
    icon: "network",
    tint: "reasoning",
    tags: ["Privacy", "Proxy"],
    ports: [9050],
    services: ["Tor"],
    sizeMB: 42,
    nix: `services.tor = {
  enable = true;
  client.enable = true;
};`,
  }),
  option({
    id: "apparmor",
    category: "security",
    name: "AppArmor",
    summary: "Mandatory access control for services",
    description:
      "Enables AppArmor profiles and confines services that ship with one.",
    icon: "lock.shield.fill",
    tint: "danger",
    tags: ["Hardening"],
    services: ["AppArmor"],
    sizeMB: 8,
    nix: `security.apparmor = {
  enable = true;
  killUnconfinedConfinables = true;
};`,
  }),
  option({
    id: "auditd",
    category: "security",
    name: "auditd",
    summary: "Kernel-level auditing of security events",
    description: "Enables the Linux audit daemon and the NixOS audit rules.",
    icon: "list.bullet.rectangle.portrait.fill",
    tint: "danger",
    tags: ["Hardening", "Audit"],
    services: ["auditd"],
    sizeMB: 12,
    nix: `security.auditd.enable = true;
security.audit.enable = true;`,
  }),
  option({
    id: "firejail",
    category: "security",
    name: "Firejail",
    summary: "Run untrusted apps in a sandbox",
    description: "Installs Firejail for ad-hoc sandboxing of desktop and CLI applications.",
    icon: "shield.checkered",
    tint: "warn",
    tags: ["Sandbox", "CLI"],
    packages: ["firejail"],
    sizeMB: 30,
  }),
  option({
    id: "gnupg",
    category: "security",
    name: "GnuPG & secrets",
    summary: "gpg, age, and sops",
    description: "Installs the standard tools for signing, encrypting, and managing secrets.",
    icon: "key.horizontal.fill",
    tint: "danger",
    tags: ["Crypto", "CLI"],
    packages: ["gnupg", "age", "sops"],
    sizeMB: 64,
  }),

  // ── Gaming ────────────────────────────────────────────────────────────────
  option({
    id: "steam",
    category: "gaming",
    name: "Steam",
    summary: "Steam and Proton for Linux gaming",
    description:
      "Enables Steam and the unfree package set. A virtualized GPU is required for anything beyond lightweight titles.",
    icon: "gamecontroller.fill",
    tint: "output",
    tags: ["Gaming", "GUI"],
    recommends: ["audio", "fonts"],
    unfree: true,
    services: ["Steam"],
    sizeMB: 2_100,
    nix: `programs.steam.enable = true;`,
  }),
  option({
    id: "minecraft",
    category: "gaming",
    name: "Minecraft server",
    summary: "A vanilla Java server on port 25565",
    description:
      "Runs the Minecraft server with the EULA accepted. Give it at least 4 GB of guest memory.",
    icon: "cube.fill",
    tint: "accent",
    tags: ["Server", "Gaming"],
    ports: [25565],
    services: ["Minecraft"],
    sizeMB: 420,
    nix: `services.minecraft-server = {
  enable = true;
  eula = true;
  openFirewall = true;
};`,
  }),
  option({
    id: "retroarch",
    category: "gaming",
    name: "RetroArch + Lutris",
    summary: "Emulation and game launchers",
    description: "Installs RetroArch and Lutris. ROMs and installers are up to you.",
    icon: "arcade.stick.console.fill",
    tint: "reasoning",
    tags: ["Gaming", "GUI"],
    recommends: ["audio", "fonts"],
    packages: ["retroarch", "lutris"],
    sizeMB: 760,
  }),
];

const OPTION_BY_ID = new Map(OPTIONS.map((entry) => [entry.id, entry]));
const CATEGORY_BY_ID = new Map(CATEGORIES.map((entry) => [entry.id, entry]));

export function optionById(id: string): CatalogOption | undefined {
  return OPTION_BY_ID.get(id);
}

export function categoryById(id: VMConfigCategoryID): VMConfigCategory | undefined {
  return CATEGORY_BY_ID.get(id);
}

export const TIMEZONES = [
  "UTC",
  "Europe/London",
  "Europe/Berlin",
  "Europe/Paris",
  "Europe/Amsterdam",
  "Europe/Madrid",
  "Europe/Rome",
  "Europe/Stockholm",
  "Europe/Oslo",
  "Europe/Helsinki",
  "Europe/Warsaw",
  "Europe/Prague",
  "Europe/Zurich",
  "Europe/Istanbul",
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "America/Toronto",
  "America/Vancouver",
  "America/Mexico_City",
  "America/Sao_Paulo",
  "America/Argentina/Buenos_Aires",
  "Asia/Tokyo",
  "Asia/Shanghai",
  "Asia/Hong_Kong",
  "Asia/Singapore",
  "Asia/Seoul",
  "Asia/Kolkata",
  "Asia/Dubai",
  "Asia/Tel_Aviv",
  "Africa/Cairo",
  "Africa/Johannesburg",
  "Australia/Sydney",
  "Australia/Melbourne",
  "Pacific/Auckland",
  "Pacific/Honolulu",
];

export const LOCALES = [
  "en_US.UTF-8",
  "en_GB.UTF-8",
  "en_CA.UTF-8",
  "en_AU.UTF-8",
  "de_DE.UTF-8",
  "fr_FR.UTF-8",
  "es_ES.UTF-8",
  "it_IT.UTF-8",
  "nl_NL.UTF-8",
  "sv_SE.UTF-8",
  "da_DK.UTF-8",
  "nb_NO.UTF-8",
  "fi_FI.UTF-8",
  "pl_PL.UTF-8",
  "pt_BR.UTF-8",
  "ja_JP.UTF-8",
  "ko_KR.UTF-8",
  "zh_CN.UTF-8",
];

export const KEYMAPS = [
  "us",
  "uk",
  "de",
  "fr",
  "es",
  "it",
  "nl",
  "se",
  "no",
  "dk",
  "fi",
  "pl",
  "pt",
  "br",
  "jp",
  "kr",
  "us-intl",
  "colemak",
  "dvorak",
];

export const SHELLS = ["bash", "zsh", "fish"] as const;

export const COMMON_GROUPS = [
  "wheel",
  "networkmanager",
  "video",
  "audio",
  "render",
  "input",
  "plugdev",
  "scanner",
  "lp",
  "kvm",
  "libvirtd",
  "docker",
  "podman",
  "dialout",
  "wireshark",
  "gamemode",
];

export const LIMITS = {
  maxUsers: 16,
  maxExtraPackages: 128,
  maxExtraConfigBytes: 16_000,
  maxPorts: 32,
};

export const PRESETS: VMConfigPreset[] = [
  {
    id: "minimal",
    name: "Minimal",
    summary: "A small, fast guest with the essentials",
    icon: "circle.dashed",
    tint: "running",
    options: ["zram"],
    tags: ["Fast", "Small"],
  },
  {
    id: "developer",
    name: "Developer",
    summary: "Editors, languages, Git, and Docker",
    icon: "hammer.fill",
    tint: "input",
    options: [
      "zram",
      "direnv",
      "nix-ld",
      "git-tools",
      "neovim",
      "vscode",
      "nodejs",
      "python",
      "rust",
      "cc",
      "tmux",
      "docker",
      "web-tools",
    ],
    tags: ["Popular", "Coding"],
  },
  {
    id: "homelab",
    name: "Homelab",
    summary: "Docker, Tailscale, Git, metrics, and dashboards",
    icon: "server.rack",
    tint: "accent",
    options: [
      "zram",
      "docker",
      "tailscale",
      "caddy",
      "gitea",
      "postgresql",
      "redis",
      "prometheus",
      "grafana",
      "netdata",
      "syncthing",
      "avahi",
      "fail2ban",
    ],
    tags: ["Self-hosted", "Infra"],
  },
  {
    id: "media",
    name: "Media",
    summary: "Jellyfin, music, SMB, and sync",
    icon: "play.rectangle.fill",
    tint: "warn",
    options: [
      "zram",
      "jellyfin",
      "navidrome",
      "samba",
      "syncthing",
      "tailscale",
      "avahi",
      "ffmpeg",
      "yt-dlp",
    ],
    tags: ["Movies", "Music"],
  },
  {
    id: "ai-lab",
    name: "AI Lab",
    summary: "Ollama, Open WebUI, notebooks, and data tools",
    icon: "sparkles",
    tint: "reasoning",
    options: [
      "zram",
      "ollama",
      "open-webui",
      "python",
      "jupyter",
      "databases",
      "glances",
    ],
    tags: ["LLM", "Notebooks"],
  },
  {
    id: "data-science",
    name: "Data Science",
    summary: "Python, Jupyter, databases, and a C toolchain",
    icon: "chart.xyaxis.line",
    tint: "cacheRead",
    options: ["zram", "python", "jupyter", "databases", "cc", "tmux", "glances"],
    tags: ["Python", "Analysis"],
  },
  {
    id: "web",
    name: "Web stack",
    summary: "Caddy, PostgreSQL, Redis, Node, and metrics",
    icon: "globe",
    tint: "output",
    options: [
      "zram",
      "caddy",
      "postgresql",
      "redis",
      "nodejs",
      "git-tools",
      "neovim",
      "prometheus",
      "glances",
    ],
    tags: ["Web", "Database"],
  },
  {
    id: "kubernetes",
    name: "Kubernetes",
    summary: "Docker, K3s, and the cluster CLI",
    icon: "helm",
    tint: "running",
    options: ["zram", "docker", "k3s", "kubernetes", "containers-tools", "tmux"],
    tags: ["K8s", "Infra"],
  },
  {
    id: "desktop",
    name: "Desktop",
    summary: "GNOME, audio, fonts, browser, and office",
    icon: "display",
    tint: "reasoning",
    options: [
      "zram",
      "gnome",
      "audio",
      "fonts",
      "firefox",
      "libreoffice",
      "vscode",
      "flatpak",
      "printing",
      "bluetooth",
      "vlc",
    ],
    tags: ["GUI", "Workstation"],
  },
  {
    id: "security",
    name: "Hardened",
    summary: "Fail2ban, AppArmor, auditd, ClamAV, and Tor",
    icon: "lock.shield.fill",
    tint: "danger",
    options: [
      "zram",
      "fail2ban",
      "clamav",
      "apparmor",
      "auditd",
      "firejail",
      "gnupg",
      "tor",
    ],
    tags: ["Hardening", "Privacy"],
  },
  {
    id: "gaming",
    name: "Gaming",
    summary: "Steam, emulators, audio, and fonts",
    icon: "gamecontroller.fill",
    tint: "output",
    options: ["zram", "audio", "fonts", "steam", "retroarch", "minecraft"],
    tags: ["Steam", "Emulation"],
  },
];

export const DEFAULT_SETTINGS: NixOSBuilderSettings = {
  timezone: "UTC",
  locale: "en_US.UTF-8",
  keymap: "us",
  firewall: true,
  passwordAuthentication: false,
  extraTCPPorts: [],
  extraUDPPorts: [],
};

export function defaultBuilderConfig(): NixOSBuilderConfig {
  return {
    version: 1,
    preset: null,
    enabled: [],
    settings: { ...DEFAULT_SETTINGS, extraTCPPorts: [], extraUDPPorts: [] },
    users: [],
    extraPackages: [],
    extraConfig: "",
  };
}

export function recommendedBuilderConfig(): NixOSBuilderConfig {
  const preset = PRESETS.find((entry) => entry.id === "developer") ?? PRESETS[0];
  return {
    ...defaultBuilderConfig(),
    preset: preset?.id ?? null,
    enabled: [...(preset?.options ?? ["zram"])],
  };
}

export function catalogForClient(): VMConfigCatalog {
  return {
    version: 1,
    categories: CATEGORIES,
    options: OPTIONS.map(({ nix: _nix, ...entry }) => entry),
    presets: PRESETS,
    defaults: defaultBuilderConfig(),
    recommendedPreset: "developer",
    shells: [...SHELLS],
    groups: COMMON_GROUPS,
    timezones: TIMEZONES,
    locales: LOCALES,
    keymaps: KEYMAPS,
    limits: LIMITS,
  };
}

const USER_NAME = /^[a-z_][a-z0-9_-]{0,31}$/;
const GROUP_NAME = /^[a-z_][a-z0-9_-]{0,31}$/;
const SSH_KEY = /^(ssh|ecdsa|sk-ssh|sk-ecdsa)-[A-Za-z0-9@._-]+ [A-Za-z0-9+/=]+/;
const RESERVED_USERS = new Set(["root", "opencodebar", "nobody", "daemon", "systemd-network"]);

function text(value: unknown, fallback: string, max: number): string {
  if (value === undefined || value === null) return fallback;
  if (typeof value !== "string") throw new VMValidationError("Expected a string");
  const trimmed = value.trim();
  if (!trimmed) return fallback;
  if (trimmed.length > max) throw new VMValidationError(`Keep this value to ${max} characters or fewer`);
  if (/[\u0000-\u001f\u007f]/.test(trimmed)) {
    throw new VMValidationError("Control characters are not supported here");
  }
  return trimmed;
}

function boolean(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function portList(value: unknown, label: string): number[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new VMValidationError(`${label} must be an array of ports`);
  if (value.length > LIMITS.maxPorts) {
    throw new VMValidationError(`Use ${LIMITS.maxPorts} ${label} or fewer`);
  }
  const unique = new Set<number>();
  for (const entry of value) {
    const port = typeof entry === "string" ? Number.parseInt(entry, 10) : entry;
    if (typeof port !== "number" || !Number.isInteger(port) || port < 1 || port > 65_535) {
      throw new VMValidationError(`${label} must contain TCP/UDP ports from 1 to 65535`);
    }
    unique.add(port);
  }
  return [...unique].sort((a, b) => a - b);
}

function userList(value: unknown): NixOSManagedUser[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new VMValidationError("Users must be an array");
  if (value.length > LIMITS.maxUsers) {
    throw new VMValidationError(`Use ${LIMITS.maxUsers} users or fewer`);
  }
  const seen = new Set<string>();
  return value.map((entry, index) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new VMValidationError(`User ${index + 1} is malformed`);
    }
    const source = entry as Record<string, unknown>;
    const name = typeof source.name === "string" ? source.name.trim().toLowerCase() : "";
    if (!USER_NAME.test(name)) {
      throw new VMValidationError(
        "User names must start with a lowercase letter or underscore and use a-z, 0-9, _ or -",
      );
    }
    if (RESERVED_USERS.has(name)) {
      throw new VMValidationError(`The user name ${name} is reserved`);
    }
    if (seen.has(name)) throw new VMValidationError(`The user ${name} is listed twice`);
    seen.add(name);

    const groups = source.groups === undefined || source.groups === null
      ? []
      : Array.isArray(source.groups)
        ? source.groups
        : (() => {
            throw new VMValidationError(`Groups for ${name} must be an array`);
          })();
    const normalizedGroups = new Set<string>();
    for (const group of groups) {
      if (typeof group !== "string" || !GROUP_NAME.test(group.trim())) {
        throw new VMValidationError(`Invalid group name for ${name}`);
      }
      normalizedGroups.add(group.trim());
    }

    const keys = source.sshKeys === undefined || source.sshKeys === null
      ? []
      : Array.isArray(source.sshKeys)
        ? source.sshKeys
        : (() => {
            throw new VMValidationError(`SSH keys for ${name} must be an array`);
          })();
    if (keys.length > 10) throw new VMValidationError(`Keep 10 SSH keys or fewer for ${name}`);
    const normalizedKeys: string[] = [];
    for (const key of keys) {
      if (typeof key !== "string") throw new VMValidationError(`SSH keys for ${name} must be strings`);
      const trimmed = key.trim();
      if (!trimmed) continue;
      if (trimmed.length > 4_096 || !SSH_KEY.test(trimmed)) {
        throw new VMValidationError(`“${trimmed.slice(0, 24)}…” is not an OpenSSH public key`);
      }
      normalizedKeys.push(trimmed);
    }

    const shell = source.shell === undefined ? "bash" : source.shell;
    if (shell !== "bash" && shell !== "zsh" && shell !== "fish") {
      throw new VMValidationError(`Choose bash, zsh, or fish as the shell for ${name}`);
    }

    return {
      name,
      description: text(source.description, name, 80),
      groups: [...normalizedGroups],
      shell,
      sshKeys: normalizedKeys,
      passwordlessSudo: boolean(source.passwordlessSudo, false),
      createHome: boolean(source.createHome, true),
    };
  });
}

function settingObject(value: unknown): Record<string, unknown> {
  if (value === undefined || value === null) return {};
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new VMValidationError("settings must be an object");
  }
  return value as Record<string, unknown>;
}

/**
 * Validates and normalizes a builder config from the API or from disk. Unknown
 * option ids are rejected so a typo never produces a half-configured guest.
 * Pass `lenient` when reading an older definition so an option removed from the
 * catalog does not make the whole VM disappear.
 */
export function normalizeBuilderConfig(value: unknown, lenient = false): NixOSBuilderConfig {
  if (value === undefined || value === null) return defaultBuilderConfig();
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new VMValidationError("The configuration must be an object");
  }
  const source = value as Record<string, unknown>;
  const settings = settingObject(source.settings);

  const enabled: string[] = [];
  if (source.enabled !== undefined && source.enabled !== null) {
    if (!Array.isArray(source.enabled)) {
      throw new VMValidationError("enabled must be an array of option ids");
    }
    for (const entry of source.enabled) {
      if (typeof entry !== "string") throw new VMValidationError("enabled must contain option ids");
      const id = entry.trim();
      if (!id) continue;
      const option = OPTION_BY_ID.get(id);
      if (!option) {
        if (lenient) continue;
        throw new VMValidationError(`Unknown configuration option: ${id}`);
      }
      if (!option.locked && !enabled.includes(id)) enabled.push(id);
    }
  }

  const preset = typeof source.preset === "string" && PRESETS.some((entry) => entry.id === source.preset)
    ? source.preset
    : null;

  const timezone = text(settings.timezone, DEFAULT_SETTINGS.timezone, 64);
  if (!/^[A-Za-z][A-Za-z0-9_+-]*(?:\/[A-Za-z0-9_+-]+)*$/.test(timezone)) {
    throw new VMValidationError("Choose a time zone such as UTC or Europe/Berlin");
  }
  const locale = text(settings.locale, DEFAULT_SETTINGS.locale, 40);
  if (!/^[a-z]{2,3}_[A-Z]{2}\.UTF-8$/.test(locale)) {
    throw new VMValidationError("Choose a locale such as en_US.UTF-8");
  }
  const keymap = text(settings.keymap, DEFAULT_SETTINGS.keymap, 24);
  if (!/^[a-z0-9-]+$/.test(keymap)) {
    throw new VMValidationError("Choose a keyboard layout such as us or de");
  }

  const extraConfig = typeof source.extraConfig === "string" ? source.extraConfig : "";
  if (extraConfig.length > LIMITS.maxExtraConfigBytes) {
    throw new VMValidationError(
      `Keep custom Nix to ${Math.round(LIMITS.maxExtraConfigBytes / 1_000)} KB or less`,
    );
  }
  if (extraConfig.includes("\u0000")) throw new VMValidationError("Custom Nix contains a NUL byte");

  const extraPackages = normalizePackages(source.extraPackages);
  if (extraPackages.length > LIMITS.maxExtraPackages) {
    throw new VMValidationError(`Use ${LIMITS.maxExtraPackages} extra packages or fewer`);
  }

  return {
    version: 1,
    preset,
    enabled,
    settings: {
      timezone,
      locale,
      keymap,
      firewall: boolean(settings.firewall, DEFAULT_SETTINGS.firewall),
      passwordAuthentication: boolean(
        settings.passwordAuthentication,
        DEFAULT_SETTINGS.passwordAuthentication,
      ),
      extraTCPPorts: portList(settings.extraTCPPorts, "TCP ports"),
      extraUDPPorts: portList(settings.extraUDPPorts, "UDP ports"),
    },
    users: userList(source.users),
    extraPackages,
    extraConfig,
  };
}

export interface ResolvedBuilderConfig {
  config: NixOSBuilderConfig;
  /** Ids added because another enabled option requires them. */
  added: string[];
  packages: string[];
  services: string[];
  ports: number[];
  warnings: string[];
  sizeMB: number;
  unfree: boolean;
  /** Enabled catalog options in catalog order, excluding locked options. */
  options: CatalogOption[];
}

/**
 * Expands requirements, checks conflicts, and flattens every enabled option
 * into the package, service, and port lists the UI shows in its build plan.
 */
export function resolveBuilderConfig(config: NixOSBuilderConfig): ResolvedBuilderConfig {
  const enabled = new Set(config.enabled.filter((id) => {
    const option = OPTION_BY_ID.get(id);
    return option !== undefined && !option.locked;
  }));
  const added: string[] = [];

  // Expand requirements breadth-first so nested dependencies appear too.
  const queue = [...enabled];
  while (queue.length > 0) {
    const id = queue.shift()!;
    const entry = OPTION_BY_ID.get(id);
    if (!entry) continue;
    for (const requirement of entry.requires) {
      if (enabled.has(requirement)) continue;
      const required = OPTION_BY_ID.get(requirement);
      if (!required) continue;
      enabled.add(requirement);
      added.push(requirement);
      queue.push(requirement);
    }
  }

  const options = OPTIONS.filter((entry) => enabled.has(entry.id) && !entry.locked);
  const conflicts = new Map<string, string>();
  for (const entry of options) {
    for (const other of entry.conflicts) {
      if (enabled.has(other)) {
        conflicts.set(entry.id, other);
        conflicts.set(other, entry.id);
      }
    }
  }
  if (conflicts.size > 0) {
    const [left, right] = [...conflicts.entries()][0]!;
    const leftName = OPTION_BY_ID.get(left)?.name ?? left;
    const rightName = OPTION_BY_ID.get(right)?.name ?? right;
    throw new VMValidationError(`${leftName} cannot be combined with ${rightName}`);
  }

  const packages = effectivePackages(
    DEFAULT_PACKAGES,
    config.extraPackages,
    ...options.map((entry) => entry.packages),
  ).sort((a, b) => a.localeCompare(b));

  const services = [...new Set(options.flatMap((entry) => entry.services))];
  const ports = [
    ...new Set([
      ...config.settings.extraTCPPorts,
      ...config.settings.extraUDPPorts,
      ...options.flatMap((entry) => entry.ports),
    ]),
  ].sort((a, b) => a - b);

  const warnings: string[] = [];
  const desktop = options.find((entry) =>
    ["gnome", "kde", "xfce", "hyprland"].includes(entry.id),
  );
  if (desktop) {
    warnings.push(`${desktop.name} needs at least 4 GB of guest memory for a smooth session.`);
  }
  if (options.some((entry) => entry.id === "ollama")) {
    warnings.push("Local models need RAM and disk. Start with a 3B model or smaller.");
  }
  if (config.settings.passwordAuthentication) {
    warnings.push(
      "SSH password authentication is on, but managed users have no passwords yet. Set one from the serial console.",
    );
  }
  if (config.users.some((user) => user.passwordlessSudo && !user.groups.includes("wheel"))) {
    warnings.push("A non-wheel user has passwordless sudo. Review that rule before exposing the guest.");
  }

  const sizeMB = 1_024 + options.reduce((total, entry) => total + entry.sizeMB, 0);

  return {
    config: { ...config, enabled: [...enabled] },
    added,
    packages,
    services,
    ports,
    warnings,
    sizeMB,
    unfree: options.some((entry) => entry.unfree),
    options,
  };
}

export function optionCount(config: NixOSBuilderConfig): number {
  return config.enabled.filter((id) => {
    const entry = OPTION_BY_ID.get(id);
    return entry !== undefined && !entry.locked;
  }).length;
}
