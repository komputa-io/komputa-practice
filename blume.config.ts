import { defineConfig } from "blume";
import { cloudflare, node } from "blume/deploy";

export default defineConfig({
  title: "Komputa Practice",
  description:
    "How Komputa builds software with coding agents: the quality funnel, the life of a program, the rules, the hooks and the evidence behind each rule.",
  content: {
    // .site/ is built by scripts/docs-prepare.mjs from site/, four repo
    // files and three generated reference pages. Nothing else is published:
    // not docs/handoffs/, not .audit/.
    root: ".site",
  },
  // The Komputa brand v1. public/brand/README.md says where the files come from.
  logo: { image: "/brand/komputa-icon.svg", text: "Komputa Practice" },
  theme: {
    accent: { light: "#C2410C", dark: "#FF5A1F" },
    background: { light: "#F4F3EF", dark: "#111111" },
    fonts: {
      display: { name: "Outfit", weights: [600, 700, 800] },
      body: "inter",
      mono: "jetbrains-mono",
    },
  },
  navigation: {
    // The way to hire us from every page: a stranger who likes what they read reaches komputa.io.
    cta: { label: "Work with Komputa", href: "https://komputa.io" },
    // A tab is added with its first page. docs:smoke checks each tab root.
    tabs: [
      { label: "Get started", path: "/start", icon: "rocket" },
      { label: "Guides", path: "/guides", icon: "map" },
      { label: "Explanation", path: "/explanation", icon: "lightbulb" },
      { label: "Reference", path: "/reference", icon: "book-open" },
    ],
  },
  agents: {
    llmsTxt: {
      details:
        "Search these docs before you invent a herdr skill script, hook, rule or file name of Komputa Practice.",
    },
    mcp: {
      enabled: true,
      instructions:
        "Search these docs before you invent a script, hook or rule of Komputa Practice. The Hooks page lists each hook header; the Skills and Template questions pages list each skill and each template question.",
    },
  },
  // /reference/scripts held the hooks page until it was renamed.
  redirects: [{ from: "/reference/scripts", to: "/reference/hooks", status: 301 }],
  ai: { openInChat: false },
  // DOCS_TARGET=cloudflare builds the Worker that .github/workflows/docs-deploy.yml deploys to
  // docs.komputa.io. Every other build, docs:smoke's included, is the Node server.
  deployment:
    process.env.DOCS_TARGET === "cloudflare"
      ? cloudflare({ site: process.env.DOCS_SITE_URL ?? "https://docs.komputa.io" })
      : node({ site: process.env.DOCS_SITE_URL ?? "http://localhost:4321" }),
});
