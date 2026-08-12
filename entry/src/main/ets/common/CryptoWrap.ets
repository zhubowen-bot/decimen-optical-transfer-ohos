import { cryptoFramework } from '@kit.CryptoArchitectureKit';

export async function sha256Digest(bytes: Uint8Array): Promise<Uint8Array> {
  const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
  const input: cryptoFramework.DataBlob = { data: bytes };
  await md.update(input);
  const result: cryptoFramework.DataBlob = await md.digest();
  return result.data;
}
