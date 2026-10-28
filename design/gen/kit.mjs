// Shared helpers for the OpenPencil design document.
// Each page module returns a JSX string rendered with `openpencil tool call render`.

export const D = {
  bg: "#161616",
  panel: "#1D1D1D",
  card: "#282828",
  cardHi: "#303030",
  field: "#242424",
  border: "#FFFFFF14",
  borderHi: "#FFFFFF24",
  text: "#FFFFFF",
  sec: "#A0A0A0",
  ter: "#6F6F6F",
  accent: "#4DD9A0",
  accentDim: "#4DD9A024",
  running: "#5CCCFA",
  runningDim: "#5CCCFA22",
  warn: "#F7B84B",
  warnDim: "#F7B84B22",
  danger: "#F7666B",
  dangerDim: "#F7666B22",
  input: "#6B9EFC",
  output: "#59D6A1",
  reasoning: "#C78CFA",
  cacheRead: "#FDB85A",
  cacheWrite: "#F5788C",
  purple: "#A78BFA",
};

export const L = {
  bg: "#F1F3F6",
  panel: "#F7F8FA",
  card: "#FFFFFF",
  cardHi: "#F2F4F7",
  border: "#00000012",
  text: "#1B1F24",
  sec: "#6B7079",
  ter: "#9AA0A8",
  accent: "#0B8F65",
  accentDim: "#0B8F6518",
  running: "#0B7DA6",
  warn: "#A56500",
  danger: "#C22A33",
};

export const esc = (s) =>
  String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

export const txt = (s) =>
  String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/{/g, "&#123;")
    .replace(/}/g, "&#125;");

const attrs = (o) =>
  Object.entries(o)
    .filter(([, v]) => v !== undefined && v !== null && v !== false)
    .map(([k, v]) => (typeof v === "number" ? `${k}={${v}}` : `${k}="${esc(v)}"`))
    .join(" ");

export const F = (name, props, ...children) =>
  `<Frame name="${esc(name)}" ${attrs(props)}>${children.join("")}</Frame>`;

export const T = (s, props = {}) =>
  `<Text name="${esc(props.name || String(s).slice(0, 28) || "Text")}" ${attrs(props)}>${txt(s)}</Text>`;

export const I = (name, size = 14, color = D.sec) =>
  `<Icon name="${esc(name)}" size={${size}} color="${esc(color)}" />`;

export const R = (name, props) => `<Rectangle name="${esc(name)}" ${attrs(props)} />`;

export const chip = (label, color = D.sec, icon) =>
  F(
    "Chip",
    {
      flex: "row",
      items: "center",
      gap: 3,
      px: 7,
      py: 2.5,
      rounded: 99,
      bg: color + "24",
      h: "hug",
      w: "hug",
    },
    (icon ? I(icon, 9, color) : "") +
      T(label, { size: 10, weight: "medium", color, name: "Chip label" }),
  );

export const pill = (label, selected = false, dark = true) =>
  F(
    "Pill",
    {
      flex: "row",
      items: "center",
      justify: "center",
      gap: 4,
      px: 8,
      py: 3.5,
      rounded: 99,
      bg: selected ? (dark ? "#4A4A4A" : "#FFFFFF") : dark ? "#2E2E2E" : "#E9ECF0",
      stroke: selected ? (dark ? "#FFFFFF24" : "#00000010") : "#FFFFFF00",
      strokeWidth: 1,
      w: "hug",
    },
    T(label, {
      size: 10,
      weight: selected ? "semibold" : "regular",
      color: selected ? (dark ? D.text : L.text) : dark ? D.sec : L.sec,
      name: "Pill label",
    }),
  );

export const card = (children, props = {}) =>
  F("Card", {
    flex: "col",
    gap: 8,
    p: 12,
    rounded: 14,
    bg: D.card,
    stroke: D.border,
    strokeWidth: 1,
    w: "fill",
    h: "hug",
    ...props,
  }, children);

