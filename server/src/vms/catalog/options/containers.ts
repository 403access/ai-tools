/**
 * Containers catalog options.
 */

import { option } from "../option.ts";
import type { CatalogOption } from "../types.ts";

export const CONTAINER_OPTIONS: CatalogOption[] = [
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
];
