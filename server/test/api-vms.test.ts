import { describe, expect, test } from "bun:test";
import { VMValidationError } from "../src/vms/nixos.ts";
import { defaultBuilderConfig } from "../src/vms/catalog.ts";
import type {
  VMAction,
  VMCapabilities,
  VMCreateInput,
  VMLog,
  VMLogType,
  VMSetupJob,
  VMSetupStep,
  VMUpdateInput,
  VirtualMachine,
  VirtualMachineStore,
} from "../src/vms/types.ts";
import { body, request, setup } from "./helpers/api.ts";

function vm(overrides: Partial<VirtualMachine> = {}): VirtualMachine {
  return {
    id: "vm_abcdef123456",
    name: "NixOS",
    distro: "nixos",
    channel: "nixos-26.05",
    stateVersion: "26.05",
    arch: "aarch64",
    status: "stopped",
    createdAt: 1,
    updatedAt: 1,
    cpuCount: 2,
    memoryMB: 2048,
    diskGB: 12,
    packages: [],
    pendingPackages: [],
    pendingConfig: false,
    config: defaultBuilderConfig(),
    lastError: null,
    progress: null,
    ssh: { user: "opencodebar", keyPath: "/tmp/key", publicKey: "ssh-ed25519 AAAA" },
    network: { mac: "52:54:00:00:00:01", ip: null, reachable: false },
    paths: {
      directory: "/tmp/vm",
      disk: "/tmp/vm/disk.raw",
      configuration: "/tmp/vm/configuration.nix",
      flake: "/tmp/vm/flake.nix",
      serialLog: "/tmp/vm/serial.log",
      buildLog: "/tmp/vm/build.log",
      applyLog: "/tmp/vm/apply.log",
      runtime: "/tmp/vm/runtime.json",
    },
    metrics: null,
    ...overrides,
  };
}

function capabilities(): VMCapabilities {
  return {
    supported: true,
    platform: "darwin",
    arch: "arm64",
    helperPath: "/tmp/OpenCodeBarVZ",
    helperAvailable: true,
    helperEntitled: true,
    nixPath: "/nix/bin/nix",
    nixAvailable: true,
    nixVersion: "nix (Nix) 2.28.3",
    linuxBuilder: true,
    linuxBuilderDetail: null,
    storageDir: "/tmp/vms",
    defaultChannel: "nixos-26.05",
    defaultCPU: 4,
    defaultMemoryMB: 4096,
    maxCPU: 7,
    maxMemoryMB: 8192,
    notes: [],
  };
}

interface Calls {
  created: VMCreateInput[];
  updated: Array<{ id: string; input: VMUpdateInput }>;
  controlled: Array<{ id: string; action: VMAction; force: boolean }>;
  removed: Array<{ id: string; force: boolean }>;
  logs: Array<{ id: string; type: VMLogType; tail: number }>;
  setups: VMSetupStep[];
  cancelled: number;
  setupLogs: Array<{ step: VMSetupStep; tail: number }>;
}

function setupJob(step: VMSetupStep): VMSetupJob {
  return {
    step,
    status: "running",
    command: step === "nix" ? "curl -fsSL https://nixos.org/nix/install | sh -s -- --yes" : "make vz-helper",
    requiresAdmin: step === "nix",
    startedAt: 1,
    finishedAt: null,
    exitCode: null,
    error: null,
    log: { path: "/tmp/setup.log", lines: [], bytes: 0, truncated: false },
  };
}

