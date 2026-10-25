import { describe, expect, test } from "bun:test";
import { VMValidationError } from "../src/vms/nixos.ts";
import type {
  VMAction,
  VMCapabilities,
  VMCreateInput,
  VMLog,
  VMLogType,
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
      return { ...(items.find((entry) => entry.id === id) ?? vm()), ...input };
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
  };
}

function emptyCalls(): Calls {
  return { created: [], updated: [], controlled: [], removed: [], logs: [] };
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

  test("requires the hub token", async () => {
    const calls = emptyCalls();
    const { handler } = setup({}, { vms: fakeStore([vm()], calls) });
    const unauthorized = await handler(request("/api/vms", {}, null));
    expect(unauthorized.status).toBe(401);
  });
});
