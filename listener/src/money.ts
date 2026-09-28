/**
 * Render a base-unit amount as a decimal string using only bigint/string operations.
 * Leading fractional zeroes are kept, trailing ones trimmed, and a whole amount has no decimal point.
 */
export function formatTokenAmount(raw: bigint, decimals: number): string {
  if (typeof raw !== "bigint") {
    throw new TypeError("raw must be a bigint");
  }
  if (!Number.isSafeInteger(decimals) || decimals < 0) {
    throw new RangeError("decimals must be a non-negative safe integer");
  }
  if (raw === 0n) return "0";

  const negative = raw < 0n;
  const digits = (negative ? -raw : raw).toString();

  let whole = digits;
  let fraction = "";
  if (decimals > 0) {
    const padded = digits.padStart(decimals + 1, "0");
    whole = padded.slice(0, -decimals);
    fraction = padded.slice(-decimals).replace(/0+$/, "");
  }

  const body = fraction === "" ? whole : `${whole}.${fraction}`;
  return negative ? `-${body}` : body;
}
