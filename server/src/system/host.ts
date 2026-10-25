import { arch, cpus, homedir, hostname, platform, release } from "node:os";
import { COMMAND_TIMEOUT_MS, LONG_COMMAND_TIMEOUT_MS } from "./constants.ts";
import { parseMemInfo, parseSwapUsage, parseVMStat } from "./memory.ts";
import type { CommandRunner, StaticInfo } from "./types.ts";
import {
  cpuModel,
  firstLine,
  firstObject,
  lines,
  numberValue,
  parseJSON,
  parseJSONRecord,
  parseKeyValueLines,
  platformName,
  readFileSafe,
  safeUsername,
  stringValue,
  text,
} from "./util.ts";

export async function collectOS(run: CommandRunner, info: StaticInfo): Promise<void> {
  const os = platform();
  info.host.platform = os;
  info.host.platformName = platformName();
  info.host.kernel = release();
  info.host.arch = arch();
  info.host.username = safeUsername();
  info.host.home = homedir();
  info.host.shell = process.env.SHELL;
  info.host.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  info.host.locale = process.env.LANG ?? Intl.DateTimeFormat().resolvedOptions().locale;

  if (os === "darwin") {
    const [swVers, computerName, virt] = await Promise.all([
      run("sw_vers", [], COMMAND_TIMEOUT_MS),
      run("scutil", ["--get", "ComputerName"], COMMAND_TIMEOUT_MS),
      run("sysctl", ["-n", "kern.hv_vmm_present"], COMMAND_TIMEOUT_MS),
    ]);
    const values = parseKeyValueLines(text(swVers));
    info.host.osName = values.ProductName;
    info.host.osVersion = values.ProductVersion;
    info.host.osBuild = values.BuildVersion;
    info.host.name = firstLine(text(computerName)) || hostname();
    const hv = firstLine(text(virt));
    if (hv === "1") info.host.isVirtualMachine = true;
    if (hv === "1") info.host.virtualization = "virtual machine";
    return;
  }

  if (os === "linux") {
    const releaseInfo = parseOSRelease(readFileSafe("/etc/os-release"));
    info.host.osName = releaseInfo.NAME ?? "Linux";
    info.host.osVersion = releaseInfo.VERSION ?? releaseInfo.VERSION_ID;
    info.host.osBuild = releaseInfo.BUILD_ID;
    info.host.name = hostname();
    const [virt, kernel] = await Promise.all([
      run("systemd-detect-virt", [], COMMAND_TIMEOUT_MS),
      run("uname", ["-r"], COMMAND_TIMEOUT_MS),
    ]);
    const virtName = firstLine(text(virt));
    if (virtName && virtName !== "none") {
      info.host.isVirtualMachine = true;
      info.host.virtualization = virtName;
    }
    const kernelLine = firstLine(text(kernel));
    if (kernelLine) info.host.kernel = kernelLine;
    return;
  }

  if (os === "win32") {
    const result = await run(
      "powershell",
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber | ConvertTo-Json -Compress",
      ],
      COMMAND_TIMEOUT_MS,
    );
    const value = parseJSONRecord(firstLine(text(result)));
    info.host.osName = stringValue(value?.Caption) ?? "Windows";
    info.host.osVersion = stringValue(value?.Version);
    info.host.osBuild = stringValue(value?.BuildNumber);
    info.host.name = hostname();
    info.host.shell = process.env.COMSPEC;
  }
}

