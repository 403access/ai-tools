import { D, F, T, I, chip, card, sectionLabel, pageParts, group, bar, node, arrow } from "./kit.mjs";

const whiteCard = (title, children, w = 1080) =>
  F("Card", { flex: "col", gap: 10, p: 18, rounded: 14, bg: "#FFFFFF", stroke: "#00000012", strokeWidth: 1, w, h: "hug" },
    T(title, { size: 14, weight: "bold", color: "#20252C" }) + children,
  );

const apiRow = (method, path, note) =>
  F("API", { flex: "row", items: "start", gap: 8, w: "fill", py: 4, stroke: "#00000008", strokeWidth: 1 },
    F("Method", { w: 46, px: 4, py: 2, rounded: 4, bg: method === "GET" ? "#0B8F6518" : method === "POST" ? "#0B7DA618" : "#A5650018", items: "center" },
      T(method, { size: 7, weight: "bold", color: method === "GET" ? "#0B8F65" : method === "POST" ? "#0B7DA6" : "#A56500" })) +
    T(path, { size: 8, color: "#20252C", w: 360 }) + T(note, { size: 8, color: "#6B7079", w: "fill", lineHeight: 12 }),
  );

const modelBox = (title, fields, color) =>
  F("Model", { flex: "col", gap: 3, p: 10, rounded: 10, bg: "#FFFFFF", stroke: color + "44", strokeWidth: 1, w: 220, h: "hug" },
    F("H", { flex: "row", items: "center", gap: 5 }, F("Dot", { w: 6, h: 6, rounded: 3, bg: color }) + T(title, { size: 10, weight: "bold", color: "#20252C" })) +
    fields.map((f) => T(f, { size: 7.5, color: "#626A75", lineHeight: 11 })).join(""),
  );