function fakeStore(items: VirtualMachine[], calls: Calls): VirtualMachineStore {
  return {
    async list() {
      return items;
    },
    async capabilities() {
      return capabilities();
    },
    async get(id) {
      return items.find((entry) => entry.id === id) ?? null;
    },
    async create(input) {
      calls.created.push(input);
      const next = vm({ id: "vm_created", name: input.name });
      items.unshift(next);
      return next;
    },
    async control(id, action, force = false) {
      calls.controlled.push({ id, action, force });
      return items.find((entry) => entry.id === id) ?? vm();
    },
    async update(id, input) {
      calls.updated.push({ id, input });
      const base = items.find((entry) => entry.id === id) ?? vm();
      return {
        ...base,
        name: input.name ?? base.name,
        cpuCount: input.cpuCount ?? base.cpuCount,
        memoryMB: input.memoryMB ?? base.memoryMB,
        packages: input.packages ?? base.packages,
        config: (input.config as VirtualMachine["config"] | undefined) ?? base.config,
      };
    },
    async remove(id, force = false) {
      calls.removed.push({ id, force });
    },
    async log(id, type, tail = 240): Promise<VMLog> {
      calls.logs.push({ id, type, tail });
      return { type, path: "/tmp/log", lines: ["line"], bytes: 4, truncated: false };
    },
    async consoleTarget(id) {
      return { vmID: id, host: "127.0.0.1", port: 4321 };
    },
    async setupStatus() {
      return null;
    },
    async startSetup(step) {
      calls.setups.push(step);
      return setupJob(step);
    },
    async cancelSetup() {
      calls.cancelled += 1;
      return null;
    },
    async setupLogs() {
      return [];
    },
    async setupLog(step, tail = 240) {
      calls.setupLogs.push({ step, tail });
      return { step, path: "/tmp/setup.log", lines: ["line"], bytes: 5, truncated: false };
    },
  };
}

function emptyCalls(): Calls {
  return {
    created: [],
    updated: [],
    controlled: [],
    removed: [],
    logs: [],
    setups: [],
    cancelled: 0,
    setupLogs: [],
  };
}

