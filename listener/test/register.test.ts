import { describe, expect, test } from "vitest";
import { FakeChain } from "../src/fakeChain.js";
import { Listener } from "../src/listener.js";
import { HolderStore } from "../src/store.js";

const ZERO = "0x0000000000000000000000000000000000000000";
const alice = "0xA11ce0000000000000000000000000000000a11c";
const bob = "0xB0b0000000000000000000000000000000000b0b";
const carol = "0xCa201000000000000000000000000000000ca201";

type Transfer = { from: string; to: string; value: bigint; txHash?: string };

/** Store whose next matching write can be made to fail, to exercise rollback. */
class FaultyStore extends HolderStore {
  failOnSetBalanceCall: number | null = null;
  failOnSetCursor = false;
  private setBalanceCalls = 0;

  override async setBalance(address: string, value: bigint): Promise<void> {
    this.setBalanceCalls += 1;
    if (this.failOnSetBalanceCall === this.setBalanceCalls) {
      this.failOnSetBalanceCall = null;
      throw new Error("injected setBalance failure");
    }
    return super.setBalance(address, value);
  }

  override async setCursor(blockNumber: bigint): Promise<void> {
    if (this.failOnSetCursor) {
      this.failOnSetCursor = false;
      throw new Error("injected setCursor failure");
    }
    return super.setCursor(blockNumber);
  }

  armSetBalanceFailure(callsFromNow: number): void {
    this.failOnSetBalanceCall = this.setBalanceCalls + callsFromNow;
  }
}

/** Chain whose next getLogs call can be made to fail. */
class FlakyChain extends FakeChain {
  failNextGetLogs = false;

  override async getLogs(fromBlock: bigint, toBlock: bigint) {
    if (this.failNextGetLogs) {
      this.failNextGetLogs = false;
      throw new Error("injected getLogs failure");
    }
    return super.getLogs(fromBlock, toBlock);
  }
}

function mineAll(chain: FakeChain, blocks: Transfer[][]): void {
  for (const block of blocks) chain.mineBlock(block);
}

/** Balances and cursor from an uninterrupted run over the same blocks. */
async function referenceRun(blocks: Transfer[][], confirmations: bigint) {
  const chain = new FakeChain();
  const store = new HolderStore();
  mineAll(chain, blocks);
  await new Listener(chain, store, confirmations).sync();
  return { snapshot: await store.snapshot(), cursor: await store.getCursor() };
}

describe("REG-01 canonical finalized state", () => {
  test("publishes logs only through head minus confirmations", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    for (let i = 0; i < 5; i += 1) chain.mineBlock([{ from: ZERO, to: alice, value: 1n }]);

    await new Listener(chain, store, 2n).sync();

    expect(await store.snapshot()).toEqual({ [alice]: "3" });
    expect(await store.getCursor()).toBe(2n);
  });

  test("depth zero publishes the current head immediately", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    chain.mineBlock([{ from: ZERO, to: alice, value: 9n }]);

    await new Listener(chain, store, 0n).sync();

    expect(await store.snapshot()).toEqual({ [alice]: "9" });
    expect(await store.getCursor()).toBe(0n);
  });

  test("is a no-op while no block has reached the confirmation depth", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    const listener = new Listener(chain, store, 3n);
    await listener.sync(); // empty chain
    mineAll(chain, [[{ from: ZERO, to: alice, value: 5n }], [], []]);

    await listener.sync();

    expect(await store.snapshot()).toEqual({});
    expect(await store.getCursor()).toBe(-1n);
  });

  test("a replaced unfinalized tip never leaves a stale balance", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    const listener = new Listener(chain, store, 1n);
    chain.mineBlock([{ from: ZERO, to: alice, value: 100n }]);
    chain.mineBlock([{ from: alice, to: bob, value: 10n }]); // tip, later orphaned
    await listener.sync();
    expect(await store.snapshot()).toEqual({ [alice]: "100" });

    chain.reorg(1, [[{ from: alice, to: carol, value: 30n }], []]);
    await listener.sync();

    expect(await store.snapshot()).toEqual({ [alice]: "70", [carol]: "30" });
    expect(await store.getCursor()).toBe(1n);
  });

  test("rejects a negative confirmation depth", () => {
    expect(() => new Listener(new FakeChain(), new HolderStore(), -1n)).toThrow();
  });
});

