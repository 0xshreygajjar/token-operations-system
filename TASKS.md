# Take-home task

## Scenario

You are taking ownership of a small permissioned token and its holder-register
listener. Both came from an internal spike. The inherited code builds and its
smoke tests pass, but the product behavior has now been approved and a
case-tracked recovery workflow must be added.

[`PRODUCT.md`](PRODUCT.md) is the complete source of truth. Do not infer policy
from the starter implementation.

## Your work

1. Add the exact case-tracked Solidity recovery API described by `TOK-04`:
   `recover(caseId, from, to, amount)`, `recoveryUsed`, and
   `RecoveryExecuted`.
2. Audit and repair the inherited `SecurityToken` so all `TOK-01` through
   `TOK-07` behavior holds across every public balance route.
3. Audit and repair the TypeScript holder listener and amount formatter so all
   `REG-01` through `REG-07` behavior holds.
4. Add focused behavioral tests for the defects and boundary cases you repair.
5. Complete `TEST_MAP.json`, `ai-prompt.log`, and `SUBMISSION.md`.

The work is intentionally one combined task. Correct contract events are the
inputs to the TypeScript projection, and both sides require exact token-unit
reasoning.

## Evidence requirements

- Add at least one useful test reference for every `TOK-*` and `REG-*`
  requirement in `TEST_MAP.json`.
- A map entry uses `relative/path::exact test name`.
- Tests must assert observable behavior. Do not inspect production source text,
  search for keywords, or add implementation-only test hooks.
- Keep tests deterministic and independent of external RPCs, clocks, or
  networks.
- Your tests must pass a correct implementation and should fail for the
  specific faulty behavior they protect against.
- Keep `SUBMISSION.md` at or below 400 words.
- Complete `ai-prompt.log` in the exact block format described in `README.md`.
  Append every candidate-authored AI prompt in chronological order with its
  timestamp and model. Do not include AI responses, private chain-of-thought,
  vendor system prompts, or assistant-internal tool calls.

Private evaluation runs additional behavior/property tests and substitutes
known-faulty implementations behind the same public interfaces. Test names,
revert strings, formatting style, and a particular internal design are not
graded.

## Change boundary

You may change only:

- `contracts/src/SecurityToken.sol`
- `contracts/test/**`
- `listener/src/listener.ts`
- `listener/src/money.ts`
- `listener/test/**`
- `TEST_MAP.json`
- `SUBMISSION.md`
- `ai-prompt.log`

All other files are supplied dependencies or assessment inputs. Changing,
deleting, renaming, or replacing them fails the scope gate. Do not commit build
outputs, dependency directories, symlinks, or generated grader artifacts.

## Time and tools

Time box: **3–4 hours maximum**. Prefer critical behavior and tests over broad
refactoring or visual polish.

You may use documentation and development tools.

## AI Usage

Using AI tools (Copilot, ChatGPT, Claude, etc.) is **encouraged**. Use whatever
helps you work effectively.

Maintain `ai-prompt.log` — append a numbered entry for every AI interaction, in
the order they occurred.

The file must contain at least one entry, and every entry must contain a
complete, non-template prompt.

## Deliverables

- Working Solidity and TypeScript implementations within the allowed boundary
- Passing local commands from `README.md`
- Behavioral contract and listener tests
- Completed `TEST_MAP.json`
- Completed `ai-prompt.log`
- Completed `SUBMISSION.md`
