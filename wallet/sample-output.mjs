// Build a synthetic Zswap output for a local prover check. No wallet inputs.
export function sampleOutput(ledger) {
  const token = ledger.shieldedToken().raw;
  const coin = ledger.createShieldedCoinInfo(token, 1000n);
  const output = ledger.ZswapOutput.new(coin, 0, ledger.sampleCoinPublicKey(), ledger.sampleEncryptionPublicKey());
  return ledger.Transaction.fromParts('preview', ledger.ZswapOffer.fromOutput(output, token, 1000n));
}

export function verifyOutput(ledger, tx) {
  const strictness = new ledger.WellFormedStrictness();
  strictness.enforceBalancing = false; // This sample has no funding input.
  strictness.verifyNativeProofs = true;
  tx.wellFormed(ledger.LedgerState.blank('preview'), strictness, new Date());
}
