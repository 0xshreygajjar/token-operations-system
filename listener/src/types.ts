/** The zero address is ERC-20 issuance/redemption plumbing, never a holder. */
export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

/** A decoded ERC-20 Transfer log in canonical block order. */
export interface TransferLog {
  blockNumber: bigint;
  txHash: string;
  /** Distinguishes several Transfer logs emitted by the same transaction. */
  logIndex: number;
  from: string;
  to: string;
  value: bigint;
}
