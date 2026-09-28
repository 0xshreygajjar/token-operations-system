# Product specification: permissioned token and holder register

**Status:** approved for implementation
**Acceptance revision:** 1

This document is the candidate-visible source of truth. Requirement identifiers
are stable acceptance IDs. A different internal design is acceptable when it
produces the same observable behavior through the supplied public interfaces.

## Domain definitions

- A **real wallet** is any address other than the zero address.
- An **eligible wallet** is a real wallet currently accepted by `IAllowList`.
- A **held wallet** is a wallet for which `frozen(account)` is true.
- A **register halt** is the state in which `paused()` is true.
- A **recovery case** is a non-zero `bytes32` case identifier authorizing one
  successful recovery movement.
- A block is **eligible** for the holder register once it has at least the
  configured number of successor blocks. With a confirmation depth of zero,
  the current head is eligible immediately.
- The listener **cursor** is the greatest block whose eligible logs have all
  been published atomically.

## Permissioned token

The inherited ERC-20 interface and role API must remain compatible. The one
required new operation is:

```solidity
mapping(bytes32 => bool) public recoveryUsed;

event RecoveryExecuted(
    bytes32 indexed caseId,
    address indexed from,
    address indexed to,
    uint256 amount
);

function recover(
    bytes32 caseId,
    address from,
    address to,
    uint256 amount
) external;
```

Revert text and internal structure are not part of the contract. The observable
rules are:

### TOK-01 — current eligibility

- Every real wallet participating in an ordinary balance change must be
  currently eligible.
- Revocation takes effect immediately and prevents the wallet from sending or
  receiving through `transfer` and `transferFrom`.
- Issuance applies eligibility to its one real destination. Redemption applies
  eligibility to its one real source.
- The documented recovery exception in `TOK-04` may move a position out of an
  ineligible source; its destination still must be eligible.

### TOK-02 — operational holds

- A held wallet can neither send nor receive through ordinary transfer routes.
- Issuance to a held wallet and redemption from a held wallet are rejected.
- Hold and allowlist status are independent controls.
- The documented recovery exception in `TOK-04` may move a position out of a
  held source; its destination must not be held.

### TOK-03 — register halt

- While paused, `transfer`, `transferFrom`, and issuance are rejected.
- An authorized redemption remains available while paused.
- An authorized recovery remains available while paused.
- Unpausing restores only operations that satisfy every other requirement.

### TOK-04 — case-tracked recovery

- Only an account with `AGENT_ROLE` may call `recover`.
- `caseId` must be non-zero and unused, `amount` must be positive, and `from`
  and `to` must both be real, distinct wallets.
- The source may be held or currently ineligible. The destination must be
  currently eligible and not held.
- Recovery is allowed while paused and moves an existing position without
  changing total supply. Normal insufficient-balance behavior still applies.
- Before a successful call, `recoveryUsed(caseId)` is false. After success it is
  true, and every later call with that case ID is rejected.
- A failed call must not consume the case ID or partially change balances.
- A successful call emits the normal ERC-20 `Transfer(from, to, amount)` and
  exactly one `RecoveryExecuted(caseId, from, to, amount)` event.

### TOK-05 — supply and zero-address safety

- Every path that increases total supply is authorized issuance by a minter.
- Every path that decreases total supply is authorized redemption by an agent.
- A holder or approved spender cannot mint or destroy supply by sending through
  the zero address.
- Ordinary transfer and recovery endpoints reject zero-address participants.
- Successful recovery preserves total supply.

### TOK-06 — authority and registry administration

- Deployment grants `DEFAULT_ADMIN_ROLE` to the deployer and does **not** grant
  `MINTER_ROLE` or `AGENT_ROLE` automatically.
- Role grants and revocations remain admin-only.
- The initial allowlist and every replacement must be non-zero. Replacement is
  admin-only.
- Issuance is a minter power.
- Holds, halts, redemption, and recovery are agent powers.

