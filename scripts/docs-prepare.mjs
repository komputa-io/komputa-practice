// Builds the content folder .site/ and the figure folder public/figures/ from
// the repo's own files, so the site never holds a second copy of a page.
//   node scripts/docs-prepare.mjs
// .site/ gets: the pages in site/, four repo files with a title added (docs/model-selection.md,
// docs/context-economics.md, docs/framework-evidence.md, rules/working-rules.md)
// and the generated scripts reference. Nothing else in the repo is published.
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const OUT = ".site";
const FIGURES = "public/figures";

// [source file, page route inside .site/, title, description]
const IMPORTED = [
  ["docs/model-selection.md", "explanation/model-selection.md", "Model selection", "How each agent's model is chosen."],
  ["docs/context-economics.md", "explanation/context-economics.md", "Context economics", "Where the tokens go when agents run as workers."],
  ["docs/framework-evidence.md", "explanation/framework-evidence.md", "Framework evidence", "What the practice caught, what it cost, and how the next period is measured."],
  ["rules/working-rules.md", "reference/rules.md", "The rules", "The working rules, and what holds each one."],
];

rmSync(OUT, { recursive: true, force: true });
rmSync(FIGURES, { recursive: true, force: true });
cpSync("site", OUT, { recursive: true });

for (const [source, target, title, description] of IMPORTED) {
  const text = readFileSync(source, "utf8");
  const match = /^# (.+)\n/.exec(text);
  if (!match) throw new Error(`${source}: no first-line "# Title"`);
  const body = text
    .slice(match[0].length)
    // A figure next to the page names its file; the site serves figures at /figures/.
    .replace(/\]\(([a-z0-9-]+\.png)\)/g, "](/figures/$1)");
  const quoted = JSON.stringify(title);
  mkdirSync(dirname(join(OUT, target)), { recursive: true });
  writeFileSync(join(OUT, target), `---\ntitle: ${quoted}\ndescription: ${JSON.stringify(description)}\n---\n\n${body}`);
}

mkdirSync(FIGURES, { recursive: true });
for (const name of readdirSync("docs")) {
  if (name.endsWith(".png")) cpSync(join("docs", name), join(FIGURES, name));
}

execFileSync("bash", ["scripts/docs-reference.sh", join(OUT, "reference", "scripts.md")], { stdio: "inherit" });
console.log(`docs:prepare: wrote ${OUT}/ and ${FIGURES}/`);
