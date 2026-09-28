import { describe, expect, test } from "vitest";
import { formatTokenAmount } from "../src/money.js";

describe("amount formatting smoke coverage", () => {
  test("renders whole token amounts", () => {
    expect(formatTokenAmount(5_000n * 10n ** 18n, 18)).toBe("5000");
  });

  test("trims an exactly representable fractional suffix", () => {
    expect(formatTokenAmount(1_500_000n, 6)).toBe("1.5");
  });
});
