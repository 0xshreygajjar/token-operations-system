/**
 * In-memory stand-in for the persistent holder-register database.
 * The same instance survives simulated process restarts. Everything inside
 * transaction(), including kv, is rolled back if the callback rejects.
 */
export class HolderStore {
  private balances = new Map<string, bigint>();
  private cursor = -1n;
  readonly kv = new Map<string, string>();

  async transaction<T>(work: () => Promise<T>): Promise<T> {
    const balancesBefore = new Map(this.balances);
    const cursorBefore = this.cursor;
    const kvBefore = new Map(this.kv);
    try {
      return await work();
    } catch (error) {
      this.balances = balancesBefore;
      this.cursor = cursorBefore;
      this.kv.clear();
      for (const [key, value] of kvBefore) this.kv.set(key, value);
      throw error;
    }
  }

  async getCursor(): Promise<bigint> {
    return this.cursor;
  }

  async setCursor(blockNumber: bigint): Promise<void> {
    this.cursor = blockNumber;
  }

  async getBalance(address: string): Promise<bigint> {
    return this.balances.get(address) ?? 0n;
  }

  async setBalance(address: string, value: bigint): Promise<void> {
    if (value === 0n) this.balances.delete(address);
    else this.balances.set(address, value);
  }

  async snapshot(): Promise<Record<string, string>> {
    const result: Record<string, string> = {};
    for (const [address, balance] of this.balances) {
      if (balance !== 0n) result[address] = balance.toString();
    }
    return result;
  }
}
