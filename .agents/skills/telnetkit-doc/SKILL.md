---
name: telnetkit-doc
description: Create, restructure, review, or validate TelnetKit Markdown documents across the AGENTS.md, architecture, public API, PRD, README, and skill tiers, including word budgets, link resolution, and the split between designed and verified statements. Use for a new or revised TelnetKit document, a documentation-quality review, a placement decision, or a check that links and budgets still hold.
---

# TelnetKit documentation

English | [中文](SKILL.zh.md)

## Summary

TelnetKit documentation has one home per fact and states whether each fact is designed or verified. This workflow places a document in its tier, writes it to that tier's rules, and validates it. Use [telnetkit-prose-standard](../telnetkit-prose-standard/SKILL.md) for sentence-level judgment and contract coverage; this skill owns placement, structure, budgets, and checks.

## Table of Contents

- [Inputs and exclusions](#inputs-and-exclusions)
- [Workflow](#workflow)
- [Tier and placement decisions](#tier-and-placement-decisions)
- [Structure of a document](#structure-of-a-document)
- [Rules](#rules)
- [Validation](#validation)
- [Dev Note](#dev-note)

## Inputs and exclusions

Require a scope: a document path, a directory, or a named change. If the scope is "documentation", list the documents that exist and ask which one, rather than rewriting the corpus.

Exclude the `libtelnet/` submodule from prose edits, and treat `Sources/CLibTelnet/UPSTREAM.md` as a fact record rather than prose.

## Workflow

1. Read the [root AGENTS.md](../../../AGENTS.md), [docs/AGENTS.md](../../../docs/AGENTS.md), and the target document. Read the code, tests, or dependency that the document makes claims about.
2. Classify the document's job: standing order, design map, caller contract, requirement, consumer contract, or workflow. The [tier table](../../../docs/AGENTS.md#the-tier-taxonomy-one-home-per-fact) fixes where that job lives.
3. Decide designed versus verified for the statements being added. A statement read from upstream is an upstream fact; a statement reproduced by running a command is verified; everything else is designed and is marked as the [root AGENTS.md](../../../AGENTS.md#design-status) requires.
4. Draft in the structure below, in the tier's own voice: a standing order is one to three lines with a link; a design map is an ordered map, not an API catalog; a caller contract states each member's outcome and failures.
5. Move any fact that belongs to another tier to its owner and leave one link. Delete a duplicated rule rather than rephrasing it.
6. Measure the document against its [ceiling](../../../docs/AGENTS.md#wordcount-budgets) and apply the relocate-condense-raise order.
7. Run the validation steps, then re-read the full diff once for correctness and once for length.

## Tier and placement decisions

| Decision | Owner | Common mistake |
|---|---|---|
| "Do not force-unwrap peer data" | Root `AGENTS.md` | Writing the reason and an example into the standing order instead of linking the architecture |
| "The handler copies inside the callback" | `docs/architecture.md` | Repeating it in `AGENTS.md` and in `public-api.md` |
| "The library supports macOS 15 and iOS 18" | `docs/architecture.md` (Platform support) | Restating the platform matrix in the README and in the platform-floor rule |
| "`send(text:)` throws `.notConnected` after close" | `docs/public-api.md` | Leaving it only in the PRD, where a caller will not look |
| "FR-CONN-03 requires a configurable connect timeout" | `PRD.md` | Restating requirement identifiers inside architecture |
| "Connect to a local echo server in five commands" | `README.md` | Putting contributor procedure in the README |
| "How to vendor or upgrade libtelnet" | `.agents/skills/` | Writing the procedure as a section of `architecture.md` |

A new document is created only when an existing tier cannot own its job. Extend an existing document before adding a file.

## Structure of a document

A reference document opens with a one-paragraph statement of its subject and scope, then a `## Table of Contents` when it has more than four sections, then sections ordered from orientation to detail. `README.md` is the one tutorial: it opens with what the library does and a runnable quick start, and it defers design and requirement detail by link.

A skill document carries YAML frontmatter with `name` and `description`, a `## Summary`, a `## Table of Contents`, the workflow, the decision rules, a `## Validation` section, and a final `## Dev Note` that says `None.` unless a genuinely open question exists. Keep the workflow and the rules separate: a step says what to do, a rule says what constrains it.

## Rules

- One physical line per paragraph, so a diff shows a changed sentence rather than a reflowed block.
- Link a fact's owner instead of restating it. A second statement of one rule is a defect in the copy.
- A byte-level claim shows the bytes and the resulting Swift value in the same paragraph as the test that proves it.
- A number has a unit and an owner: `65_536` bytes in `inboundBufferLimit`, `10 s` in `connectTimeout`.
- Do not annotate status in a heading. Status lives in the [design-status rule](../../../AGENTS.md#design-status) and the PRD milestone table.
- Code fences carry a language tag; a `swift` fence must be valid Swift, and a `text` fence is for composition diagrams.
- Every relative link resolves to a file in this repository; an upstream file is referenced by URL.
- A Chinese counterpart updates in the same change, with the same heading sequence, table and code structure, and physical line count; [PRD.md](../../../PRD.md) pairs with [PRD.zh.md](../../../PRD.zh.md) like every other document.

## Validation

Run what applies and report the observed result for each:

1. Link resolution: for every relative Markdown link in the changed files, `test -e "$(dirname <file>)/<target-path>"` succeeds. Report a link whose target is a directory or an anchor as a failure, since only files are checked here.
2. Word budget: `wc -w <file>` is within the ceiling in [docs/AGENTS.md](../../../docs/AGENTS.md#wordcount-budgets), with 5% headroom for `AGENTS.md`, `docs/AGENTS.md`, `docs/architecture.md`, and `docs/public-api.md`.
3. Heading uniqueness: no two headings in one file produce the same anchor.
4. Statement kind: every present-tense behavior claim in a changed file is verified, upstream, or explicitly designed; report any that is none of the three.
5. Duplication: grep a distinctive phrase from each new rule across the repository and confirm it appears once as a rule, with links elsewhere.
6. Test plan: every command in it was run once, and each suite names the platforms it runs on; a command that fails on this machine is recorded with its error rather than softened.
7. Bilingual pair: both sides exist, the structural line kinds match line for line, and `wc -l` reports the same count for each side.
8. No hand edit inside `Sources/CLibTelnet/`.

## Dev Note

None.