describe("REG-02 complete transfer accounting", () => {
  test("mint credits, burn debits and transfers move the exact amount", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    mineAll(chain, [
      [{ from: ZERO, to: alice, value: 1_000n }],
      [{ from: alice, to: bob, value: 250n }],
      [{ from: bob, to: ZERO, value: 50n }],
      [{ from: alice, to: alice, value: 10n }],
    ]);

    await new Listener(chain, store, 0n).sync();

    expect(await store.snapshot()).toEqual({ [alice]: "750", [bob]: "200" });
    expect(await store.getBalance(ZERO)).toBe(0n);
  });

  test("a fully redeemed holder disappears and the zero address never appears", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    mineAll(chain, [
      [{ from: ZERO, to: alice, value: 40n }, { from: ZERO, to: bob, value: 5n }],
      [{ from: alice, to: ZERO, value: 40n }],
    ]);

    await new Listener(chain, store, 0n).sync();

    const snapshot = await store.snapshot();
    expect(snapshot).toEqual({ [bob]: "5" });
    expect(Object.keys(snapshot)).not.toContain(ZERO);
  });
});

describe("REG-03 exactly-once log identity", () => {
  test("applies every distinct log emitted by one transaction", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    chain.mineBlock([
      { from: ZERO, to: alice, value: 100n, txHash: "0xbatch" },
      { from: alice, to: bob, value: 30n, txHash: "0xbatch" },
      { from: alice, to: carol, value: 20n, txHash: "0xbatch" },
    ]);

    await new Listener(chain, store, 0n).sync();

    expect(await store.snapshot()).toEqual({ [alice]: "50", [bob]: "30", [carol]: "20" });
  });

  test("the same txHash and logIndex in different blocks are different logs", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    chain.mineBlock([{ from: ZERO, to: alice, value: 7n, txHash: "0xdup" }]);
    chain.mineBlock([{ from: ZERO, to: alice, value: 7n, txHash: "0xdup" }]);

    await new Listener(chain, store, 0n).sync();

    expect(await store.snapshot()).toEqual({ [alice]: "14" });
  });

  test("an overlapping re-read by a new instance never applies a log twice", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    mineAll(chain, [
      [{ from: ZERO, to: alice, value: 100n, txHash: "0xa" }, { from: alice, to: bob, value: 1n, txHash: "0xa" }],
      [{ from: alice, to: bob, value: 9n }],
    ]);
    await new Listener(chain, store, 0n).sync();
    await store.setCursor(-1n); // force the next range to overlap everything already applied

    await new Listener(chain, store, 0n).sync();

    expect(await store.snapshot()).toEqual({ [alice]: "90", [bob]: "10" });
    expect(await store.getCursor()).toBe(1n);
  });
});

describe("REG-04 durable restart and catch-up", () => {
  test("a new instance fills every newly eligible block after the cursor", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    mineAll(chain, [[{ from: ZERO, to: alice, value: 100n }], []]);
    await new Listener(chain, store, 1n).sync();
    expect(await store.getCursor()).toBe(0n);

    mineAll(chain, [
      [{ from: alice, to: bob, value: 10n }],
      [{ from: alice, to: carol, value: 20n }],
      [{ from: bob, to: carol, value: 5n }],
      [{ from: ZERO, to: bob, value: 1n }], // tip, not yet eligible
    ]);
    await new Listener(chain, store, 1n).sync();

    expect(await store.snapshot()).toEqual({ [alice]: "70", [bob]: "5", [carol]: "25" });
    expect(await store.getCursor()).toBe(4n);
  });

  test("restarting with no eligible gap changes nothing and later blocks apply once", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    chain.mineBlock([{ from: ZERO, to: alice, value: 100n }]);
    await new Listener(chain, store, 0n).sync();

    await new Listener(chain, store, 0n).sync();
    expect(await store.snapshot()).toEqual({ [alice]: "100" });
    expect(await store.getCursor()).toBe(0n);

    chain.mineBlock([{ from: alice, to: bob, value: 40n }]);
    await new Listener(chain, store, 0n).sync();
    expect(await store.snapshot()).toEqual({ [alice]: "60", [bob]: "40" });
    expect(await store.getCursor()).toBe(1n);
  });
});

