import { describe, expect, test } from "vitest";
import { formatTokenAmount } from "../src/money.js";

describe("REG-06 formatTokenAmount", () => {
  test("matches the specified examples", () => {
    expect(formatTokenAmount(0n, 18)).toBe("0");
    expect(formatTokenAmount(1n, 18)).toBe("0.000000000000000001");
    expect(formatTokenAmount(1_500_000n, 6)).toBe("1.5");
    expect(formatTokenAmount(5_000n * 10n ** 18n, 18)).toBe("5000");
  });

  test("is exact above Number.MAX_SAFE_INTEGER", () => {
    expect(formatTokenAmount(9_007_199_254_740_993n, 0)).toBe("9007199254740993");
    expect(formatTokenAmount(2n ** 64n + 1n, 18)).toBe("18.446744073709551617");
    expect(formatTokenAmount(10n ** 18n - 1n, 18)).toBe("0.999999999999999999");
    expect(formatTokenAmount(123_456_789_012_345_678_901_234_567_890n, 18)).toBe(
      "123456789012.34567890123456789",
    );
    expect(formatTokenAmount(2n ** 256n - 1n, 18)).toBe(
      "115792089237316195423570985008687907853269984665640564039457.584007913129639935",
    );
  });

  test("pads leading fractional zeroes and trims only trailing ones", () => {
    expect(formatTokenAmount(1_010n, 3)).toBe("1.01");
    expect(formatTokenAmount(100n, 3)).toBe("0.1");
    expect(formatTokenAmount(5n, 3)).toBe("0.005");
    expect(formatTokenAmount(1_000_500n, 6)).toBe("1.0005");
  });

  test("never emits an unnecessary decimal point", () => {
    expect(formatTokenAmount(1_000n, 3)).toBe("1");
    expect(formatTokenAmount(10_000n, 3)).toBe("10");
    expect(formatTokenAmount(123n, 0)).toBe("123");
    expect(formatTokenAmount(100n, 0)).toBe("100");
  });

  test("keeps one leading minus sign for negatives and renders zero unsigned", () => {
    expect(formatTokenAmount(-1_500_000n, 6)).toBe("-1.5");
    expect(formatTokenAmount(-1n, 18)).toBe("-0.000000000000000001");
    expect(formatTokenAmount(-(2n ** 64n + 1n), 18)).toBe("-18.446744073709551617");
    expect(formatTokenAmount(-7n, 0)).toBe("-7");
    expect(formatTokenAmount(-0n, 18)).toBe("0");
    expect(formatTokenAmount(0n, 0)).toBe("0");
  });

  test("honours decimals other than 18", () => {
    expect(formatTokenAmount(123_456n, 2)).toBe("1234.56");
    expect(formatTokenAmount(1n, 30)).toBe("0.000000000000000000000000000001");
  });

  test("rejects invalid decimals", () => {
    for (const decimals of [-1, 1.5, Number.NaN, Number.POSITIVE_INFINITY, 2 ** 53]) {
      expect(() => formatTokenAmount(1n, decimals)).toThrow();
    }
  });
});
