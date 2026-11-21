// The same private binary request is consumed by JNI and by the proof check.
export async function proofRequest(keys, runtime, preimage, location, binding) {
  const material = await keys.lookupKey(location);
  if (!material) throw Error('Circuit key unavailable');
  const { Zkir } = await runtime(material.ir);
  const circuit = Zkir.deserialize(material.ir);
  let k;
  try { k = circuit.getK(); } finally { circuit.free?.(); }
  const params = await keys.getParams(k);
  const bindingBytes = new Uint8Array(binding == null ? 0 : 32);
  if (binding != null) {
    if (binding < 0n || binding >= (1n << 256n)) throw Error('Invalid proof binding');
    for (let i = 0; i < 32; i++, binding >>= 8n) bindingBytes[i] = Number(binding & 255n);
  }
  const parts = [new TextEncoder().encode(location), preimage, bindingBytes,
    material.ir, material.proverKey, material.verifierKey, params];
  const size = parts.reduce((n, part) => n + 4 + part.length, 0);
  const bytes = new Uint8Array(size);
  const lengths = new DataView(bytes.buffer);
  let offset = 0;
  for (const part of parts) {
    lengths.setUint32(offset, part.length, true);
    bytes.set(part, offset + 4);
    offset += 4 + part.length;
  }
  return bytes;
}