export const sectionLabel = (label, trailing = "", color = D.ter) =>
  F(
    "Section label",
    { flex: "row", items: "center", justify: "between", w: "fill", h: "hug" },
    T(label.toUpperCase(), { size: 10, weight: "bold", color, letterSpacing: 0.7 }) + trailing,
  );

export const bar = (pct, color = D.accent, h = 5, track = "#FFFFFF14") =>
  F(
    "Bar",
    { w: "fill", h, rounded: h, bg: track, overflow: "hidden" },
    F("Fill", { w: `${Math.max(0, Math.min(100, pct))}%`, h, rounded: h, bg: color }),
  );

export const iconButton = (icon, color = D.sec, size = 13) =>
  F(
    "Icon button",
    {
      w: 28,
      h: 28,
      rounded: 9,
      bg: "#FFFFFF0A",
      items: "center",
      justify: "center",
    },
    I(icon, size, color),
  );

export const emptyState = (
  icon,
  title,
  subtitle,
  { color = D.sec, h = "hug", w = "fill" } = {},
) =>
  F(
    "Empty state",
    {
      w,
      h,
      flex: "col",
      items: "center",
      justify: "center",
      gap: 10,
      p: 28,
      rounded: 14,
      bg: D.card,
      stroke: D.border,
      strokeWidth: 1,
    },
    F(
      "Icon well",
      {
        w: 44,
        h: 44,
        rounded: 14,
        bg: color + "18",
        items: "center",
        justify: "center",
      },
      I(icon, 22, color),
    ) +
      T(title, { size: 14, weight: "semibold", color: D.text, textAlign: "center" }) +
      T(subtitle, {
        size: 11,
        color: D.sec,
        textAlign: "center",
        lineHeight: 16,
        w: "fill",
      }),
  );

export const notice = (icon, message, color = D.warn) =>
  F(
    "Notice",
    {
      flex: "row",
      items: "start",
      gap: 8,
      p: 10,
      rounded: 12,
      bg: color + "14",
      stroke: color + "33",
      strokeWidth: 1,
      w: "fill",
      h: "hug",
    },
    I(icon, 13, color) +
      T(message, { size: 10, color, lineHeight: 14, w: "fill" }),
  );

export const statTile = (label, value, sub, icon, color = D.accent) =>
  F(
    "Stat tile",
    {
      flex: "col",
      gap: 4,
      p: 12,
      rounded: 14,
      bg: D.card,
      stroke: D.border,
      strokeWidth: 1,
      w: "fill",
      h: "hug",
      grow: 1,
    },
    F(
      "Label row",
      { flex: "row", items: "center", gap: 5 },
      I(icon, 10, color) +
        T(label.toUpperCase(), { size: 9, weight: "bold", color: D.sec, letterSpacing: 0.6 }),
    ) +
      T(value, { size: 24, weight: "bold", color: D.text, letterSpacing: -0.5 }) +
      T(sub, { size: 9, color: D.ter }),
  );

export const listRow = (title, meta, trailing = "", leading = "") =>
  F(
    "List row",
    {
      flex: "row",
      items: "center",
      gap: 9,
      p: 11,
      rounded: 12,
      bg: D.card,
      stroke: D.border,
      strokeWidth: 1,
      w: "fill",
      h: "hug",
    },
    leading +
      F(
        "Body",
        { flex: "col", gap: 3, grow: 1, w: "fill" },
        T(title, { size: 12, weight: "semibold", color: D.text, w: "fill" }) +
          (meta ? T(meta, { size: 9, color: D.sec, w: "fill" }) : ""),
      ) +
      trailing,
  );

