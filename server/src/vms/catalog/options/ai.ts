/**
 * AI catalog options.
 */

import { option } from "../option.ts";
import type { CatalogOption } from "../types.ts";

export const AI_OPTIONS: CatalogOption[] = [
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
];
