import { defineConfig } from "blume";
import { node } from "blume/deploy";

export default defineConfig({
  title: "Komputa agent practice",
  description:
    "How Komputa runs coding agents as pull-request owners: the quality funnel, the life of a program, the scripts and the rules.",
  content: {
    // .site/ is built by scripts/docs-prepare.mjs from site/, three repo
    // files and the generated scripts reference. Nothing else is published:
    // not docs/handoffs/, not .audit/.
    root: ".site",
  },
  navigation: {
    // The practice has no tutorials or how-to pages yet, so two of the four
    // Diátaxis tabs: Explanation and Reference.
    tabs: [
      { label: "Explanation", path: "/explanation", icon: "lightbulb" },
      { label: "Reference", path: "/reference", icon: "book-open" },
    ],
  },
  agents: {
    llmsTxt: {
      details:
        "Search these docs before you invent a herdr skill script, hook, rule or file name of the Komputa agent practice.",
    },
    mcp: {
      enabled: true,
      instructions:
        "Search these docs before you invent a script, hook or rule of the Komputa agent practice. The Hooks reference page lists each hook header.",
    },
  },
  ai: { openInChat: false },
  deployment: node({ site: process.env.DOCS_SITE_URL ?? "http://localhost:4321" }),
});
