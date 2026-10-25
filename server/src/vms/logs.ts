import {
  appendFileSync,
  chmodSync,
  closeSync,
  existsSync,
  openSync,
  readSync,
  statSync,
  truncateSync,
} from "node:fs";

const DEFAULT_MAX_BYTES = 128 * 1024;
const DEFAULT_MAX_LINES = 240;

export interface LogTail {
  lines: string[];
  bytes: number;
  truncated: boolean;
}

/** Reads only the end of a potentially very large build or serial log. */
export function readLogTail(
  path: string,
  maxLines = DEFAULT_MAX_LINES,
  maxBytes = DEFAULT_MAX_BYTES,
): LogTail {
  if (!existsSync(path)) return { lines: [], bytes: 0, truncated: false };
  let size = 0;
  try {
    size = statSync(path).size;
  } catch {
    return { lines: [], bytes: 0, truncated: false };
  }
  if (size === 0) return { lines: [], bytes: 0, truncated: false };

  const length = Math.min(size, maxBytes);
  const start = size - length;
  const buffer = Buffer.allocUnsafe(length);
  const fd = openSync(path, "r");
  try {
    readSync(fd, buffer, 0, length, start);
  } finally {
    closeSync(fd);
  }

  let text = buffer.toString("utf8");
  // When starting mid-file, the first line is usually a fragment. Drop it so
  // the UI never shows half a timestamp.
  if (start > 0) {
    const newline = text.indexOf("\n");
    text = newline >= 0 ? text.slice(newline + 1) : "";
  }
  const allLines = text.split(/\r?\n/);
  if (allLines.length > 0 && allLines[allLines.length - 1] === "") allLines.pop();
  const lines = allLines.length > maxLines ? allLines.slice(-maxLines) : allLines;
  return { lines, bytes: size, truncated: start > 0 || allLines.length > maxLines };
}

export function appendLog(path: string, text: string): void {
  if (!text) return;
  appendFileSync(path, text, { mode: 0o600 });
}

export function resetLog(path: string): void {
  appendFileSync(path, "", { mode: 0o600 });
  try {
    truncateSync(path, 0);
  } catch {
    // The next append creates it again.
  }
  try {
    chmodSync(path, 0o600);
  } catch {
    // Best effort.
  }
}

/**
 * Turns a stream of command output into line-sized log writes. Nix writes
 * progress with carriage returns; normalising keeps the log readable.
 */
export function createLogWriter(path: string): (chunk: string) => void {
  return (chunk: string) => {
    const text = chunk.replace(/\r(?!\n)/g, "\n");
    if (text) appendLog(path, text);
  };
}
