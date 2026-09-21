# AGENTS.md — The documentation standard

English | [中文](AGENTS.zh.md)

This file defines TelnetKit document tiers, placement, writing rules, and word ceilings. Use [telnetkit-doc](../.agents/skills/telnetkit-doc/SKILL.md) for placement and validation. Standing orders live in the [root AGENTS.md](../AGENTS.md).

## Document structure

These rules apply to human-facing documents, not to vendored upstream files, which keep their upstream form.

Classify every in-scope document as a tutorial or a reference. A tutorial follows an ordered path to an outcome and introduces only what each step needs; the [README quick start](../README.md) is the only tutorial. A reference defines a lookup scope and states current behavior without a teaching sequence. Separate substantial tutorial and reference content, and label a section when either part is small.

A document's subject fixes its scope: describe that subject at its own detail, direct children by purpose and responsibility, and link the owning descendant for lower-level detail. A reference may be exhaustive only about its own subject. A diagram may carry a sequence or a composition; it never carries a rule that prose must also state.

Author in this order: locate the document in the tier table; set its permitted detail; choose tutorial or reference; order tutorial concepts by prerequisite; relocate descendant-owned detail; replace lower-level explanation with a link to its owner.

## The tier taxonomy: one home per fact

Each fact has one home: the tier whose job it is. Elsewhere, link there. A statement that exists in two tiers is a defect in one of them.

| Tier | Job | Does NOT belong there |
|---|---|---|
| [Root AGENTS.md](../AGENTS.md) | Standing orders an agent needs in every session: identity, commands, non-negotiable constraints, conventions, one to three lines each, linking the owning document | Worked examples, requirement detail, API catalogs, anything restated from a linked owner |
| [docs/architecture.md](architecture.md) | Ordered map of the design: layers, ownership, concurrency model, event flow, extension points; read before changing `Sources/` | Type-by-type API contracts (→ public-api.md), requirement identifiers and acceptance criteria (→ PRD.md), decision history |
| [docs/public-api.md](public-api.md) | The caller contract: every public type, method, property, and enum case with its preconditions, failures, ordering, and cancellation behavior | Requirements and priorities (→ PRD.md), internal design (→ architecture.md), test inventories (→ test files) |
| [PRD.md](../PRD.md) | Requirements: goals, user stories, functional and non-functional requirements with identifiers, acceptance criteria, test-case inventory, demo scope, milestones, risks | API signatures as the contract of record (→ public-api.md), architecture rationale (→ architecture.md) |
| [README.md](../README.md) | The consumer contract: what the library does, install, a runnable quick start, supported platforms, known limitations, security stance | Contributor procedure, internal design, requirement traceability |
| [.agents/skills/](../.agents/skills/) | Reusable workflows and decision standards for repeatable tasks | Product contracts, requirement identifiers, runtime behavior |
| [Sources/CLibTelnet/UPSTREAM.md](../Sources/CLibTelnet/UPSTREAM.md) | Vendored source provenance: upstream URL, branch, commit, version, copy date, local-modification statement | Build instructions, design rationale |

Placement: a requirement → PRD; a caller contract → public-api.md; a design decision that constrains code → architecture.md; a repeatable procedure → a skill; a standing rule → root AGENTS.md with a link to its owner; a consumer-visible fact → README.

## Writing rules

