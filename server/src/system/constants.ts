import type { SystemRuntime } from "../types.ts";

export const DEFAULT_STATIC_TTL_MS = 5 * 60_000;
export const DEFAULT_CACHE_TTL_MS = 2_000;
export const COMMAND_TIMEOUT_MS = 5_000;
export const LONG_COMMAND_TIMEOUT_MS = 20_000;

export const APP_DIRECTORIES = [
  "/Applications",
  "/Applications/Utilities",
  "/System/Applications",
  "/System/Applications/Utilities",
  "/System/Library/CoreServices/Applications",
];

export const TOOL_COMMANDS: Array<{
  name: string;
  command: string;
  args: string[];
  kind: SystemRuntime["kind"];
}> = [
  { name: "Node.js", command: "node", args: ["--version"], kind: "runtime" },
  { name: "Bun", command: "bun", args: ["--version"], kind: "runtime" },
  { name: "Deno", command: "deno", args: ["--version"], kind: "runtime" },
  { name: "Python", command: "python3", args: ["--version"], kind: "runtime" },
  { name: "pip", command: "pip3", args: ["--version"], kind: "tool" },
  { name: "Go", command: "go", args: ["version"], kind: "runtime" },
  { name: "Rust", command: "rustc", args: ["--version"], kind: "runtime" },
  { name: "Cargo", command: "cargo", args: ["--version"], kind: "tool" },
  { name: "Java", command: "java", args: ["-version"], kind: "runtime" },
  { name: "Swift", command: "swift", args: ["--version"], kind: "runtime" },
  { name: "Ruby", command: "ruby", args: ["--version"], kind: "runtime" },
  { name: "PHP", command: "php", args: ["--version"], kind: "runtime" },
  { name: "Git", command: "git", args: ["--version"], kind: "tool" },
  { name: "npm", command: "npm", args: ["--version"], kind: "tool" },
  { name: "pnpm", command: "pnpm", args: ["--version"], kind: "tool" },
  { name: "Yarn", command: "yarn", args: ["--version"], kind: "tool" },
  { name: "Docker", command: "docker", args: ["--version"], kind: "tool" },
  { name: "kubectl", command: "kubectl", args: ["version", "--client"], kind: "tool" },
  { name: "GitHub CLI", command: "gh", args: ["--version"], kind: "tool" },
  { name: "Clang", command: "clang", args: ["--version"], kind: "tool" },
  { name: "CMake", command: "cmake", args: ["--version"], kind: "tool" },
  { name: "Make", command: "make", args: ["--version"], kind: "tool" },
  { name: "SQLite", command: "sqlite3", args: ["--version"], kind: "tool" },
  { name: "FFmpeg", command: "ffmpeg", args: ["-version"], kind: "tool" },
  { name: "Terraform", command: "terraform", args: ["version"], kind: "tool" },
  { name: "AWS CLI", command: "aws", args: ["--version"], kind: "tool" },
  { name: "Google Cloud", command: "gcloud", args: ["--version"], kind: "tool" },
];
