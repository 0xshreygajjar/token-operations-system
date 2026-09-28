# Submission note

## Highest-risk defect repaired

`transferFrom` never checked the source wallet. Trace: an agent freezes ALICE (100 FUND) and the
registrar revokes her; SPENDER, holding an earlier max approval, calls
`transferFrom(ALICE, BOB, 100)`. The inherited override checked only pause and the recipient, so
the call succeeded and the held, ineligible position left the register. Every ordinary route now
requires both participants to be non-zero, unheld and eligible
(`test_TOK02_heldOwnerCannotSendThroughTransferFrom`, `test_TOK01_revokedOwnerCannotSendThroughTransferFrom`).
Related repairs: `transfer` ignored sender eligibility; `mint` ignored pause and holds; `burn`
ignored holds and eligibility; deployment auto-granted minter/agent; zero allowlists were accepted;
zero-address participants were rejected only by allowlist membership.

## Recovery design

`recover` validates everything first: agent role, non-zero unused case, positive amount, non-zero
distinct endpoints, eligible and unheld destination. It then sets `recoveryUsed[caseId]` and moves
the position with `ERC20Base._update`, which skips only the ordinary policy on the source. Supply
is unchanged because neither endpoint is zero. Any revert, including insufficient balance inside
`_update`, rolls back the whole call, so a failed attempt never consumes the case. Success emits
one `Transfer` and one `RecoveryExecuted`. Pause is not checked.

## Listener design

`finalized = head - confirmations`; a negative depth is rejected. Logs in `(cursor, finalized]` are
fetched before any write. Balance updates, per-log markers and the new cursor are written in one
`store.transaction`, so a failed tick publishes nothing and a retry converges. Markers live in the
durable `kv`, keyed by the full `(blockNumber, txHash, logIndex)` tuple. Eligible empty ranges
still advance the cursor. `formatTokenAmount` uses only bigint and string operations.

## Residual risk / unfinished work

- Self-transfers and zero-amount ordinary transfers are allowed; the spec is silent.
- `freeze`, `unfreeze`, `pause` and `unpause` still emit no events.
- The listener relies on the stated bound that no reorg exceeds the confirmation depth; a deeper
  reorg would go undetected.
- Holder addresses are not case-normalised; mixed-case logs from a real RPC would split a holder.
- Tests were checked against 32 Solidity and 26 TypeScript hand-written faulty variants, not the
  grader's set.
- Vitest map entries use the `test()` title without the `describe` prefix.

## Verification

README commands.
