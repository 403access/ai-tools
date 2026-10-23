import type { SessionMessage } from "../types.ts";

export function encodeMessageCursor(message: SessionMessage): string {
  const payload = JSON.stringify({ t: message.time.created, i: message.id });
  return "hub." + Buffer.from(payload, "utf8").toString("base64url");
}

export function decodeMessageCursor(cursor: string): { t: number; i: string } | null {
  if (!cursor.startsWith("hub.")) return null;
  try {
    const parsed = JSON.parse(Buffer.from(cursor.slice(4), "base64url").toString("utf8")) as {
      t?: unknown;
      i?: unknown;
    };
    if (typeof parsed.t !== "number" || typeof parsed.i !== "string") return null;
    return { t: parsed.t, i: parsed.i };
  } catch {
    return null;
  }
}
