import { describe, expect, test } from "bun:test";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { CommandResult, CommandRunner } from "../src/system/types.ts";
import {
  VMValidationError,
  normalizeChannel,
  normalizePackages,
  renderConfiguration,
  renderFlake,
  validateVMName,
} from "../src/vms/nixos.ts";
import { VirtualMachineService } from "../src/vms/service.ts";
import { readLogTail } from "../src/vms/logs.ts";
import { VMStore, newMACAddress, newVMID } from "../src/vms/store.ts";
import type { VirtualMachine } from "../src/vms/types.ts";

function tempRoot(): string {
  return mkdtempSync(join(tmpdir(), "opencodebar-vms-"));
}

function executable(path: string, body: string): void {
  writeFileSync(path, body, { mode: 0o755 });
  chmodSync(path, 0o755);
}

const FAKE_NIX = `#!/bin/sh
set -e
if [ "$1" = "--version" ]; then
  echo "nix (Nix) 2.28.3"
  exit 0
fi
if [ "$1" = "config" ]; then
  echo "builders = ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 4 1 big-parallel"
  exit 0
fi
mkdir -p "$PWD/fake-store/image/nix-support"
dd if=/dev/zero of="$PWD/fake-store/image/nixos.img" bs=1024 count=64 2>/dev/null
ln -sfn "$PWD/fake-store/image" result
echo "$PWD/fake-store/image"
`;

function fakeRunner(nixPath: string): CommandRunner {
  return async (command: string, args: string[]): Promise<CommandResult> => {
    if (command === nixPath) {
      if (args[0] === "--version") {
        return { ok: true, stdout: "nix (Nix) 2.28.3\n", stderr: "" };
      }
      if (args.includes("config") && args.includes("show")) {
        return {
          ok: true,
          stdout: "builders = ssh-ng://builder@linux-builder aarch64-linux /key 4 1\n",
          stderr: "",
        };
      }
      return { ok: false, stdout: "", stderr: "unexpected nix call" };
    }
    if (command === "ssh-keygen") {
      const index = args.indexOf("-f");
      const path = index >= 0 ? args[index + 1] : undefined;
      if (!path) return { ok: false, stdout: "", stderr: "missing key path" };
      writeFileSync(path, "private\n", { mode: 0o600 });
      writeFileSync(`${path}.pub`, "ssh-ed25519 AAAATEST opencodebar\n");
      return { ok: true, stdout: "", stderr: "" };
    }
    if (command === "cp") {
      const [source, destination] = [args[args.length - 2], args[args.length - 1]];
      if (!source || !destination) {
        return { ok: false, stdout: "", stderr: "missing cp paths" };
      }
      writeFileSync(destination, readFileSync(source));
      chmodSync(destination, 0o600);
      return { ok: true, stdout: "", stderr: "" };
    }
    return { ok: false, stdout: "", stderr: `unexpected command ${command}` };
  };
}

async function waitForStatus(
  service: VirtualMachineService,
  id: string,
  statuses: VirtualMachine["status"][],
  timeoutMs = 8_000,
): Promise<VirtualMachine> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const vm = await service.get(id, false);
    if (vm && statuses.includes(vm.status)) return vm;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  const current = await service.get(id, false);
  throw new Error(`Timed out waiting for ${statuses.join("/")}: ${current?.status}`);
}

describe("NixOS definitions", () => {
  test("validates names, channels and package attributes", () => {
    expect(validateVMName("  Nix OS  ")).toBe("Nix OS");
    expect(() => validateVMName("")).toThrow(VMValidationError);
    expect(() => validateVMName("bad\nname")).toThrow(VMValidationError);
    expect(normalizeChannel(undefined)).toBe("nixos-26.05");
    expect(() => normalizeChannel("nixos-26.05; rm -rf /")).toThrow(VMValidationError);
    expect(normalizePackages(["nodejs", "python3Packages.requests", "nodejs"])).toEqual([
      "nodejs",
      "python3Packages.requests",
    ]);
    expect(() => normalizePackages(["ok; bad"])).toThrow(VMValidationError);
  });

  test("renders a declarative NixOS module and flake", () => {
    const vm = sampleVM();
    const config = renderConfiguration(vm, ["nodejs"]);
    expect(config).toContain('system.stateVersion = "26.05"');
    expect(config).toContain('networking.hostName = "ocb-');
    expect(config).toContain("console=ttyAMA0");
    expect(config).toContain("qemu-guest.nix");
    expect(config).toContain("PasswordAuthentication = false");
    expect(config).toContain("wheelNeedsPassword = false");
    expect(config).toContain('lib.getAttrFromPath [ "nodejs" ] pkgs');
    expect(config).toContain(vm.ssh.publicKey);
    expect(config).toContain("image.modules.raw-efi");
    expect(config).toContain("virtualisation.diskSize = 20480");
    expect(config).toContain("lib.mkDefault");
    expect(config).not.toContain("${");

    const nested = renderConfiguration(vm, ["0ad", "python3Packages.requests"]);
    expect(nested).toContain('lib.getAttrFromPath [ "0ad" ] pkgs');
    expect(nested).toContain('lib.getAttrFromPath [ "python3Packages" "requests" ] pkgs');

    const flake = renderFlake(vm);
    expect(flake).toContain('inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05"');
    expect(flake).toContain("system.build.images.raw-efi");
    expect(flake).toContain("nixosConfigurations.ocb-");
  });

  test("allocates unique MAC addresses", () => {
    const first: VirtualMachine = sampleVM();
    const second: VirtualMachine = { ...sampleVM(), id: newVMID() };
    const mac = newMACAddress([first, second]);
    expect(mac).toMatch(/^52:54:00:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}$/);
    expect([first.network.mac, second.network.mac]).not.toContain(mac);
  });
});