describe("virtual machine API", () => {
  test("lists VMs and reports host capabilities", async () => {
    const calls = emptyCalls();
    const { handler } = setup({}, { vms: fakeStore([vm()], calls) });

    const list = await body<{ data: VirtualMachine[] }>(
      await handler(request("/api/vms")),
    );
    expect(list.data.map((entry) => entry.id)).toEqual(["vm_abcdef123456"]);

    const caps = await body<{ data: VMCapabilities }>(
      await handler(request("/api/vms/capabilities")),
    );
    expect(caps.data.linuxBuilder).toBe(true);
    expect(caps.data.defaultChannel).toBe("nixos-26.05");
  });

  test("creates with validated fields", async () => {
    const calls = emptyCalls();
    const { handler } = setup({}, { vms: fakeStore([], calls) });

    const created = await handler(
      request("/api/vms", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: "Build box",
          cpuCount: 4,
          memoryMB: 4096,
          diskGB: 20,
          channel: "nixos-26.05",
          packages: ["nodejs", "ripgrep"],
          autostart: false,
        }),
      }),
    );
    expect(created.status).toBe(201);
    const payload = await body<{ data: VirtualMachine }>(created);
    expect(payload.data.id).toBe("vm_created");
    expect(calls.created[0]).toMatchObject({
      name: "Build box",
      cpuCount: 4,
      memoryMB: 4096,
      diskGB: 20,
      packages: ["nodejs", "ripgrep"],
      autostart: false,
    });
  });

  test("rejects malformed create and update bodies", async () => {
    const calls = emptyCalls();
    const { handler } = setup({}, { vms: fakeStore([vm()], calls) });

    const noName = await handler(
      request("/api/vms", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ cpuCount: 2 }),
      }),
    );
    expect(noName.status).toBe(400);

    const badPackages = await handler(
      request("/api/vms", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: "X", packages: [1, 2] }),
      }),
    );
    expect(badPackages.status).toBe(400);

    const badUpdate = await handler(
      request("/api/vms/vm_abcdef123456", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      }),
    );
    expect(badUpdate.status).toBe(400);
  });

  test("updates packages and controls lifecycle actions", async () => {
    const calls = emptyCalls();
    const { handler } = setup({}, { vms: fakeStore([vm()], calls) });

    const update = await handler(
      request("/api/vms/vm_abcdef123456", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ packages: ["nodejs"] }),
      }),
    );
    expect(update.status).toBe(200);
    expect(calls.updated[0]?.input.packages).toEqual(["nodejs"]);

    const start = await handler(
      request("/api/vms/vm_abcdef123456/start", { method: "POST" }),
    );
    expect(start.status).toBe(200);
    expect(calls.controlled[0]).toEqual({
      id: "vm_abcdef123456",
      action: "start",
      force: false,
    });

    const rebuild = await handler(
      request("/api/vms/vm_abcdef123456/rebuild?force=1", { method: "POST" }),
    );
    expect(rebuild.status).toBe(200);
    expect(calls.controlled[1]).toEqual({
      id: "vm_abcdef123456",
      action: "rebuild",
      force: true,
    });

    const unknown = await handler(
      request("/api/vms/vm_abcdef123456/frobnicate", { method: "POST" }),
    );
    expect(unknown.status).toBe(404);
  });

  test("serves logs, deletes with force, and maps service errors", async () => {
    const calls = emptyCalls();
    const items = [vm()];
    const store = fakeStore(items, calls);
    const { handler } = setup({}, { vms: store });

    const log = await handler(
      request("/api/vms/vm_abcdef123456/log?type=serial&tail=10"),
    );
    expect(log.status).toBe(200);
    expect(calls.logs[0]).toEqual({
      id: "vm_abcdef123456",
      type: "serial",
      tail: 10,
    });

    const badType = await handler(
      request("/api/vms/vm_abcdef123456/log?type=shell"),
    );
    expect(badType.status).toBe(400);

    const deleted = await handler(
      request("/api/vms/vm_abcdef123456?force=1", { method: "DELETE" }),
    );
    expect(deleted.status).toBe(200);
    expect(calls.removed[0]).toEqual({ id: "vm_abcdef123456", force: true });

    const failing = setup(
      {},
      {
        vms: {
          ...store,
          async get() {
            throw new VMValidationError("Virtual machine not found", 404);
          },
          async control() {
            throw new VMValidationError("Stop the VM first", 409);
          },
        },
      },
    );
    const missing = await failing.handler(
      request("/api/vms/vm_missing"),
    );
    expect(missing.status).toBe(404);

    const conflict = await failing.handler(
      request("/api/vms/vm_abcdef123456/start", { method: "POST" }),
    );
    expect(conflict.status).toBe(409);
  });

  test("runs and reports fixed host setup steps", async () => {
    const calls = emptyCalls();
    const { handler } = setup({}, { vms: fakeStore([], calls) });

    const idle = await handler(request("/api/vms/setup"));
    expect(idle.status).toBe(200);
    expect(await body<{ data: VMSetupJob | null }>(idle)).toEqual({ data: null });

    const start = await handler(
      request("/api/vms/setup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ step: "nix" }),
      }),
    );
    expect(start.status).toBe(202);
    const job = await body<{ data: VMSetupJob }>(start);
    expect(job.data.step).toBe("nix");
    expect(job.data.requiresAdmin).toBe(true);
    expect(calls.setups).toEqual(["nix"]);

    const invalid = await handler(
      request("/api/vms/setup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ step: "rm -rf /" }),
      }),
    );
    expect(invalid.status).toBe(400);

    const cancel = await handler(request("/api/vms/setup/cancel", { method: "POST" }));
    expect(cancel.status).toBe(200);
    expect(calls.cancelled).toBe(1);
  });

  test("serves setup log history and tails", async () => {
    const calls = emptyCalls();
    const { handler } = setup({}, { vms: fakeStore([], calls) });

    const files = await handler(request("/api/vms/setup/logs"));
    expect(files.status).toBe(200);
    expect(await body<{ data: unknown[] }>(files)).toEqual({ data: [] });

    const log = await handler(request("/api/vms/setup/log?step=nix&tail=10"));
    expect(log.status).toBe(200);
    const payload = await body<{
      data: { step: string; path: string; lines: string[] };
    }>(log);
    expect(payload.data.step).toBe("nix");
    expect(payload.data.lines).toEqual(["line"]);
    expect(calls.setupLogs).toEqual([{ step: "nix", tail: 10 }]);

    const builder = await handler(request("/api/vms/setup/log?step=builder"));
    expect(builder.status).toBe(200);
    expect(calls.setupLogs.at(-1)).toEqual({ step: "builder", tail: 240 });

    const invalid = await handler(request("/api/vms/setup/log?step=shell"));
    expect(invalid.status).toBe(400);
  });

  test("serves the builder catalog and previews draft and existing configurations", async () => {
    const calls = emptyCalls();
    const { handler } = setup({}, { vms: fakeStore([vm()], calls) });

    const catalog = await handler(request("/api/vms/catalog"));
    expect(catalog.status).toBe(200);
    const catalogBody = await body<{
      data: { options: Array<{ id: string; nix?: string }>; presets: Array<{ id: string }> };
    }>(catalog);
    expect(catalogBody.data.options.some((entry) => entry.id === "docker")).toBe(true);
    expect(catalogBody.data.options[0]?.nix).toBeUndefined();
    expect(catalogBody.data.presets.some((entry) => entry.id === "developer")).toBe(true);

    const draft = await handler(
      request("/api/vms/preview", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: "Draft",
          config: { enabled: ["jupyter"], users: [], settings: {}, extraPackages: [] },
        }),
      }),
    );
    expect(draft.status).toBe(200);
    const draftBody = await body<{
      data: { configuration: string; added: string[]; packages: string[] };
    }>(draft);
    expect(draftBody.data.configuration).toContain("system.stateVersion");
    expect(draftBody.data.added).toContain("python");
    expect(draftBody.data.packages).toContain("python3Packages.jupyterlab");

    const preview = await handler(
      request("/api/vms/vm_abcdef123456/preview", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ config: { enabled: ["docker"] } }),
      }),
    );
    expect(preview.status).toBe(200);
    const previewBody = await body<{ data: { configuration: string; services: string[] } }>(
      preview,
    );
    expect(previewBody.data.configuration).toContain("virtualisation.docker");
    expect(previewBody.data.services).toContain("Docker Engine");

    const missing = await handler(
      request("/api/vms/vm_missing/preview", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      }),
    );
    expect(missing.status).toBe(404);

    const invalid = await handler(
      request("/api/vms/preview", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ config: { enabled: ["not-a-real-option"] } }),
      }),
    );
    expect(invalid.status).toBe(400);
  });

  test("accepts builder configurations on create and update", async () => {
    const calls = emptyCalls();
    const { handler } = setup({}, { vms: fakeStore([vm()], calls) });
    const config = {
      enabled: ["docker", "tailscale"],
      users: [
        {
          name: "alice",
          groups: ["docker"],
          shell: "zsh",
          sshKeys: [],
          passwordlessSudo: false,
          createHome: true,
        },
      ],
      extraPackages: ["ripgrep"],
    };

    const created = await handler(
      request("/api/vms", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: "Builder", config }),
      }),
    );
    expect(created.status).toBe(201);
    expect(calls.created[0]?.config).toMatchObject({ enabled: ["docker", "tailscale"] });

    const updated = await handler(
      request("/api/vms/vm_abcdef123456", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ config }),
      }),
    );
    expect(updated.status).toBe(200);
    expect(calls.updated[0]?.input.config).toMatchObject({ enabled: ["docker", "tailscale"] });

    const invalid = await handler(
      request("/api/vms", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: "Builder", config: "nope" }),
      }),
    );
    expect(invalid.status).toBe(400);
  });

  test("requires the hub token", async () => {
    const calls = emptyCalls();
    const { handler } = setup({}, { vms: fakeStore([vm()], calls) });
    const unauthorized = await handler(request("/api/vms", {}, null));
    expect(unauthorized.status).toBe(401);
  });
});