### TOK-07 — route consistency and atomic failure

- The same eligibility, hold, pause, zero-address, and supply rules apply no
  matter whether an ordinary balance change begins through `transfer`,
  `transferFrom`, issuance, or redemption.
- Allowance does not bypass participant policy. A rejected `transferFrom` does
  not spend allowance.
- Any rejected operation leaves balances, supply, allowance, recovery-case
  state, and emitted-event history unchanged.

## Holder-register listener

The supplied interfaces are fixed:

```ts
new Listener(chain: FakeChain, store: HolderStore, confirmations?: bigint)
listener.sync(): Promise<void>

formatTokenAmount(raw: bigint, decimals: number): string
```

`FakeChain` and `HolderStore` model the permitted environment. Calls to
`sync()` are not concurrent. A reorganization will not replace a block after it
has reached the configured confirmation depth. The configured confirmation
depth must be non-negative; constructing a listener with a negative depth is
rejected.

### REG-01 — canonical finalized state

- Reported balances include logs only through
  `finalizedBlock = head - confirmations`.
- With depth zero, the current head is eligible immediately.
- If no new block is eligible, `sync()` is a no-op.
- A replaceable, unfinalized tip is never published, so replacing it before it
  becomes eligible cannot leave a stale balance.

### REG-02 — complete transfer accounting

- Every eligible `Transfer` log changes both non-zero sides of the movement.
- Mint credits only the non-zero recipient.
- Burn debits only the non-zero sender.
- A normal transfer debits the sender and credits the recipient by the exact
  same base-unit amount.
- The zero address is issuance/redemption plumbing and never appears as a
  holder.

### REG-03 — exactly-once log identity

- Repeated reads and overlapping ranges never apply a log twice.
- Distinct logs in the same transaction are all applied.
- Durable identity uses the complete `(blockNumber, txHash, logIndex)` tuple;
  transaction hash alone is not a log identifier.

### REG-04 — durable restart and catch-up

- A new `Listener` using the same `HolderStore` resumes from durable state.
- It fills every newly eligible block after the cursor without gaps.
- Restarting when there is no eligible gap is a no-op and does not corrupt
  balances, deduplication state, or the cursor.
- Listener instance fields are not durable storage. The supplied store is.

### REG-05 — atomic publication

- One `sync()` publishes its balance updates, deduplication markers, and final
  cursor in a single supplied store transaction.
- If any store operation fails, the tick publishes none of those changes.
- A later retry converges to the same balances and cursor as an uninterrupted
  run.

### REG-06 — exact amounts and formatting

- Amounts remain `bigint` base units throughout accounting. They are never
  converted to JavaScript `number` for arithmetic.
- `formatTokenAmount` performs decimal-string formatting without floating-point
  conversion, including for amounts above `Number.MAX_SAFE_INTEGER`.
- It pads leading fractional zeroes and trims only insignificant trailing
  fractional zeroes. It never emits an unnecessary decimal point.
- A negative input preserves one leading minus sign; zero is always rendered as
  `"0"`, never negative zero.
- Examples: `0n, 18 → "0"`; `1n, 18 → "0.000000000000000001"`;
  `1_500_000n, 6 → "1.5"`; `5_000n * 10n**18n, 18 → "5000"`.
- `decimals` must be a non-negative safe integer. Invalid values are rejected.

### REG-07 — cursor meaning

- The cursor is the greatest eligible block whose complete log range has been
  published successfully.
- It never denotes merely observed chain head or an unfinalized block.
- An eligible empty range still advances the cursor because that range has been
  completely processed.
- A failed tick cannot advance the cursor.

## Compatibility and non-requirements

- Token decimals remain 18. The standalone formatter must still honor its
  `decimals` argument.
- Authentication, RPC networking, database drivers, deployment scripts, and UI
  work are outside this exercise.
- Do not add testing-only methods to production code. Tests should observe the
  existing public contract and supplied store/chain interfaces.
