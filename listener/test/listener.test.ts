import { describe, expect, test } from "vitest";
import { FakeChain } from "../src/fakeChain.js";
import { Listener } from "../src/listener.js";
import { HolderStore } from "../src/store.js";

const ZERO = "0x0000000000000000000000000000000000000000";
const alice = "0xA11ce0000000000000000000000000000000a11c";
const bob = "0xB0b0000000000000000000000000000000000b0b";

describe("holder register smoke coverage", () => {
  test("accounts for issuance and a holder transfer", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    const listener = new Listener(chain, store, 0n);
    chain.mineBlock([{ from: ZERO, to: alice, value: 100n }]);
    chain.mineBlock([{ from: alice, to: bob, value: 30n }]);

    await listener.sync();

    expect(await store.snapshot()).toEqual({ [alice]: "70", [bob]: "30" });
    expect(await store.getCursor()).toBe(1n);
  });

  test("continues from durable progress after restart", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    chain.mineBlock([{ from: ZERO, to: alice, value: 100n }]);
    await new Listener(chain, store, 0n).sync();
    chain.mineBlock([{ from: alice, to: bob, value: 25n }]);

    await new Listener(chain, store, 0n).sync();

    expect(await store.snapshot()).toEqual({ [alice]: "75", [bob]: "25" });
  });

  test("does not reapply one repeated log", async () => {
    const chain = new FakeChain();
    const store = new HolderStore();
    const listener = new Listener(chain, store, 0n);
    chain.mineBlock([{ from: ZERO, to: alice, value: 100n, txHash: "0xsame" }]);
    await listener.sync();
    await store.setCursor(-1n);

    await listener.sync();

    expect(await store.getBalance(alice)).toBe(100n);
  });
});
