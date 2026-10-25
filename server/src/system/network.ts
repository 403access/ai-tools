import { hostname, networkInterfaces, platform } from "node:os";
import type { SystemNetwork, SystemPort } from "../types.ts";
import { COMMAND_TIMEOUT_MS } from "./constants.ts";
import type { CommandRunner } from "./types.ts";
import {
  asRecord,
  firstLine,
  lines,
  numberValue,
  parseJSONValue,
  readFileSafe,
  stringValue,
  text,
  unique,
} from "./util.ts";

export async function collectNetwork(run: CommandRunner): Promise<SystemNetwork> {
  const interfaces = networkInterfaces();
  const result: SystemNetwork["interfaces"] = [];
  for (const [name, addresses] of Object.entries(interfaces)) {
    if (!addresses || addresses.length === 0) continue;
    result.push({
      name,
      addresses: addresses.map((address) => ({
        address: address.address,
        family: address.family,
        internal: address.internal,
        mac: address.mac,
        netmask: address.netmask,
        cidr: address.cidr ?? undefined,
      })),
    });
  }
  result.sort((a, b) => a.name.localeCompare(b.name));

  const os = platform();
  let defaultGateway: string | undefined;
  let defaultInterface: string | undefined;
  let dnsServers: string[] = [];

  if (os === "darwin") {
    const [route, dns] = await Promise.all([
      run("route", ["-n", "get", "default"], COMMAND_TIMEOUT_MS),
      run("scutil", ["--dns"], COMMAND_TIMEOUT_MS),
    ]);
    const routeText = text(route);
    defaultGateway = /gateway:\s*(\S+)/.exec(routeText)?.[1];
    defaultInterface = /interface:\s*(\S+)/.exec(routeText)?.[1];
    dnsServers = unique(
      [...text(dns).matchAll(/nameserver\[\d+\]\s*:\s*(\S+)/g)].map((match) => match[1] ?? ""),
    );
  } else if (os === "linux") {
    const route = await run("ip", ["route", "show", "default"], COMMAND_TIMEOUT_MS);
    const routeText = firstLine(text(route));
    defaultGateway = /via\s+(\S+)/.exec(routeText ?? "")?.[1];
    defaultInterface = /\bdev\s+(\S+)/.exec(routeText ?? "")?.[1];
    dnsServers = [...readFileSafe("/etc/resolv.conf").matchAll(/^nameserver\s+(\S+)/gm)]
      .map((match) => match[1] ?? "");
    dnsServers = unique(dnsServers);
  } else if (os === "win32") {
    const [route, dns] = await Promise.all([
      run("powershell", ["-NoProfile", "-NonInteractive", "-Command", "(Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).NextHop"], COMMAND_TIMEOUT_MS),
      run("powershell", ["-NoProfile", "-NonInteractive", "-Command", "(Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses"], COMMAND_TIMEOUT_MS),
    ]);
    defaultGateway = firstLine(text(route));
    dnsServers = unique(lines(text(dns)));
  }

  return {
    hostname: hostname(),
    interfaces: result,
    defaultGateway,
    defaultInterface,
    dnsServers,
  };
}


export async function collectListeningPorts(run: CommandRunner): Promise<SystemPort[]> {
  const os = platform();
  if (os === "darwin") {
    const result = await run(
      "lsof",
      ["-nP", "-iTCP", "-sTCP:LISTEN"],
      COMMAND_TIMEOUT_MS,
    );
    if (!result.ok && !text(result)) return [];
    return parseLsofPorts(text(result));
  }

  if (os === "linux") {
    let result = await run("ss", ["-ltnp"], COMMAND_TIMEOUT_MS);
    if (!result.ok) result = await run("netstat", ["-ltnp"], COMMAND_TIMEOUT_MS);
    return parseSSPorts(text(result));
  }

  if (os === "win32") {
    const result = await run(
      "powershell",
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Get-NetTCPConnection -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess | ConvertTo-Json -Compress",
      ],
      COMMAND_TIMEOUT_MS,
    );
    const raw = parseJSONValue(text(result));
    const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
    return entries.flatMap((rawEntry) => {
      const entry = asRecord(rawEntry);
      const port = numberValue(entry?.LocalPort);
      if (port === undefined) return [];
      return [{
        port,
        protocol: "tcp" as const,
        address: stringValue(entry?.LocalAddress),
        pid: numberValue(entry?.OwningProcess),
      }];
    });
  }

  return [];
}

export function parseLsofPorts(value: string): SystemPort[] {
  const ports: SystemPort[] = [];
  const seen = new Set<string>();
  for (const line of value.split(/\r?\n/)) {
    const match = line.match(/^(\S+)\s+(\d+)\s+\S+.*\sTCP\s+(\S+)\s+\(LISTEN\)/);
    if (!match) continue;
    const process = match[1] ?? "";
    const pid = Number.parseInt(match[2] ?? "", 10);
    const name = match[3] ?? "";
    const separator = name.lastIndexOf(":");
    if (separator < 0) continue;
    const port = Number.parseInt(name.slice(separator + 1), 10);
    if (!Number.isFinite(port)) continue;
    const key = `${port}:${process}:${pid}`;
    if (seen.has(key)) continue;
    seen.add(key);
    ports.push({
      port,
      protocol: "tcp",
      address: name.slice(0, separator),
      process,
      pid: Number.isFinite(pid) ? pid : undefined,
    });
  }
  return ports.sort((a, b) => a.port - b.port);
}

export function parseSSPorts(value: string): SystemPort[] {
  const ports: SystemPort[] = [];
  const seen = new Set<string>();
  for (const line of value.split(/\r?\n/)) {
    const columns = line.trim().split(/\s+/);
    if (columns[0] !== "LISTEN") continue;
    const local = columns[3];
    if (!local) continue;
    const separator = local.lastIndexOf(":");
    if (separator < 0) continue;
    const port = Number.parseInt(local.slice(separator + 1), 10);
    if (!Number.isFinite(port)) continue;
    const processMatch = /users:\(\("([^"]+)",pid=(\d+)/.exec(line);
    const process = processMatch?.[1];
    const pid = processMatch?.[2] ? Number.parseInt(processMatch[2], 10) : undefined;
    const key = `${port}:${process ?? ""}:${pid ?? 0}`;
    if (seen.has(key)) continue;
    seen.add(key);
    ports.push({
      port,
      protocol: "tcp",
      address: local.slice(0, separator),
      process,
      pid,
    });
  }
  return ports.sort((a, b) => a.port - b.port);
}
