import { describe, expect, test } from "bun:test";
import { CaffeinateSleepGuard, type SleepProcess } from "../src/hub/sleep.ts";

function fakeProcess(onKill: () => void): SleepProcess {
  return {
    kill: onKill,
    exited: new Promise<number>(() => {}),
  };
}

describe("sleep guard", () => {
  test("starts caffeinate for idle sleep and stops it again", () => {
    const argv: string[][] = [];
    let killed = false;
    const guard = new CaffeinateSleepGuard(() => {}, {
      platform: "darwin",
      spawn: (command) => {
        argv.push(command);
        return fakeProcess(() => {
          killed = true;
        });
      },
    });

    guard.setEnabled(true);
    expect(argv).toEqual([["/usr/bin/caffeinate", "-i", "-w", String(process.pid)]]);
    expect(killed).toBe(false);

    guard.setEnabled(false);
    expect(killed).toBe(true);
  });

  test("does not start caffeinate twice", () => {
    let spawns = 0;
    const guard = new CaffeinateSleepGuard(() => {}, {
      platform: "darwin",
      spawn: () => {
        spawns += 1;
        return fakeProcess(() => {});
      },
    });

    guard.setEnabled(true);
    guard.setEnabled(true);
    expect(spawns).toBe(1);
    guard.stop();
  });

  test("is a no-op away from macOS", () => {
    let spawns = 0;
    const guard = new CaffeinateSleepGuard(() => {}, {
      platform: "linux",
      spawn: () => {
        spawns += 1;
        return fakeProcess(() => {});
      },
    });

    expect(guard.supported).toBe(false);
    guard.setEnabled(true);
    expect(spawns).toBe(0);
  });
});
