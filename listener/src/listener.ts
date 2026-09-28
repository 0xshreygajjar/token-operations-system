import { FakeChain } from "./fakeChain.js";
import { HolderStore } from "./store.js";
import { ZERO_ADDRESS, type TransferLog } from "./types.js";

/** Durable per-log marker key: the full (blockNumber, txHash, logIndex) identity. */
function appliedKey(log: TransferLog): string {
  return `transfer:${JSON.stringify([log.blockNumber.toString(), log.txHash, log.logIndex])}`;
}

/**
 * Polls Transfer logs and projects holder balances into the supplied store.
 *
 * Only blocks with at least `confirmations` successors (`head - confirmations`) are published.
 * Each sync applies every eligible log after the durable cursor, records its marker and moves
 * the cursor inside one store transaction, so a failed tick publishes nothing.
 */
export class Listener {
  constructor(
    private readonly chain: FakeChain,
    private readonly store: HolderStore,
    private readonly confirmations: bigint = 2n,
  ) {
    if (typeof confirmations !== "bigint" || confirmations < 0n) {
      throw new RangeError("confirmations must be a non-negative bigint");
    }
  }

  async sync(): Promise<void> {
    const head = await this.chain.getHead();
    const finalized = head - this.confirmations;
    const cursor = await this.store.getCursor();
    if (finalized <= cursor) return;

    const logs = await this.chain.getLogs(cursor + 1n, finalized);

    await this.store.transaction(async () => {
      for (const log of logs) {
        if (log.blockNumber <= cursor || log.blockNumber > finalized) continue;
        const key = appliedKey(log);
        if (this.store.kv.has(key)) continue;

        if (log.from !== ZERO_ADDRESS) {
          const balance = await this.store.getBalance(log.from);
          await this.store.setBalance(log.from, balance - log.value);
        }
        if (log.to !== ZERO_ADDRESS) {
          const balance = await this.store.getBalance(log.to);
          await this.store.setBalance(log.to, balance + log.value);
        }

        this.store.kv.set(key, "1");
      }

      await this.store.setCursor(finalized);
    });
  }
}
