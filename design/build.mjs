// Build the OpenPencil design mirror.
//
//   node design/build.mjs            # write JSX for every page into /tmp/opjsx
//   node design/build.mjs 00 01      # only the named pages
//   node design/build.mjs --render   # write and render into the open document
//
// Rendering uses the OpenPencil CLI and the document already open in the app.
// Page ids come from `openpencil tool call list_pages --document-id <id>`.

import { writeFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";

export const PAGES = [
  ["start", "Start here", () => import("./gen/pstart.mjs")],
  ["00", "00 · Cover & Repo Map", () => import("./gen/p00.mjs")],
  ["01", "01 · Design System", () => import("./gen/p01.mjs")],
  ["02", "02 · macOS Shell & Navigation", () => import("./gen/p02.mjs")],
  ["03", "03 · macOS Live & Session", () => import("./gen/p03.mjs")],
  ["04", "04 · macOS Projects & Usage", () => import("./gen/p04.mjs")],
  ["05", "05 · macOS System & VMs", () => import("./gen/p05.mjs")],
  ["06", "06 · iOS Core", () => import("./gen/p06.mjs")],
  ["07", "07 · iOS Host & Remote", () => import("./gen/p07.mjs")],
  ["08", "08 · iOS VMs & Widgets", () => import("./gen/p08.mjs")],
  ["09", "09 · States & Edge Cases", () => import("./gen/p09.mjs")],
  ["10", "10 · Architecture", () => import("./gen/p10.mjs")],
  ["11", "11 · Roadmap", () => import("./gen/p11.mjs")],
  ["12", "12 · Coverage & Docs", () => import("./gen/p12.mjs")],
];

const args = process.argv.slice(2);
const render = args.includes("--render");
const docId = process.env.OPENPENCIL_DOC || "tab-1";
const only = args.filter((a) => !a.startsWith("--"));
const outDir = "/tmp/opjsx";
mkdirSync(outDir, { recursive: true });

const pageIds = {};
if (render) {
  const pages = JSON.parse(
    execFileSync("openpencil", ["tool", "call", "list_pages", "--document-id", docId, "--json"], {
      encoding: "utf8",
    }),
  ).pages;
  for (const p of pages) pageIds[p.name] = p.id;
}

for (const [key, name, load] of PAGES) {
  if (only.length && !only.includes(key)) continue;
  const mod = await load();
  const out = mod.default();
  const file = `${outDir}/${key}.json`;
  if (typeof out === "string" || !out.flat) {
    writeFileSync(file, JSON.stringify({ jsx: typeof out === "string" ? out : out.root }));
  }
  console.log(`${key}  ${name}  ${(JSON.stringify(out).length / 1024).toFixed(1)} KB`);
  if (render) {
    const pageId = pageIds[name];
    if (!pageId) throw new Error(`No OpenPencil page named ${name}`);
    // A rebuild replaces the page, so remove the previous root frames first.
    const tree = JSON.parse(
      execFileSync(
        "openpencil",
        ["tool", "call", "get_page_tree", "--document-id", docId, "--page-id", pageId, "--json"],
        { encoding: "utf8" },
      ),
    );
    for (const child of tree.children || []) {
      execFileSync(
        "openpencil",
        ["tool", "call", "delete_node", "--args", JSON.stringify({ id: child.id }), "--document-id", docId, "--page-id", pageId],
        { stdio: "ignore" },
      );
    }
    if (typeof out !== "string" && out.flat) {
      // Flat pages render every top-level frame independently. This avoids a
      // single huge page frame that some OpenPencil canvas builds refuse to paint.
      out.sections.forEach((jsx, i) => {
        const sectionFile = `${outDir}/${key}-flat-${i}.json`;
        writeFileSync(sectionFile, JSON.stringify({ jsx }));
        console.log(`  flat ${i + 1}/${out.sections.length}  ${(jsx.length / 1024).toFixed(1)} KB`);
        execFileSync(
          "openpencil",
          ["tool", "call", "render", "--args-file", sectionFile, "--document-id", docId, "--page-id", pageId],
          { stdio: "inherit" },
        );
      });
      continue;
    }
    execFileSync(
      "openpencil",
      ["tool", "call", "render", "--args-file", file, "--document-id", docId, "--page-id", pageId],
      { stdio: "inherit" },
    );
    if (typeof out !== "string") {
      // The root is on the page; append each section into it so every MCP call
      // stays small enough for the app's RPC deadline.
      const after = JSON.parse(
        execFileSync(
          "openpencil",
          ["tool", "call", "get_page_tree", "--document-id", docId, "--page-id", pageId, "--json"],
          { encoding: "utf8" },
        ),
      );
      const rootId = (after.children || [])[0]?.id;
      if (!rootId) throw new Error(`No root frame on ${name}`);
      out.sections.forEach((jsx, i) => {
        const sectionFile = `${outDir}/${key}-${i}.json`;
        writeFileSync(sectionFile, JSON.stringify({ jsx, parent_id: rootId }));
        console.log(`  section ${i + 1}/${out.sections.length}  ${(jsx.length / 1024).toFixed(1)} KB`);
        execFileSync(
          "openpencil",
          ["tool", "call", "render", "--args-file", sectionFile, "--document-id", docId, "--page-id", pageId],
          { stdio: "inherit" },
        );
      });
    }
  }
}
