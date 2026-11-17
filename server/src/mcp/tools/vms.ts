import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { readSocket } from "../websocket.ts";
import type { ToolContext } from "./common.ts";
import { describeError, failure, jsonText, queryString, text } from "./common.ts";

const READ_ONLY = { readOnlyHint: true, openWorldHint: false } as const;
const WRITE = { readOnlyHint: false, openWorldHint: false } as const;

const VM_ACTION = z.enum([
  "start",
  "stop",
  "restart",
  "pause",
  "resume",
  "rebuild",
  "apply",
]);

const VM_CONFIG = z
  .record(z.string(), z.unknown())
  .describe("Full NixOS builder configuration. Use get_vm_catalog to discover option ids.");

function vmPath(id: string): string {
  return `/api/vms/${encodeURIComponent(id.trim())}`;
}

export function registerVMTools(server: McpServer, context: ToolContext): void {
  server.registerTool(
    "list_vms",
    {
      title: "List virtual machines",
      description:
        "List the NixOS virtual machines defined on the hub host, with their status, resources, progress, network, and metrics.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/vms"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_vm",
    {
      title: "Get a virtual machine",
      description:
        "Read one virtual machine's definition, status, progress, SSH details, network, and latest metrics.",
      inputSchema: {
        vm: z.string().describe("Virtual machine id."),
        refresh: z.boolean().optional().describe("Collect fresh guest metrics."),
      },
      annotations: READ_ONLY,
    },
    async ({ vm, refresh }) => {
      try {
        return jsonText(
          await context.client().get(`${vmPath(vm)}${queryString({ refresh: refresh ? 1 : undefined })}`),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "create_vm",
    {
      title: "Create a NixOS virtual machine",
      description:
        "Define a declarative NixOS guest with CPU, memory, disk, channel, packages, and an optional builder configuration. " +
        "The hub builds the image and boots it when autostart is on.",
      inputSchema: {
        name: z.string().describe("Display name for the VM."),
        cpuCount: z.number().int().positive().optional().describe("Virtual CPU count."),
        memoryMB: z.number().int().positive().optional().describe("Memory in megabytes."),
        diskGB: z.number().int().positive().optional().describe("Disk size in gigabytes."),
        channel: z.string().optional().describe("NixOS channel, for example nixos-26.05."),
        packages: z.array(z.string()).optional().describe("Extra nixpkgs attributes."),
        config: VM_CONFIG.optional(),
        autostart: z
          .boolean()
          .optional()
          .describe("Boot as soon as the image is ready. Defaults to true."),
      },
      annotations: { readOnlyHint: false, openWorldHint: true },
    },
    async ({ name, cpuCount, memoryMB, diskGB, channel, packages, config, autostart }) => {
      try {
        return jsonText(
          await context.client().post("/api/vms", {
            name,
            ...(cpuCount !== undefined ? { cpuCount } : {}),
            ...(memoryMB !== undefined ? { memoryMB } : {}),
            ...(diskGB !== undefined ? { diskGB } : {}),
            ...(channel ? { channel } : {}),
            ...(packages?.length ? { packages } : {}),
            ...(config ? { config } : {}),
            ...(autostart !== undefined ? { autostart } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "update_vm",
    {
      title: "Update a virtual machine",
      description:
        "Rename a VM, change CPU/memory, replace its package list, or update its builder configuration.",
      inputSchema: {
        vm: z.string().describe("Virtual machine id."),
        name: z.string().optional().describe("New display name."),
        cpuCount: z.number().int().positive().optional().describe("Virtual CPU count."),
        memoryMB: z.number().int().positive().optional().describe("Memory in megabytes."),
        packages: z.array(z.string()).optional().describe("Replacement package list."),
        config: VM_CONFIG.optional(),
      },
      annotations: WRITE,
    },
    async ({ vm, name, cpuCount, memoryMB, packages, config }) => {
      if (
        name === undefined &&
        cpuCount === undefined &&
        memoryMB === undefined &&
        packages === undefined &&
        config === undefined
      ) {
        return failure("Provide name, cpuCount, memoryMB, packages, or config.");
      }
      try {
        return jsonText(
          await context.client().patch(vmPath(vm), {
            ...(name !== undefined ? { name } : {}),
            ...(cpuCount !== undefined ? { cpuCount } : {}),
            ...(memoryMB !== undefined ? { memoryMB } : {}),
            ...(packages !== undefined ? { packages } : {}),
            ...(config !== undefined ? { config } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "remove_vm",
    {
      title: "Remove a virtual machine",
      description:
        "Delete a VM definition and its disk image. Running guests must be stopped first unless force is set.",
      inputSchema: {
        vm: z.string().describe("Virtual machine id."),
        force: z.boolean().optional().describe("Stop and remove even when the guest is running."),
      },
      annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: false },
    },
    async ({ vm, force }) => {
      try {
        await context.client().delete(`${vmPath(vm)}${queryString({ force: force ? 1 : undefined })}`);
        return text(`Removed virtual machine ${vm.trim()}.`);
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "control_vm",
    {
      title: "Control a virtual machine",
      description:
        "Start, stop, restart, pause, resume, rebuild, or apply package/config changes to a VM.",
      inputSchema: {
        vm: z.string().describe("Virtual machine id."),
        action: VM_ACTION,
        force: z.boolean().optional().describe("Force the operation, for example a hard stop."),
      },
      annotations: WRITE,
    },
    async ({ vm, action, force }) => {
      try {
        return jsonText(
          await context.client().post(`${vmPath(vm)}/${action}`, {
            ...(force !== undefined ? { force } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_vm_capabilities",
    {
      title: "Get VM host capabilities",
      description:
        "Check whether the VZ helper, Nix, and an aarch64-linux builder are ready on the hub host, with setup notes.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/vms/capabilities"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_vm_catalog",
    {
      title: "Get the NixOS configuration catalog",
      description:
        "List every builder category, option, preset, and default used by the VM configuration builder.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/vms/catalog"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "preview_vm",
    {
      title: "Preview a NixOS configuration",
      description:
        "Render configuration.nix, the flake, packages, services, ports, and warnings for a draft configuration, " +
        "or for an existing VM when `vm` is passed.",
      inputSchema: {
        vm: z.string().optional().describe("Existing VM id to preview against."),
        config: VM_CONFIG.optional(),
        packages: z.array(z.string()).optional().describe("Additional packages."),
        name: z.string().optional().describe("Draft VM name."),
        diskGB: z.number().int().positive().optional().describe("Draft disk size."),
        channel: z.string().optional().describe("Draft NixOS channel."),
      },
      annotations: READ_ONLY,
    },
    async ({ vm, config, packages, name, diskGB, channel }) => {
      try {
        const client = context.client();
        if (vm?.trim()) {
          return jsonText(
            await client.post(`${vmPath(vm)}/preview`, {
              ...(config ? { config } : {}),
              ...(packages ? { packages } : {}),
            }),
          );
        }
        return jsonText(
          await client.post("/api/vms/preview", {
            ...(config ? { config } : {}),
            ...(packages ? { packages } : {}),
            ...(name ? { name } : {}),
            ...(diskGB !== undefined ? { diskGB } : {}),
            ...(channel ? { channel } : {}),
          }),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_vm_log",
    {
      title: "Read a VM log",
      description: "Read the build, serial-console, or nixos-rebuild apply log for a virtual machine.",
      inputSchema: {
        vm: z.string().describe("Virtual machine id."),
        type: z.enum(["build", "serial", "apply"]).optional().describe("Log to read. Defaults to build."),
        tail: z
          .number()
          .int()
          .min(1)
          .max(2_000)
          .optional()
          .describe("Lines to return. Defaults to 240."),
      },
      annotations: READ_ONLY,
    },
    async ({ vm, type, tail }) => {
      try {
        return jsonText(
          await context.client().get(
            `${vmPath(vm)}/log${queryString({ type: type ?? "build", tail: tail ?? 240 })}`,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "read_vm_console",
    {
      title: "Read or type in a VM serial console",
      description:
        "Attach to a running guest's serial console for a short bounded window. Pass `input` to type into it, " +
        "for example a login name or command.",
      inputSchema: {
        vm: z.string().describe("Virtual machine id."),
        input: z.string().optional().describe("Text to send to the console."),
        enter: z
          .boolean()
          .optional()
          .describe("Append a carriage return to the input. Defaults to true when input is sent."),
        waitMs: z
          .number()
          .int()
          .min(100)
          .max(20_000)
          .optional()
          .describe("How long to collect console output. Defaults to 1,500 ms."),
        raw: z.boolean().optional().describe("Keep terminal colour escapes."),
      },
      annotations: WRITE,
    },
    async ({ vm, input, enter, waitMs, raw }) => {
      const pressEnter = enter ?? true;
      const payload =
        input === undefined ? undefined : pressEnter ? `${input}\r` : input;
      try {
        const result = await readSocket(
          context.client(),
          `${vmPath(vm)}/console/socket`,
          {},
          {
            ...(payload !== undefined ? { input: payload } : {}),
            waitMs: waitMs ?? 1_500,
            raw,
          },
        );
        return jsonText({ vm: vm.trim(), ...result });
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_vm_setup_status",
    {
      title: "Get VM setup status",
      description:
        "Read the current or last Nix/helper setup job, including its step, state, progress, and output.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/vms/setup"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "start_vm_setup",
    {
      title: "Start a VM host setup step",
      description:
        "Run the hub's fixed Nix installer or helper-build step on the Mac. The macOS admin prompt appears on the Mac.",
      inputSchema: {
        step: z.enum(["nix", "helper"]).describe("Setup step to start."),
      },
      annotations: { readOnlyHint: false, openWorldHint: true },
    },
    async ({ step }) => {
      try {
        return jsonText(await context.client().post("/api/vms/setup", { step }));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "cancel_vm_setup",
    {
      title: "Cancel VM setup",
      description: "Cancel the running Nix installer or helper build.",
      inputSchema: {},
      annotations: { readOnlyHint: false, destructiveHint: true, openWorldHint: false },
    },
    async () => {
      try {
        return jsonText(await context.client().post("/api/vms/setup/cancel"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "list_vm_setup_logs",
    {
      title: "List VM setup logs",
      description: "List the stored Nix-installer and helper-build logs, including rotated runs.",
      inputSchema: {},
      annotations: READ_ONLY,
    },
    async () => {
      try {
        return jsonText(await context.client().get("/api/vms/setup/logs"));
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );

  server.registerTool(
    "get_vm_setup_log",
    {
      title: "Read a VM setup log",
      description: "Read the newest log for one setup step, with ANSI escapes stripped by the hub.",
      inputSchema: {
        step: z.enum(["nix", "helper", "builder"]).describe("Setup step to read."),
        tail: z
          .number()
          .int()
          .min(1)
          .max(2_000)
          .optional()
          .describe("Lines to return. Defaults to 1,200."),
      },
      annotations: READ_ONLY,
    },
    async ({ step, tail }) => {
      try {
        return jsonText(
          await context.client().get(
            `/api/vms/setup/log${queryString({ step, tail: tail ?? 1_200 })}`,
          ),
        );
      } catch (caught) {
        return failure(describeError(caught));
      }
    },
  );
}