export default function () {
  const topology = whiteCard("Runtime topology",
    F("Diagram", { flex: "row", items: "center", gap: 4, w: "fill", h: "hug" },
      node("OpenCode service", ["loopback · HTTP Basic auth", "REST + SSE · /api/event"], D.running, 220) +
      arrow("REST + SSE") +
      node("OpenCodeBar Hub", ["Bun · SQLite · Bearer auth", "cache · throttle · forward"], D.accent, 220) +
      arrow("cached REST + SSE") +
      F("Clients", { flex: "col", gap: 8, w: 250, h: "hug" },
        node("macOS app", ["menu bar · panel · desktop"], D.purple, 250) +
        node("iOS app", ["iPhone · iPad · widgets"], D.warn, 250))) +
    F("Notes", { flex: "row", gap: 8, w: "fill" }, chip("5s fast poll", D.accent) + chip("60s slow poll", D.sec) + chip("250ms event throttle", D.running) + chip("SQLite cache", D.purple) + chip("SSE reconnect", D.warn)),
    1600,
  );

  const flow = whiteCard("Request flow",
    F("Steps", { flex: "col", gap: 7, w: "fill" },
      [["1", "Discover", "Read ~/.config/opencode/service.json for the password, then opencode service status → lsof → server log for the URL."],
       ["2", "Poll", "Read sessions, projects, messages, stats, Go usage and PTYs on 5s / 60s cycles; write into hub.sqlite."],
       ["3", "Subscribe", "Forward OpenCode /api/event to every client; coalesce bursts into eventThrottleMs windows."],
       ["4", "Serve", "Expose stable mirrored shapes under /api with Bearer auth and X-OpenCodeBar-* identity headers."],
       ["5", "Write through", "Prompts, new sessions, pause/stop/continue and VM actions are forwarded to OpenCode or the helpers."],
       ["6", "Recover", "If the stream is missed, read the newest messages back and rebuild the live snapshot, including todowrite."]].map(([n, t, d]) =>
        F("Step", { flex: "row", items: "start", gap: 8, w: "fill" },
          F("N", { w: 20, h: 20, rounded: 10, bg: "#0B8F6518", items: "center", justify: "center" }, T(n, { size: 9, weight: "bold", color: "#0B8F65" })) +
          F("B", { flex: "col", gap: 1, grow: 1 }, T(t, { size: 10, weight: "semibold", color: "#20252C" }), T(d, { size: 8.5, color: "#626A75", lineHeight: 12, w: "fill" })))).join("")),
    1200,
  );

  const api = whiteCard("Hub API surface",
    F("Groups", { flex: "col", gap: 6, w: "fill" },
      sectionLabel("Sessions") +
      apiRow("GET", "/api/session", "List sessions") + apiRow("GET", "/api/session/:id", "One session") + apiRow("GET", "/api/session/:id/message", "Messages, cached") +
      apiRow("GET", "/api/session/:id/changes", "File patches") + apiRow("GET", "/api/session/:id/stats", "Reliability, paged") + apiRow("GET", "/api/session/:id/git", "Commits while active") +
      apiRow("GET", "/api/session/:id/forks", "Fork graph") + apiRow("POST", "/api/session", "Create session") + apiRow("POST", "/api/session/:id/prompt", "Send prompt") +
      apiRow("POST", "/api/session/:id/pause", "Hold until deadline") + apiRow("POST", "/api/session/:id/stop", "Hold until continue") + apiRow("POST", "/api/session/:id/continue", "Release hold"),
      sectionLabel("Projects, tasks and usage") +
      apiRow("GET", "/api/project", "Projects with running counts") + apiRow("GET", "/api/project/:id/changes", "Aggregated patches") + apiRow("GET", "/api/project/:id/files", "Files + git state") +
      apiRow("GET", "/api/project/:id/git", "Branches, tags, graph") + apiRow("GET", "/api/project/:id/icon", "Discovered icon") + apiRow("GET", "/api/task", "Task board") +
      apiRow("PATCH", "/api/task/:id", "Mark done / reopen / dismiss") + apiRow("GET", "/api/usage", "Go plan limits") + apiRow("GET", "/api/sync", "Delta feed") + apiRow("POST", "/api/sync", "Force sync"),
      sectionLabel("Host, VMs and devices") +
      apiRow("GET", "/api/system", "Machine inventory") + apiRow("GET", "/api/terminals", "OpenCode PTYs") + apiRow("GET", "/api/host-terminals", "Terminal.app tabs") +
      apiRow("GET", "/api/files", "Read-only host browser") + apiRow("GET", "/api/vms", "VM definitions + metrics") + apiRow("GET", "/api/vms/capabilities", "Helper / Nix readiness") +
      apiRow("POST", "/api/vms", "Create guest") + apiRow("POST", "/api/vms/:id/:action", "start stop restart pause resume rebuild apply") + apiRow("GET", "/api/vms/:id/console/socket", "Serial console") +
      apiRow("GET", "/api/devices", "Paired clients") + apiRow("GET", "/api/settings", "Hub settings") + apiRow("GET", "/api/event", "SSE stream"),
    ),
    1200,
  );

  const models = whiteCard("Data model",
    F("Row", { flex: "row", gap: 10, w: "fill", h: "hug" },
      modelBox("Session", ["id · title · directory", "projectID · modelID · agent", "time.created / updated", "outcome · taskStatus"], D.accent) +
      modelBox("Message", ["id · sessionID · role", "time.created", "parts[]"], D.running) +
      modelBox("Part", ["text · reasoning · tool", "state · input · metadata", "files[] patches"], D.purple) +
      modelBox("Project", ["id · worktree · vcs", "icon · running count", "last activity"], D.warn)) +
    F("Row2", { flex: "row", gap: 10, w: "fill", h: "hug" },
      modelBox("Task", ["sessionID · status", "labels[] (type/scope/risk)", "reviewedAt"], D.cacheRead) +
      modelBox("VirtualMachine", ["id · name · channel", "cpu · memoryMB · diskGB", "status · address · metrics"], D.cacheWrite) +
      modelBox("Device", ["stable id · platform", "app version · first/last seen", "live state"], D.input) +
      modelBox("Usage", ["rolling · weekly · monthly", "resetAt · stale", "cachedAt"], D.output)),
    1200,
  );

  const storage = whiteCard("Storage and events",
    F("Grid", { flex: "row", gap: 16, w: "fill", h: "hug" },
      F("Tables", { flex: "col", gap: 5, w: 520 },
        T("SQLITE TABLES", { size: 8, weight: "bold", color: "#6B7079", letterSpacing: 0.6 }) +
        ["sessions", "messages", "message_parts", "projects", "tasks", "usage_cache", "devices", "settings", "vms"].map((t) =>
          F("T", { flex: "row", items: "center", gap: 5, p: 5, rounded: 5, bg: "#F7F8FA", w: "fill" }, I("lucide:database", 8, D.accent) + T(t, { size: 8.5, color: "#20252C" }))).join("")) +
      F("Events", { flex: "col", gap: 5, w: "fill" },
        T("EVENT FOLDING", { size: 8, weight: "bold", color: "#6B7079", letterSpacing: 0.6 }) +
        ["session.step.* → current step + elapsed", "session.reasoning.* → reasoning preview", "session.text.* → streaming text", "session.tool.* → current tool + command", "session.usage.* → cost + token counts", "permission.* → pending permission", "hub.* → cached data changed"].map((t) =>
          F("E", { flex: "row", items: "center", gap: 5, p: 5, rounded: 5, bg: "#F7F8FA", w: "fill" }, I("lucide:activity", 8, D.running) + T(t, { size: 8.5, color: "#20252C" }))).join(""))),
    1200,
  );

  const security = whiteCard("Security and pairing",
    F("Grid", { flex: "row", gap: 12, w: "fill", h: "hug" },
      ["Bearer token on every request", "Token in ~/.config/opencode/opencodebar-hub.json (owner-only)", "iOS token stored in the keychain", "QR + opencodebar://pair?url&token", "Local socket and discovery files are 0600", "CORS limited to the app origin"].map((t) =>
        F("S", { flex: "row", items: "start", gap: 5, p: 8, rounded: 8, bg: "#F7F8FA", w: 560, h: "hug" }, I("lucide:lock", 9, D.accent) + T(t, { size: 8.5, color: "#3C4450", lineHeight: 12, w: "fill" }))).join("")),
    1200,
  );

  const build = whiteCard("Build and release",
    F("Grid", { flex: "row", gap: 10, w: "fill", h: "hug" },
      ["make hub — build hub + sign VZ helper", "make desktop — build and open the window", "make mobile — simulator, paired", "make mobile-device — physical device", "make hub-tunnel — Cloudflare quick tunnel", "make screenshots — README images", "make deploy — marketing + docs"].map((t) =>
        F("B", { flex: "row", items: "center", gap: 5, p: 7, rounded: 7, bg: "#F7F8FA", w: 560 }, I("lucide:terminal", 9, D.sec) + T(t, { size: 8.5, color: "#3C4450" }))).join("")),
    1200,
  );

  return pageParts({
    title: "Architecture and API",
    subtitle: "One hub between OpenCode and every client. This page is the visual companion to the README's How it works section and the published OpenAPI reference.",
    meta: "Sources: README.md · server/src/** · website/docs/hub/architecture.md · website/docs/hub/api.md · website/docs/hub/security.md",
    width: 2600,
    sections: [
      group("Topology and request flow", "OpenCode stays loopback-only; the hub is the single authenticated door for both apps.", [
        topology + flow,
      ].join("")),
      group("API surface", "Stable mirrored shapes, grouped by domain. WebSocket routes carry terminals and VM consoles.", [
        api,
      ].join("")),
      group("Data and storage", "What the hub caches, and how live events become the activity snapshot.", [
        models + storage,
      ].join("")),
      group("Security and build", "The token never reaches the model provider, and every surface has a reproducible build target.", [
        security + build,
      ].join("")),
    ],
  });
}
