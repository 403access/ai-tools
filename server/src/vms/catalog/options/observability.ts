/**
 * Monitoring catalog options.
 */

import { option } from "../option.ts";
import type { CatalogOption } from "../types.ts";

export const OBSERVABILITY_OPTIONS: CatalogOption[] = [
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
];