export const panelHeader = (sub = "Connected · v2.1.4", dark = true) =>
  F(
    "Panel header",
    { flex: "row", items: "center", gap: 11, w: "fill", h: "hug", p: 20 },
    F(
      "Logo",
      {
        w: 44,
        h: 44,
        rounded: 13,
        bg: dark ? D.accent : L.accent,
        items: "center",
        justify: "center",
      },
      I("lucide:code-xml", 24, dark ? "#0C2018" : "#FFFFFF"),
    ) +
      F(
        "Titles",
        { flex: "col", gap: 3, grow: 1 },
        T("OpenCode", { size: 21, weight: "bold", color: dark ? D.text : L.text }) +
          F(
            "Status",
            { flex: "row", items: "center", gap: 5 },
            F("Dot", { w: 7, h: 7, rounded: 4, bg: D.accent }),
            T(sub, { size: 12, color: dark ? D.sec : L.sec }),
          ),
      ) +
      iconButton("lucide:refresh-cw", dark ? D.sec : L.sec, 15) +
      iconButton("lucide:power", dark ? D.sec : L.sec, 15),
  );

export const panelTabs = (tabs, active, dark = true) =>
  F(
    "Tab wrap",
    { flex: "row", w: "fill", h: "hug", px: 16 },
    F(
    "Tab bar",
    {
      flex: "row",
      items: "center",
      gap: 2,
      p: 3,
      rounded: 12,
      bg: dark ? "#262626" : "#E6E9EE",
      w: "fill",
      h: "hug",
    },
    tabs
      .map((t) => {
        const on = t.label === active;
        return F(
          "Tab",
          {
            flex: "row",
            items: "center",
            justify: "center",
            gap: 4,
            grow: 1,
            px: 4,
            py: 7,
            rounded: 9,
            bg: on ? (dark ? "#3E3E3E" : "#FFFFFF") : "#FFFFFF00",
          },
          I(t.icon, 12, on ? (dark ? D.text : L.text) : dark ? D.sec : L.sec) +
            T(t.label, {
              size: tabs.length > 5 ? 9.5 : 12,
              weight: on ? "semibold" : "medium",
              color: on ? (dark ? D.text : L.text) : dark ? D.sec : L.sec,
            }),
        );
      })
      .join(""),
  ));

export const panel = ({
  tabs,
  active,
  children,
  dark = true,
  sub = "Connected · v2.1.4",
  footer = "3 active",
  w = 800,
  h = 1200,
  name = "Panel",
}) =>
  F(
    name,
    {
      w,
      h,
      flex: "col",
      gap: 0,
      bg: dark ? D.panel : L.panel,
      rounded: 20,
      stroke: dark ? D.border : L.border,
      strokeWidth: 1,
      overflow: "hidden",
    },
    panelHeader(sub, dark) +
      panelTabs(tabs, active, dark) +
      F(
        "Content",
        {
          flex: "col",
          gap: 12,
          px: 20,
          py: 16,
          grow: 1,
          w: "fill",
          overflow: "hidden",
        },
        children,
      ) +
      F(
        "Footer",
        {
          flex: "row",
          items: "center",
          justify: "between",
          px: 20,
          py: 10,
          w: "fill",
          bg: dark ? "#191919" : "#EEF1F5",
          stroke: dark ? "#FFFFFF10" : L.border,
          strokeWidth: 1,
        },
        F(
          "Active",
          { flex: "row", items: "center", gap: 5 },
          F("Dot", { w: 6, h: 6, rounded: 3, bg: D.running }),
          T(footer, { size: 10, color: dark ? D.sec : L.sec }),
        ) + T("Updated just now", { size: 10, color: dark ? D.ter : L.ter }),
      ),
  );

export const statusBar = (dark = true) =>
  F(
    "Status bar",
    {
      flex: "row",
      items: "center",
      justify: "between",
      w: "fill",
      px: 22,
      pt: 12,
      pb: 6,
      h: "hug",
    },
    T("20:35", { size: 12, weight: "semibold", color: dark ? D.text : L.text }),
    F(
      "Indicators",
      { flex: "row", items: "center", gap: 5 },
      I("lucide:signal", 12, dark ? D.text : L.text) +
        I("lucide:wifi", 12, dark ? D.text : L.text) +
        I("lucide:battery-full", 15, dark ? D.text : L.text),
    ),
  );