describe("VM store and logs", () => {
  test("round-trips a VM definition with owner-only permissions", () => {
    const root = tempRoot();
    const store = new VMStore({ root });
    const vm = sampleVM();
    store.createLayout(vm.id);
    store.write(vm);
    const loaded = store.read(vm.id);
    expect(loaded?.name).toBe(vm.name);
    expect(loaded?.packages).toEqual(vm.packages);
    expect(statSync(store.metaPath(vm.id)).mode & 0o777).toBe(0o600);
    expect(store.list()).toHaveLength(1);
    store.remove(vm.id);
    expect(store.read(vm.id)).toBeNull();
    rmSync(root, { recursive: true, force: true });
  });

  test("reads only the tail of a large log", () => {
    const root = tempRoot();
    const path = join(root, "log.txt");
    writeFileSync(path, Array.from({ length: 500 }, (_, index) => `line ${index}`).join("\n"));
    const tail = readLogTail(path, 3, 32);
    expect(tail.lines.length).toBeLessThanOrEqual(3);
    expect(tail.truncated).toBe(true);
    rmSync(root, { recursive: true, force: true });
  });
});

describe("VirtualMachineService", () => {
  test("creates, builds, updates and deletes a VM with an injected Nix", async () => {
    const root = tempRoot();
    const tools = join(root, "tools");
    mkdirSync(tools, { recursive: true });
    const nixPath = join(tools, "nix");
    const helperPath = join(tools, "OpenCodeBarVZ");
    executable(nixPath, FAKE_NIX);
    executable(helperPath, "#!/bin/sh\nexit 0\n");

    const service = new VirtualMachineService({
      root: join(root, "vms"),
      runner: fakeRunner(nixPath),
      env: {
        ...process.env,
        OPENCODEBAR_NIX: nixPath,
        OPENCODEBAR_VZ_HELPER: helperPath,
      },
    });

    const capabilities = await service.capabilities();
    expect(capabilities.nixAvailable).toBe(true);
    expect(capabilities.linuxBuilder).toBe(true);
    expect(capabilities.helperAvailable).toBe(true);

    const created = await service.create({
      name: "Test NixOS",
      cpuCount: 2,
      memoryMB: 2048,
      diskGB: 12,
      packages: ["nodejs"],
      autostart: false,
    });
    expect(created.status).toBe("building");
    expect(created.network.mac).toMatch(/^52:54:00:/);

    const built = await waitForStatus(service, created.id, ["stopped", "error"]);
    expect(built.status).toBe("stopped");
    expect(existsSync(built.paths.disk)).toBe(true);
    expect(statSync(built.paths.disk).size).toBe(64 * 1024);

    const config = readFileSync(built.paths.configuration, "utf8");
    expect(config).toContain("nodejs");
    expect(config).toContain(built.ssh.publicKey);

    const log = await service.log(created.id, "build", 50);
    expect(log.lines.join("\n")).toContain("nix build");
    expect(log.lines.join("\n")).toContain("fake-store/image");
    expect(log.lines.join("\n")).toContain("Image ready");

    const updated = await service.update(created.id, { packages: ["nodejs", "ripgrep"] });
    expect(updated.packages).toEqual(["nodejs", "ripgrep"]);
    expect(updated.pendingPackages).toEqual(["nodejs", "ripgrep"]);
    expect(readFileSync(updated.paths.configuration, "utf8")).toContain("ripgrep");

    await expect(service.control(created.id, "apply")).rejects.toThrow(
      "Start the virtual machine before applying packages",
    );
    await expect(service.consoleTarget(created.id)).rejects.toThrow(VMValidationError);

    await service.remove(created.id, true);
    expect(await service.get(created.id)).toBeNull();
    rmSync(root, { recursive: true, force: true });
  });
});

function sampleVM(): VirtualMachine {
  const id = newVMID();
  const directory = `/tmp/opencodebar-vms/${id}`;
  return {
    id,
    name: "Test NixOS",
    distro: "nixos",
    channel: "nixos-26.05",
    stateVersion: "26.05",
    arch: "aarch64",
    status: "stopped",
    createdAt: 1,
    updatedAt: 1,
    cpuCount: 4,
    memoryMB: 4096,
    diskGB: 20,
    packages: ["nodejs"],
    pendingPackages: [],
    lastError: null,
    progress: null,
    ssh: {
      user: "opencodebar",
      keyPath: `${directory}/ssh/id_ed25519`,
      publicKey: "ssh-ed25519 AAAATEST test",
    },
    network: {
      mac: "52:54:00:11:22:33",
      ip: null,
      reachable: false,
    },
    paths: {
      directory,
      disk: `${directory}/disk.raw`,
      configuration: `${directory}/configuration.nix`,
      flake: `${directory}/flake.nix`,
      serialLog: `${directory}/serial.log`,
      buildLog: `${directory}/build.log`,
      applyLog: `${directory}/apply.log`,
      runtime: `${directory}/runtime.json`,
    },
    metrics: null,
  };
}