describe("REG-05 atomic publication", () => {
  const blocks: Transfer[][] = [
    [{ from: ZERO, to: alice, value: 100n }],
    [{ from: alice, to: bob, value: 30n }, { from: bob, to: carol, value: 10n }],
    [{ from: alice, to: ZERO, value: 5n }],
  ];

  test("a store failure mid-tick publishes nothing and a retry converges", async () => {
    const chain = new FakeChain();
    const store = new FaultyStore();
    mineAll(chain, blocks);
    const listener = new Listener(chain, store, 0n);
    store.armSetBalanceFailure(3); // after the mint and the first debit have been written

    await expect(listener.sync()).rejects.toThrow("injected");
    expect(await store.snapshot()).toEqual({});
    expect(await store.getCursor()).toBe(-1n);

    await listener.sync();
    expect({ snapshot: await store.snapshot(), cursor: await store.getCursor() }).toEqual(
      await referenceRun(blocks, 0n),
    );
  });

  test("a failure writing the cursor rolls back balances and dedup markers", async () => {
    const chain = new FakeChain();
    const store = new FaultyStore();
    chain.mineBlock(blocks[0]!);
    const listener = new Listener(chain, store, 0n);
    await listener.sync();
    chain.mineBlock(blocks[1]!);
    chain.mineBlock(blocks[2]!);
    store.failOnSetCursor = true;

    await expect(listener.sync()).rejects.toThrow("injected");
    expect(await store.snapshot()).toEqual({ [alice]: "100" });
    expect(await store.getCursor()).toBe(0n);

    await new Listener(chain, store, 0n).sync();
    expect({ snapshot: await store.snapshot(), cursor: await store.getCursor() }).toEqual(
      await referenceRun(blocks, 0n),
    );
  });

  test("a chain read failure leaves the register untouched", async () => {
    const chain = new FlakyChain();
    const store = new HolderStore();
    mineAll(chain, blocks);
    const listener = new Listener(chain, store, 0n);
    chain.failNextGetLogs = true;

    await expect(listener.sync()).rejects.toThrow("injected");
    expect(await store.snapshot()).toEqual({});
    expect(await store.getCursor()).toBe(-1n);

    await listener.sync();
    expect(await store.snapshot()).toEqual((await referenceRun(blocks, 0n)).snapshot);
  });
});

describe("REG-06 exact bigint amounts", () => {
  test("balances above Number.MAX_SAFE_INTEGER stay exact", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    const big = 2n ** 200n + 7n;
    const moved = 2n ** 64n + 1n;
    mineAll(chain, [
      [{ from: ZERO, to: alice, value: big }],
      [{ from: alice, to: bob, value: moved }],
      [{ from: alice, to: carol, value: 1n }],
    ]);

    await new Listener(chain, store, 0n).sync();

    expect(await store.getBalance(alice)).toBe(big - moved - 1n);
    expect(await store.getBalance(bob)).toBe(moved);
    expect(await store.getBalance(carol)).toBe(1n);
    expect(await store.snapshot()).toEqual({
      [alice]: (big - moved - 1n).toString(),
      [bob]: "18446744073709551617",
      [carol]: "1",
    });
  });
});

describe("REG-07 cursor meaning", () => {
  test("an eligible empty range still advances the cursor", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    mineAll(chain, [[], [], [], []]);

    await new Listener(chain, store, 1n).sync();

    expect(await store.getCursor()).toBe(2n);
    expect(await store.snapshot()).toEqual({});
  });

  test("the cursor tracks the finalized block, never the observed head", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    const listener = new Listener(chain, store, 2n);
    mineAll(chain, [[{ from: ZERO, to: alice, value: 1n }], [], [], []]);

    await listener.sync();
    expect(await store.getCursor()).toBe(1n);

    chain.mineBlock([{ from: ZERO, to: bob, value: 2n }]);
    await listener.sync();
    expect(await store.getCursor()).toBe(2n);
    expect(await store.snapshot()).toEqual({ [alice]: "1" });

    mineAll(chain, [[], []]);
    await listener.sync();
    expect(await store.getCursor()).toBe(4n);
    expect(await store.snapshot()).toEqual({ [alice]: "1", [bob]: "2" });
  });

  test("a failed tick cannot advance the cursor", async () => {
    const chain = new FakeChain();
    const store = new FaultyStore();
    mineAll(chain, [[{ from: ZERO, to: alice, value: 1n }], [], []]);
    store.armSetBalanceFailure(1);

    await expect(new Listener(chain, store, 0n).sync()).rejects.toThrow("injected");

    expect(await store.getCursor()).toBe(-1n);
  });
});
