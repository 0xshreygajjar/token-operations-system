import type { TransferLog } from "./types.js";

/**
 * Deterministic stand-in for the chain RPC used by tests and the evaluator.
 * Production code may use only getHead/getLogs; mineBlock/reorg are test controls.
 */
export class FakeChain {
  private blocks: TransferLog[][] = [];

  async getHead(): Promise<bigint> {
    return BigInt(this.blocks.length - 1);
  }

  async getLogs(fromBlock: bigint, toBlock: bigint): Promise<TransferLog[]> {
    const out: TransferLog[] = [];
    const start = fromBlock < 0n ? 0n : fromBlock;
    for (let blockNumber = start; blockNumber <= toBlock; blockNumber += 1n) {
      const block = this.blocks[Number(blockNumber)];
      if (block) {
        for (const log of block) out.push({ ...log });
      }
    }
    return out;
  }

  mineBlock(
    transfers: Array<{
      from: string;
      to: string;
      value: bigint;
      txHash?: string;
    }>,
  ): bigint {
    const blockNumber = BigInt(this.blocks.length);
    this.blocks.push(
      transfers.map((transfer, logIndex) => ({
        blockNumber,
        logIndex,
        txHash: transfer.txHash ?? `0x${blockNumber.toString(16)}_${logIndex}`,
        from: transfer.from,
        to: transfer.to,
        value: transfer.value,
      })),
    );
    return blockNumber;
  }

  /** Replace an unfinalized suffix with a different branch. */
  reorg(
    fromBlock: number,
    replacement: Array<
      Array<{ from: string; to: string; value: bigint; txHash?: string }>
    >,
  ): void {
    this.blocks.length = fromBlock;
    for (const transfers of replacement) this.mineBlock(transfers);
  }
}
