import { platform } from "node:os";
import type { SystemSecurity } from "../types.ts";
import { COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import { asRecord, firstLine, parseJSONValue, readFileSafe, text } from "./util.ts";

export async function collectSecurity(run: CommandRunner): Promise<SystemSecurity | null> {
  const os = platform();
  if (os === "darwin") {
    const [sip, vault, firewall, gatekeeper] = await Promise.all([
      run("csrutil", ["status"], COMMAND_TIMEOUT_MS),
      run("fdesetup", ["status"], COMMAND_TIMEOUT_MS),
      run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"], COMMAND_TIMEOUT_MS),
      run("spctl", ["--status"], COMMAND_TIMEOUT_MS),
    ]);
    return {
      systemIntegrityProtection: parseOnOff(text(sip)),
      fileVault: parseOnOff(text(vault)),
      firewall: parseOnOff(text(firewall)),
      gatekeeper: parseOnOff(text(gatekeeper)),
    };
  }

  if (os === "linux") {
    const [ufw, selinux, apparmor] = await Promise.all([
      run("ufw", ["status"], COMMAND_TIMEOUT_MS),
      run("getenforce", [], COMMAND_TIMEOUT_MS),
      run("aa-status", ["--enabled"], COMMAND_TIMEOUT_MS),
    ]);
    const security: SystemSecurity = {
      firewall: parseOnOff(text(ufw)),
    };
    const selinuxValue = firstLine(text(selinux));
    if (selinuxValue) security.selinux = selinuxValue;
    if (apparmor.ok) security.appArmor = "enabled";
    const lsm = readFileSafe("/sys/kernel/security/lsm").trim();
    if (lsm && !security.appArmor && !security.selinux) security.appArmor = lsm;
    return security;
  }

  if (os === "win32") {
    const [defender, firewall] = await Promise.all([
      run(
        "powershell",
        ["-NoProfile", "-NonInteractive", "-Command", "(Get-MpComputerStatus).RealTimeProtectionEnabled"],
        COMMAND_TIMEOUT_MS,
      ),
      run(
        "powershell",
        [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "Get-NetFirewallProfile | Select-Object Name,Enabled | ConvertTo-Json -Compress",
        ],
        COMMAND_TIMEOUT_MS,
      ),
    ]);
    return {
      defender: firstLine(text(defender)) || undefined,
      firewall: summarizeWindowsFirewall(text(firewall)),
    };
  }

  return null;
}

export function parseOnOff(value: string): boolean | string | undefined {
  const lower = value.toLowerCase();
  if (!lower.trim()) return undefined;
  if (lower.includes("disabled") || lower.includes(" off") || lower.includes("inactive")) return false;
  if (lower.includes("enabled") || lower.includes(" on") || lower.includes("active")) return true;
  return value.trim().slice(0, 120) || undefined;
}

export function summarizeWindowsFirewall(value: string): boolean | string | undefined {
  if (!value.trim()) return undefined;
  const raw = parseJSONValue(value);
  const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
  if (entries.length === 0) return undefined;
  const enabled = entries.every((entry) => {
    const record = asRecord(entry);
    return record?.Enabled === true || record?.Enabled === 1;
  });
  return enabled;
}
