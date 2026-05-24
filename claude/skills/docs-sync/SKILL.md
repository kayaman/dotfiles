---
name: docs-sync
description: >-
  Turn a coding/dev session into a tutorial-style learning note in the user's
  Obsidian vault, then link it from that day's daily note. Use this whenever the
  user wants to capture, document, write up, or "sync" what was worked on so they
  can learn from it later — phrases like "document this session", "sync the docs",
  "write this up to my vault/Obsidian", "make a note about what we did", "save this
  as a tutorial", or "add this to my daily note". Also offer it proactively after a
  substantial piece of work (a feature shipped, an architecture figured out, a tricky
  bug solved, a new tool/API learned) so the knowledge doesn't evaporate. The note
  teaches the topic — context, solution architecture (with Mermaid), commented code
  snippets, decisions, and gotchas — not just a changelog of what happened.
---

# docs-sync

Capture the *understanding* gained in a session as a standalone teaching note in
the Obsidian vault, and surface it from the daily note so each day becomes an index
of what was learned. The reader six months from now should be able to re-learn the
topic from the note alone — without the repo, without this conversation.

## Vault layout (fixed)

- **Vault root:** `/home/kayaman/Documents/Obsidian/marco`
- **Learning notes:** one file per topic at the vault root, named by **topic only**
  (e.g. `Bundling aws-cli v2 in the installer.md`). No date prefix — the date lives
  in frontmatter and the daily-note link. Title-case the topic; use spaces, not
  kebab-case, so it reads naturally and `[[wikilinks]]` resolve cleanly.
- **Daily note:** `<vault-root>/YYYY-MM-DD.md` (Obsidian's default daily note, at the
  root). Today's date is available in the environment context.

If a path looks wrong (vault moved, folder renamed), surface that and ask rather than
writing to a guessed location.

## Workflow

1. **Identify the topic and gather material.** Decide the one thing this note teaches.
   Pull from the conversation (the problem, the reasoning, decisions, dead ends) and,
   when a repo is present, from git — `git log`, `git diff`, changed files — to ground
   the snippets in what was actually built. If the session covered several unrelated
   things, prefer one note per topic over one sprawling note; each should stand alone.

2. **Write the learning note.** Use the template in `assets/note-template.md`. Fill
   every section that applies; drop sections that genuinely don't (don't pad). The bar
   is *teaching*, not *logging*: explain why, not just what. See "What makes a good
   note" below.

3. **Draw the architecture as Mermaid.** Almost every non-trivial topic has a shape —
   a data flow, a request path, a component layout, a state machine. Draw it. Follow
   `references/diagram-conventions.md` (per-tier color palette, edge weight = how hot
   the data path is). A diagram the reader can scan beats three paragraphs of prose.

4. **Link it from the daily note.** Ensure `<vault-root>/YYYY-MM-DD.md` exists (create
   it with the frontmatter below if not), then add a `## <Topic>` section with a short
   bullet — one line of what + why — that links to the note via `[[Topic]]`. The daily
   note is the spine; the topic note is the muscle.

5. **Report what you wrote** — the note path and the daily-note line — so the user can
   jump straight to it.

## Daily note format

Match the user's existing convention exactly:

```markdown
---
title: "YYYY-MM-DD"
pubDate: YYYY-MM-DD
tags: [daily]
---

# YYYY-MM-DD

## <Topic> — <short subtitle>

- One line: what was done and why it mattered. See [[Topic]].
```

When the daily note already exists, **append** a new `## <Topic>` section — never rewrite
or reorder what's already there. If a section for this topic already exists from earlier
today, add a bullet under it instead of duplicating the heading.

## What makes a good note

- **Lead with the problem.** Start from why this came up — the constraint, the bug, the
  goal. Context is what makes the solution make sense later.
- **Teach the reasoning, not the keystrokes.** "We used a CloudFront → GitHub proxy so the
  install URL stays stable even if the release asset moves" teaches; "ran `curl ...`"
  doesn't. Capture the *why* behind each decision and the alternatives you rejected.
- **Snippets must be self-explanatory.** Every code block gets a sentence before it saying
  what it does and why it's shaped that way. Prefer the real snippet from the session over
  invented examples.
- **Write down the gotchas.** The thing that bit you — the silent failure, the wrong default,
  the convention you only discovered by breaking it — is often the most valuable part.
- **Link generously.** Use `[[wikilinks]]` to related notes in the vault, even if the target
  doesn't exist yet — an unresolved link marks something worth writing later and grows the
  graph. Link to repos and external docs with markdown links.

## Reference files

- `assets/note-template.md` — the structure for the learning note. Read it before writing.
- `references/diagram-conventions.md` — Mermaid architecture conventions (palette, edge
  weight, side-by-side option diagrams). Read it before drawing.