export const dock = (tabs, active, dark = true) =>
  F(
    "Dock",
    {
      flex: "row",
      items: "center",
      gap: 2,
      mx: 16,
      mb: 10,
      p: 6,
      rounded: 20,
      bg: dark ? "#242424" : "#FFFFFF",
      stroke: dark ? D.border : L.border,
      strokeWidth: 1,
      shadow: dark ? undefined : "0 6 18 #0000001A",
      w: "fill",
      h: "hug",
    },
    tabs
      .map((t) => {
        const on = t.label === active;
        return F(
          "Dock item",
          {
            flex: "col",
            items: "center",
            justify: "center",
            gap: 3,
            grow: 1,
            py: 5,
            rounded: 12,
            bg: on ? (dark ? "#FFFFFF14" : "#F0F3F7") : "#FFFFFF00",
          },
          I(t.icon, 14, on ? (dark ? D.text : L.text) : dark ? D.sec : L.sec) +
            T(t.label, {
              size: 8,
              weight: "semibold",
              color: on ? (dark ? D.text : L.text) : dark ? D.sec : L.sec,
            }),
        );
      })
      .join(""),
  );

export const phone = ({
  title,
  sub = "",
  children,
  active = "Live",
  tabs,
  dark = true,
  footer = true,
  h = 896,
  w = 414,
  name = "iPhone",
}) =>
  F(
    name,
    {
      w,
      h,
      flex: "col",
      gap: 0,
      bg: dark ? "#121212" : "#F4F6F9",
      rounded: 34,
      stroke: dark ? D.border : L.border,
      strokeWidth: 1,
      overflow: "hidden",
    },
    statusBar(dark) +
      F(
        "Title bar",
        {
          flex: "row",
          items: "center",
          justify: "between",
          w: "fill",
          px: 20,
          py: 8,
          h: "hug",
        },
        T(title, { size: 16, weight: "semibold", color: dark ? D.text : L.text }) +
        (sub
          ? F(
              "Right",
              { flex: "row", items: "center", gap: 6 },
              F("Dot", { w: 6, h: 6, rounded: 3, bg: D.accent }) +
                T(sub, { size: 10, weight: "medium", color: D.accent }),
            )
          : ""),
      ) +
      F(
        "Content",
        {
          flex: "col",
          gap: 10,
          px: 16,
          py: 8,
          grow: 1,
          w: "fill",
          overflow: "hidden",
        },
        children,
      ) +
      (footer ? dock(tabs || iosTabs, active, dark) : ""),
  );

export const iosTabs = [
  { label: "Tasks", icon: "lucide:list-checks" },
  { label: "Live", icon: "lucide:radio" },
  { label: "Projects", icon: "lucide:folder" },
  { label: "Usage", icon: "lucide:bar-chart-3" },
  { label: "Host", icon: "lucide:monitor" },
  { label: "VMs", icon: "lucide:server" },
  { label: "Settings", icon: "lucide:settings" },
];

export const macTabs3 = [
  { label: "Live", icon: "lucide:radio" },
  { label: "Usage", icon: "lucide:bar-chart-3" },
  { label: "Projects", icon: "lucide:folder" },
];
export const macTabs4 = [...macTabs3, { label: "Settings", icon: "lucide:settings" }];
export const macTabs5 = [
  { label: "Tasks", icon: "lucide:list-checks" },
  ...macTabs4,
];
export const macTabs7 = [
  { label: "Tasks", icon: "lucide:list-checks" },
  { label: "Live", icon: "lucide:radio" },
  { label: "Usage", icon: "lucide:bar-chart-3" },
  { label: "Projects", icon: "lucide:folder" },
  { label: "System", icon: "lucide:monitor" },
  { label: "VMs", icon: "lucide:server" },
  { label: "Settings", icon: "lucide:settings" },
];

