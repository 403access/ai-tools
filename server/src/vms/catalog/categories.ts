import type { VMConfigCategory, VMConfigCategoryID } from "../types.ts";

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

const CATEGORY_BY_ID = new Map(CATEGORIES.map((entry) => [entry.id, entry]));

export function categoryById(id: VMConfigCategoryID): VMConfigCategory | undefined {
  return CATEGORY_BY_ID.get(id);
}
