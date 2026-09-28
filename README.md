# Token Operations System

**Assessment version:** 1.2.0

This take-home contains two small production-like components:

- a permissioned ERC-20 fund-share token; and
- a TypeScript listener that projects finalized `Transfer` logs into a holder
  register.

The inherited implementation builds and its smoke tests pass. Those smoke
tests are not a complete acceptance suite. Your task is described in
[`TASKS.md`](TASKS.md), and [`PRODUCT.md`](PRODUCT.md) is the source of truth for
every required behavior.

## Time box

Spend at most **3–4 hours**. Prioritize behavior that could authorize an
incorrect token movement, change supply incorrectly, or publish a wrong holder
balance. Record anything unfinished in [`SUBMISSION.md`](SUBMISSION.md).

## Prerequisites

- Foundry with Solidity `0.8.24` support
- Node.js 22 or later
- npm 10 or later

The Solidity test harness is self-contained; do not install `forge-std`.

## Run the project

### Solidity

```bash
cd contracts
forge build
forge test
```

### TypeScript

```bash
cd listener
npm ci
npm test
npm run typecheck
```

Run both suites before submitting. A passing starter suite does not mean the
product requirements are satisfied.

## Repository map

```text
contracts/
  src/SecurityToken.sol       permitted production change
  src/*.sol                   supplied, read-only dependencies
  test/*.t.sol                Solidity tests
listener/
  src/listener.ts             permitted production change
  src/money.ts                permitted production change
  src/fakeChain.ts            supplied, read-only chain model
  src/store.ts                supplied, read-only durable store model
  src/types.ts                supplied, read-only event contract
  test/*.test.ts              TypeScript tests
PRODUCT.md                    acceptance requirements
TEST_MAP.json                 requirement-to-test evidence
SUBMISSION.md                 concise engineering handoff
ai-prompt.log                 chronological AI prompt record
```

## Evaluation

Evaluation is behavior-first. Private checks exercise all `TOK-*` and `REG-*`
requirements, including route combinations, failure atomicity, finality,
restart, and large amounts. The evaluator also runs your tests against correct
and deliberately faulty implementations. Source-text assertions and tests that
depend on test-only production APIs do not count as behavioral evidence.

## AI Usage

Using AI tools (Copilot, ChatGPT, Claude, etc.) is **encouraged**. Use whatever
helps you work effectively.

Maintain `ai-prompt.log` — append a numbered entry for every AI interaction, in
the order they occurred.

The file must contain at least one entry, and every entry must contain a
complete, non-template prompt.

### `ai-prompt.log` format

Append entries in the order the prompts were sent. Entry number 1 is the first
block in the file, entry number 2 is the second, and so on; do not add a number
field. The evaluator refers to them as `P-001`, `P-002`, and so on. Every entry
contains exactly `timestamp`, `model`, and the complete prompt block:

```text
---
timestamp: 2026-04-27T10:30:00Z
model: GPT-5.3-Codex
prompt: |
  <full prompt text>
---
```

Repeat that block for each prompt, optionally separated by blank lines. Do
not add headings, bullets, comments, response summaries, decision fields, or
other metadata. Every non-empty prompt line must be indented by two spaces
beneath `prompt: |`; blank prompt lines may be empty.

The timestamp must be an ISO-8601 date-time with a timezone, and timestamps
must be nondecreasing in file order. `model` must be one non-empty line; use
`unknown` if the exact model is unavailable. The log must be UTF-8, use LF or
CRLF line endings, be no larger than 1 MiB, and contain between 1 and 100
complete entries. Replace the starter placeholder: placeholder prompts do not
count as disclosure.

See [`TASKS.md`](TASKS.md) for deliverables and
[`SUBMISSION.md`](SUBMISSION.md) for the handoff format.