export async function collectHardware(run: CommandRunner, info: StaticInfo): Promise<void> {
  const os = platform();
  const logical = cpus().length;
  info.cpu.logicalCores = logical;
  info.cpu.architecture = arch();
  info.cpu.speedMHz = cpus()[0]?.speed;
  info.cpu.model = cpuModel();

  if (os === "darwin") {
    const [hw, physical, brand, model] = await Promise.all([
      run(
        "system_profiler",
        ["SPHardwareDataType", "-json", "-detailLevel", "mini"],
        LONG_COMMAND_TIMEOUT_MS,
      ),
      run("sysctl", ["-n", "hw.physicalcpu"], COMMAND_TIMEOUT_MS),
      run("sysctl", ["-n", "machdep.cpu.brand_string"], COMMAND_TIMEOUT_MS),
      run("sysctl", ["-n", "hw.model"], COMMAND_TIMEOUT_MS),
    ]);
    const hardware = firstObject(parseJSON(text(hw))?.SPHardwareDataType);
    info.host.model = stringValue(hardware?.machine_name);
    info.host.chip = stringValue(hardware?.chip_type);
    info.host.machine = stringValue(hardware?.machine_model) ?? firstLine(text(model));
    info.host.osName = info.host.osName ?? "macOS";
    info.cpu.model = info.host.chip ?? firstLine(text(brand)) ?? info.cpu.model;
    info.cpu.vendor = "Apple";
    const cores = Number.parseInt(firstLine(text(physical)) ?? "", 10);
    if (Number.isFinite(cores)) info.cpu.physicalCores = cores;

    const swap = parseSwapUsage(text(await run("sysctl", ["-n", "vm.swapusage"], COMMAND_TIMEOUT_MS)));
    info.memory.swapTotalBytes = swap.total;
    info.memory.swapUsedBytes = swap.used;
    info.memory.swapFreeBytes = swap.free;
    Object.assign(info.memory, parseVMStat(text(await run("vm_stat", [], COMMAND_TIMEOUT_MS))));
    return;
  }

  if (os === "linux") {
    const cpuinfo = readFileSafe("/proc/cpuinfo");
    info.cpu.model = info.cpu.model ?? parseLinuxCPUModel(cpuinfo);
    info.cpu.vendor = parseLinuxCPUVendor(cpuinfo);
    info.cpu.physicalCores = parseLinuxPhysicalCores(cpuinfo);
    Object.assign(info.memory, parseMemInfo(readFileSafe("/proc/meminfo")));
    const model = readFileSafe("/proc/device-tree/model").replace(/\0/g, "").trim();
    if (model) info.host.model = model;
    return;
  }

  if (os === "win32") {
    const result = await run(
      "powershell",
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Get-CimInstance Win32_Processor | Select-Object -First 1 Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed | ConvertTo-Json -Compress",
      ],
      COMMAND_TIMEOUT_MS,
    );
    const cpu = parseJSONRecord(firstLine(text(result)));
    info.cpu.model = stringValue(cpu?.Name) ?? info.cpu.model;
    info.cpu.vendor = stringValue(cpu?.Manufacturer);
    info.cpu.physicalCores = numberValue(cpu?.NumberOfCores);
    const cores = numberValue(cpu?.NumberOfLogicalProcessors);
    if (cores) info.cpu.logicalCores = cores;
    info.cpu.speedMHz = numberValue(cpu?.MaxClockSpeed);
    info.host.osName = info.host.osName ?? "Windows";

    const computer = await run(
      "powershell",
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory | ConvertTo-Json -Compress",
      ],
      COMMAND_TIMEOUT_MS,
    );
    const system = parseJSONRecord(firstLine(text(computer)));
    info.host.model = stringValue(system?.Model);
    info.host.machine = stringValue(system?.Manufacturer);
  }
}

function parseOSRelease(value: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of lines(value)) {
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!match?.[1]) continue;
    result[match[1]] = (match[2] ?? "").replace(/^["']|["']$/g, "");
  }
  return result;
}

function parseLinuxCPUModel(cpuinfo: string): string | undefined {
  const match = cpuinfo.match(/^model name\s*:\s*(.+)$/m) ?? cpuinfo.match(/^Hardware\s*:\s*(.+)$/m);
  return match?.[1]?.trim();
}

function parseLinuxCPUVendor(cpuinfo: string): string | undefined {
  return cpuinfo.match(/^vendor_id\s*:\s*(.+)$/m)?.[1]?.trim();
}

function parseLinuxPhysicalCores(cpuinfo: string): number | undefined {
  const pairs = new Set<string>();
  let physicalID = "0";
  let coreID: string | undefined;
  for (const line of cpuinfo.split(/\r?\n/)) {
    const field = line.split(":")[0]?.trim();
    const value = line.slice(line.indexOf(":") + 1).trim();
    if (field === "physical id") physicalID = value;
    if (field === "core id") coreID = value;
    if (coreID !== undefined && field === "core id") pairs.add(`${physicalID}:${coreID}`);
  }
  return pairs.size || undefined;
}
