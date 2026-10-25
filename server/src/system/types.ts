import type {
  SystemApp,
  SystemCPU,
  SystemDisplayGroup,
  SystemHomebrew,
  SystemHost,
  SystemMemory,
  SystemRuntime,
  SystemSecurity,
} from "../types.ts";

export interface CommandResult {
  ok: boolean;
  stdout: string;
  stderr: string;
}

export type CommandRunner = (
  command: string,
  args: string[],
  timeoutMs?: number,
  env?: NodeJS.ProcessEnv,
) => Promise<CommandResult>;

export interface SystemInfoOptions {
  runner?: CommandRunner;
  /** How long the expensive, rarely changing collectors stay cached. */
  staticTTLMs?: number;
  /** How long a complete snapshot is reused between clients. */
  cacheTTLMs?: number;
  hub?: () => {
    startedAt: number;
    port?: number;
    dbPath?: string;
  };
}

export interface StaticInfo {
  host: Partial<SystemHost>;
  cpu: Partial<SystemCPU>;
  memory: Partial<SystemMemory>;
  apps: SystemApp[];
  homebrew: SystemHomebrew | null;
  runtimes: SystemRuntime[];
  displays: SystemDisplayGroup[];
  security: SystemSecurity | null;
}
