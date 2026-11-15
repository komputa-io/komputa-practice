// Builds the content folder .site/ and the figure folder public/figures/ from
// the repo's own files, so the site never holds a second copy of a page.
//   node scripts/docs-prepare.mjs
// .site/ gets: the pages in site/, five repo files with a title added (docs/model-selection.md,
// docs/context-economics.md, rules/working-rules.md, rules/leadonly-rules.md, archive/README.md)
// and four generated reference pages: the hooks (from their header comments), the
// skills (from each SKILL.md front matter), the template questions (from copier.yml) and the
// changes (from git: it needs the full history and the tags).
// Nothing else in the repo is published.
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const OUT = ".site";
const FIGURES = "public/figures";

// [source file, page route inside .site/, title, description]
const IMPORTED = [
  ["docs/model-selection.md", "explanation/model-selection.md", "Model selection", "How each agent's model is chosen."],
  ["docs/context-economics.md", "explanation/context-economics.md", "Context economics", "Where the tokens go when agents run as workers."],
  ["rules/working-rules.md", "reference/rules.md", "The rules", "The working rules, and what holds each one."],
  ["rules/leadonly-rules.md", "reference/lead-rules.md", "Lead-only rules", "The extra rules for a lead that starts workers."],
  ["archive/README.md", "explanation/archive.md", "The archive", "What the practice no longer runs, and why."],
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

execFileSync("bash", ["scripts/docs-reference.sh", join(OUT, "reference", "hooks.md")], { stdio: "inherit" });

const GENERATED = "This page is generated. Do not edit it: change the source it names, and the next build changes this page.";

// A front matter value on one line, plain or double-quoted, as each SKILL.md writes it.
function frontMatter(text, key, source) {
  const block = /^---\n([\s\S]*?)\n---\n/.exec(text);
  const line = block?.[1].split("\n").find((l) => l.startsWith(`${key}:`));
  if (!line) throw new Error(`${source}: no "${key}:" in the front matter`);
  const value = line.slice(key.length + 1).trim();
  return value.startsWith('"') ? JSON.parse(value) : value;
}

const skills = readdirSync("skills", { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => join("skills", entry.name, "SKILL.md"))
  .sort()
  .map((source) => {
    const text = readFileSync(source, "utf8");
    const name = frontMatter(text, "name", source);
    return `### \`${name}\`\n\nSource: \`${source}\`\n\n${frontMatter(text, "description", source)}\n`;
  });
writeFileSync(
  join(OUT, "reference", "skills.md"),
  `---\ntitle: "Skills"\ndescription: "Every skill in the practice, and when an agent uses it."\n---\n\n${GENERATED}\n\n${skills.join("\n")}`,
);

// copier.yml: each question is a key at the start of a line whose block holds help:, and maybe
// default:, when: and choices: (inline [a, b], or one "label: value" line for each choice).
function templateQuestions(text) {
  const questions = [];
  let current;
  let folding = false;
  let listing = false;
  for (const line of text.split("\n")) {
    const key = /^([a-z][a-z0-9_]*):\s*$/.exec(line);
    if (key) {
      current = { name: key[1], help: "", fallback: undefined, when: undefined, choices: [] };
      questions.push(current);
      folding = false;
      listing = false;
      continue;
    }
    if (!current) continue;
    if (/^\S/.test(line)) {
      current = undefined;
      continue;
    }
    const field = /^ {2}(help|default|when|choices):\s*(.*)$/.exec(line);
    if (field) {
      folding = field[1] === "help" && field[2] === ">-";
      listing = field[1] === "choices" && field[2] === "";
      if (field[1] === "choices" && field[2].startsWith("[")) {
        current.choices = field[2].slice(1, -1).split(",").map((c) => c.trim());
      }
      if (field[1] === "help") current.help = folding ? "" : field[2];
      if (field[1] === "default") current.fallback = field[2];
      if (field[1] === "when") current.when = field[2].replace(/^"|"$/g, "");
      continue;
    }
    if (folding && /^ {4}\S/.test(line)) current.help = `${current.help} ${line.trim()}`.trim();
    else if (listing && /^ {4}\S/.test(line)) current.choices.push(line.trim().split(/:\s+/).at(-1));
    else if (/^ {2}\S/.test(line)) {
      folding = false;
      listing = false;
    }
  }
  return questions;
}

const cell = (text) => text.replaceAll("|", "\\|");
// A computed value (`when: false`) is never asked, so it is not a question.
const questions = templateQuestions(readFileSync("copier.yml", "utf8")).filter((q) => q.when !== "false");
if (questions.length === 0 || questions.some((q) => !q.help)) throw new Error("copier.yml: a question has no help: line");
const rows = questions.map((q) => {
  const help = /[.?!]$/.test(q.help) ? q.help : `${q.help}.`;
  const choices = q.choices.length ? ` Choices: ${q.choices.map((c) => `\`${cell(c)}\``).join(", ")}.` : "";
  const when = q.when ? ` Asked only when \`${cell(q.when)}\`.` : "";
  const fallback = q.fallback === undefined ? "none" : `\`${cell(q.fallback)}\``;
  return `| \`${q.name}\` | ${cell(help)}${choices}${when} | ${fallback} |`;
});
writeFileSync(
  join(OUT, "reference", "template-questions.md"),
  `---\ntitle: "Template questions"\ndescription: "Every question that copier copy asks, from copier.yml."\n---\n\n${GENERATED} The source is \`copier.yml\`.\n\nThe environment file answers \`vault_command\` and \`forge\` for every repo. A question with no default needs an answer: each one is a decision.\n\n| Question | What it asks | Default |\n|---|---|---|\n${rows.join("\n")}\n`,
);
// The changes: each pull request merged into main, newest first, under the version tag it shipped in. A pull request
// reaches main as a merge commit ("Merge pull request #7 from …", "Merges PR #7 from …", its title in the body) or as
// a squash commit ("Its title (#7)"). Other commits on main are not listed.
const git = (...args) => execFileSync("git", args, { encoding: "utf8" }).trim();
if (git("rev-parse", "--is-shallow-repository") === "true") {
  throw new Error("the changes page needs the full history and the tags: check out with fetch-depth: 0");
}
function pulls(range) {
  return git("log", "--first-parent", "--date=short", "--format=%ad%x1f%s%x1f%b%x1e", range)
    .split("\x1e")
    .map((record) => record.trim())
    .filter(Boolean)
    .flatMap((record) => {
      const [date, subject, body = ""] = record.split("\x1f");
      const merged = /^Merges? (?:pull request|PR) #(\d+)/.exec(subject);
      if (merged) return [{ date, number: merged[1], title: body.trim().split("\n")[0] || subject }];
      const squashed = /^(.+) \(#(\d+)\)$/.exec(subject);
      return squashed ? [{ date, number: squashed[2], title: squashed[1] }] : [];
    });
}
const versions = [];
let previous;
for (const tag of git("tag", "--list", "v*", "--sort=v:refname").split("\n").filter(Boolean)) {
  const date = git("log", "-1", "--date=short", "--format=%ad", tag);
  versions.unshift({ heading: `${tag} (${date})`, items: pulls(previous ? `${previous}..${tag}` : tag) });
  previous = tag;
}
const unreleased = pulls(previous ? `${previous}..HEAD` : "HEAD");
if (unreleased.length) versions.unshift({ heading: "Not released yet", items: unreleased });
const changes = versions
  .map((v) => `## ${v.heading}\n\n${v.items.map((p) => `- ${p.date} · #${p.number} ${p.title}`).join("\n") || "- No pull request."}\n`)
  .join("\n");
writeFileSync(
  join(OUT, "reference", "changes.md"),
  `---\ntitle: "Changes"\ndescription: "Every pull request merged into the practice, under the version it shipped in."\n---\n\n${GENERATED} The source is the git history of \`main\` and its version tags.\n\n${changes}`,
);
console.log(`docs:prepare: wrote ${OUT}/ and ${FIGURES}/`);