- **State current behavior in the present tense.** Mark an unimplemented design `Designed` and write it as a requirement, per the [design-status rule](../AGENTS.md#design-status). Keep history in commits, pull requests, and the PRD milestone table.
- **One physical line per paragraph.** Use editor soft-wrap; code blocks, tables, and list structure keep their formatting.
- **One home per term.** Define a term once, in the [glossary](public-api.md#glossary), and reuse it. A second name for one concept is a defect.
- **Name the mechanism.** Write the exact function, type, file, byte sequence, or command: `TelnetChannelHandler` copies the buffer inside the callback, not "the layer normalizes it".
- **Byte-level claims show bytes.** State the wire bytes in hexadecimal and the resulting Swift value, in the paragraph that names the proving test.
- **Complete contracts, not reasoning transcripts.** Keep behavior, failure, timing, ownership, modality, exceptions, and consequence; delete derivation paths, test walkthroughs, review history, and restatement of code or of a linked owner.
- **Requirements stay testable.** A PRD requirement names an observable outcome that a named test can assert; do not add one that no test can distinguish.
- **Code maps explicitly.** A documented mapping between a Swift value and a wire code is exhaustive; name an unmatched code instead of writing "and others".
- **No status decoration.** Do not annotate a heading with "implemented" or "WIP"; the design-status rule and the milestone table carry status.
- **Emphasis is reserved.** Bold marks the clause that changes behavior, not a whole rule set.

## Wordcount budgets

The ceilings below are guardrails, not reduction targets. Measure with `wc -w` on the file and keep at least 5% headroom while a document is at or under its ceiling.

| Document | Ceiling (words) |
|---|---|
| `AGENTS.md` | 1,400 |
| `docs/AGENTS.md` | 1,500: this file also owns the bilingual pairing mechanics |
| `docs/architecture.md` | 1,800 |
| `docs/public-api.md` | 3,200: the caller contract is exhaustive about every public symbol, and a member table row costs words that cannot be relocated without losing the contract |
| `README.md` | 900 |
| A skill under `.agents/skills/*/SKILL.md` | 1,400 |
| `PRD.md` | unbudgeted: it owns requirement detail |

When a document exceeds its ceiling, apply this order and stop at the first step that clears it:

1. **Relocate** content that belongs in another tier, leaving a one-line link.
2. **Condense** content that belongs here but carries avoidable words.
3. **Raise** the ceiling when the required content genuinely needs the space, and state the reason in the same change. A too-low ceiling is a documentation defect.

## Bilingual pairs

Every human-facing document has an English original and a Chinese counterpart: `foo.md` beside `foo.zh.md`, so `AGENTS.md` pairs with `AGENTS.zh.md`. [PRD.md](../PRD.md) is the one pair whose canonical side is Chinese and whose English counterpart is `PRD.en.md`, because Chinese is the requirement source language. Both sides land in the same change. [README.md](../README.md) and [README.zh.md](../README.zh.md) are the reference pair.

A pair keeps the same heading sequence, list and table structure, code blocks, and link targets, and the same number of physical lines, so a reviewer can diff line n against line n. Identifier lines differ, since a relative link resolves against the file's own directory and a Chinese filename sits beside its English original. Count with:

```sh
wc -l AGENTS.md AGENTS.zh.md
```

Translation rules:

- Translate prose, headings, table text, and code comments. Never translate a code identifier, a command, a path, a wire byte sequence, a `TelnetError` case, or a link target.
- Keep one term per concept in Chinese and reuse it: 选项 (option)、协商 (negotiation)、子协商 (subnegotiation)、命令 (command)、事件 (event)、连接 (connection)、会话 (session)、调用方契约 (caller contract)、常驻规则 (standing orders).
- Prefer the shorter Chinese clause when both carry the same proposition. Do not pad a line to reach parity; rewrite the English line instead.
- Update both sides in one pass. A statement true on one side and stale on the other is a defect in the pair, not a translation backlog.
- Do not add a third locale file. A second language other than Chinese needs a decision recorded in this file first.

Without a translation tool configured, produce the counterpart by hand and leave a line-level surface check plus the line-count comparison as the evidence. Never merge a pair with a missing side.

## The slop checklist

Hunt these before reporting a document done:

- One rule in two tiers, or a contract restated beside the link that owns it.
- A designed behavior written in the present tense as if observed.
- A hand-restated catalog: an API, test, or requirement list copied instead of linked.
- Reasoning transcripts: derivation steps, branch proofs, test walkthroughs, rejected alternatives.
- A paragraph wall: several rules and asides in one paragraph.
- Emphasis inflation that leaves nothing standing out.
- Spec-speak after implementation: "should", "will need to", or an acceptance checklist in a reference that now describes shipped behavior.
- An unexplained magic number: a limit, timeout, or buffer size with no owner and no unit.

## Repository references

Use relative Markdown links for files in this repository. Every relative link must resolve: verify with the link check in [telnetkit-doc](../.agents/skills/telnetkit-doc/SKILL.md#validation). Reference an upstream file by URL and a historical state by commit or tag, never by branch name.
