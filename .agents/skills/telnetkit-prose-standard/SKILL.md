---
name: telnetkit-prose-standard
description: Decide what a TelnetKit comment, doc comment, README, or document must say, and what to remove. Use when writing or reviewing public doc comments, internal comments, the README, architecture or API prose, or diagnostics, and when trimming reasoning transcripts, duplicated rules, or decoration without losing a contract.
---

# TelnetKit Prose Standard

## Summary

Write enough to preserve the contract, then remove reasoning transcripts, repetition, and decoration. A contract is an obligation, invariant, precondition, postcondition, or compatibility promise that a caller or callee relies on. This skill owns sentence-level judgment and required coverage; use [telnetkit-doc](../telnetkit-doc/SKILL.md) for placement, tiers, budgets, and validation.

## Table of Contents

- [Inputs and modes](#inputs-and-modes)
- [Preserve the complete proposition](#preserve-the-complete-proposition)
- [Required coverage by location](#required-coverage-by-location)
- [Terms to check before use](#terms-to-check-before-use)
- [Workflow](#workflow)
- [Dev Note](#dev-note)

## Inputs and modes

Require a scope: named files, a diff, or a named symbol. If the scope is missing, report it and stop.

Accept `mode: automatic | interactive`, defaulting to `automatic`. In automatic mode, apply clear edits and report genuine borderline cases without asking. In interactive mode, group analogous passages under one principle, present two or three viable versions, recommend one, and state the factual difference. Do not offer a weaker option as a distractor.

Mode controls questions, not write authority: a review reports findings without editing, and an explicit fix request applies clear changes.

Exclude `Sources/CLibTelnet/` from edits at every scope.

## Preserve the complete proposition

Before editing a passage, list its propositions. Preserve each relevant actor and action, condition and ordering, modality such as must or may, negative guarantee and exception, ownership, side effect, failure mode, and consequence.

Remove an adjective, repetition, or narration only when every factual clause survives and the result is clearer. A shorter passage is not automatically better.

Keep a complete local contract at the point of use: what happens, what fails, who owns the resource, and what the caller must do. Link to the owner for architecture, rationale, algorithms, history, and extended examples. One explanation has one home; an essential contract fact may repeat locally.

Keep non-obvious rationale when omitting it could cause misuse, such as why a buffer is copied rather than retained. Otherwise state the consequence and link the reason.

## Required coverage by location

This is not a shortening pass. Add a statement when the code and types do not carry the contract below, and stay silent when they already do.

- **Public doc comments.** State the outcome, the throw conditions by `TelnetError` case, the finish condition of the event stream, ownership, wire effects such as escaping and line-ending translation, ordering, and cancellation behavior. A reader who reads only the generated interface must know when to call the member and what a failure means.
- **Internal comments.** Orient structure that a reader cannot see locally: EventLoop ownership, the callback lifetime rule, the option ledger's relationship to observed events, and any invariant that a refactor could silently break. Delete control-flow narration and restatement of the next line.
- **Module-level comments.** State the file's role, its dependencies, and its non-obvious design choice, with a link to [architecture.md](../../../docs/architecture.md) for the reason.
- **Tests.** Explain only non-obvious test design: why a fixture, an indirect observation, or a platform accommodation is necessary. Delete walkthroughs and inventories of assertions.
- **README.** Cover what the library does, supported platforms, install, a runnable quick start, known limitations, and the security stance. Quote behavior that a caller depends on rather than paraphrasing the API reference.
- **Skills.** State the guardrail and the scope limit, keep the workflow short, and link the owning document instead of restating a rule.
- **Diagnostics and log messages.** Name the failing subject, the violated rule, and the correction when it is not obvious, and never include payload bytes or peer-supplied values.
- **Errors.** A `TelnetError` case's doc comment says what condition produces it and what the caller can do; it does not restate the C error code.

## Terms to check before use

Treat `contract`, `boundary`, `surface`, `seam`, `layer`, and `shape` as terms to verify, not banned words. Ask first whether a precise term names the subject better: write `the event callback`, `the TCP connection`, `the public API`, or `TelnetChannelHandler` instead of `the boundary` or `the layer`. Keep `contract` for a real obligation and `boundary` for a literal process, wire, or trust boundary.

Use the [glossary](../../../docs/public-api.md#glossary) terms exactly: `option`, `negotiation`, `subnegotiation`, `command`, `event`, `connection`, `session`, `NVT`. Do not introduce a second name for one of them, and do not call a connection a session.

Name the mechanism. "The parse layer strips it" is unusable; "`TelnetProtocolCore` removes the `IAC` sequence and emits only application bytes in `.data`" is the fact.

## Workflow

1. Confirm the scope, mode, and the documents that own the affected facts.
2. Read the owning code, test, or upstream header before judging a passage.
3. Classify each candidate as keep, add, trim, restore, or restructure. Judge semantically, not by length.
4. Apply clear changes only when the task authorizes edits, and update the owner before a derivative document.
5. Re-read one analogous passage after learning a rule, and apply the rule there too.
6. Run the checks in [telnetkit-doc](../telnetkit-doc/SKILL.md#validation), plus `swift test` when a visible string or a documented behavior changed.
7. Report the inspected scope, the clear changes, the deliberate keeps, and any deferred case with its reason.

## Dev Note

None.