export const screen = (label, node, note = "") =>
  F(
    "Screen",
    { flex: "col", gap: 10, w: "hug", h: "hug", items: "start" },
    F(
      "Caption",
      { flex: "col", gap: 2, w: "fill" },
      T(label, { size: 13, weight: "semibold", color: "#2B3038" }) +
        (note ? T(note, { size: 10, color: "#6B7079", w: "fill" }) : ""),
    ) + node,
  );

export const row = (name, children, props = {}) =>
  F("Row", { flex: "row", gap: 36, items: "start", w: "fill", h: "hug", ...props }, children);

export const pageHeader = ({ title, subtitle, meta = "" }) =>
  F(
    "Page header",
    { flex: "col", gap: 10, w: "fill", h: "hug", pb: 12 },
    F(
      "Eyebrow",
      { flex: "row", items: "center", gap: 8 },
      F("Bar", { w: 34, h: 4, rounded: 2, bg: D.accent }),
      T("OPENCODEBAR · DESIGN MIRROR", {
        size: 11,
        weight: "bold",
        color: "#5A626D",
        letterSpacing: 1.4,
      }),
    ) +
      T(title, { size: 42, weight: "bold", color: "#171B21", letterSpacing: -1.2 }) +
      T(subtitle, { size: 15, color: "#4C545E", lineHeight: 22, w: 1500 }) +
      (meta ? T(meta, { size: 11, color: "#7A828C", letterSpacing: 0.2 }) : ""),
  );

export const page = ({ title, subtitle, meta = "", width = 3000, children, bg = "#E9ECEF" }) =>
  F(
    "Page",
    { w: width, h: "hug", flex: "col", gap: 36, p: 72, bg },
    pageHeader({ title, subtitle, meta }) + children,
  );

// Large pages render as a small root plus independent sections, so no single
// MCP call has to carry the whole page.
export const pageParts = ({ title, subtitle, meta = "", width = 3000, sections, bg = "#E9ECEF" }) => ({
  root: F(
    "Page",
    { w: width, h: "hug", flex: "col", gap: 36, p: 72, bg },
    pageHeader({ title, subtitle, meta }),
  ),
  sections,
});

// A labelled group of screens inside a page.
export const group = (label, note, children, props = {}) =>
  F(
    "Group",
    { flex: "col", gap: 16, w: "fill", h: "hug", ...props },
    F(
      "Group header",
      { flex: "col", gap: 3, w: "fill" },
      T(label, { size: 22, weight: "bold", color: "#20252C" }) +
        (note ? T(note, { size: 12, color: "#646C77", w: 1100 }) : ""),
    ) + row(label + " row", children),
  );

// Small architecture boxes for the diagram pages.
export const node = (title, lines, color = D.accent, w = 260) =>
  F(
    "Node",
    {
      flex: "col",
      gap: 5,
      p: 14,
      rounded: 12,
      bg: "#FFFFFF",
      stroke: "#00000014",
      strokeWidth: 1,
      w,
      h: "hug",
    },
    F(
      "Node title",
      { flex: "row", items: "center", gap: 7 },
      F("Dot", { w: 8, h: 8, rounded: 4, bg: color }),
      T(title, { size: 12, weight: "bold", color: "#1B1F24" }),
    ) + lines.map((l) => T(l, { size: 9.5, color: "#626A75", lineHeight: 14 })).join(""),
  );

export const arrow = (label = "") =>
  F(
    "Arrow",
    { flex: "col", items: "center", gap: 3, w: 90, h: "hug" },
    T(label, { size: 9, color: "#6B7079" }) +
      F(
        "Line",
        { flex: "row", items: "center", w: "fill", h: 12 },
        F("Shaft", { w: "fill", h: 1, bg: "#9AA0A8" }),
        I("lucide:chevron-right", 12, "#9AA0A8"),
      ),
  );
