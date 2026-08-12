import { zlib } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';

let gzipTempDir: string = '';
let tempCounter: number = 0;

export function initGzipTempDir(dir: string): void {
  gzipTempDir = dir;
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

function tempPath(ext: string): string {
  tempCounter++;
  return `${gzipTempDir}/decimen-gz-${Date.now()}-${tempCounter}.${ext}`;
}

export async function gzipBytes(bytes: Uint8Array): Promise<Uint8Array> {
  if (gzipTempDir === '') {
    throw new Error('gzip temp dir not initialized');
  }
  const outPath: string = tempPath('gz');
  const gz: zlib.GZip = zlib.createGZipSync();
  try {
    await gz.gzopen(outPath, 'wb');
    await gz.gzwrite(toArrayBuffer(bytes), bytes.length);
    await gz.gzflush(zlib.CompressFlushMode.FINISH);
    await gz.gzclose();
    const stat = fs.statSync(outPath);
    const outBuf: ArrayBuffer = new ArrayBuffer(stat.size);
    const file = fs.openSync(outPath, fs.OpenMode.READ_ONLY);
    fs.readSync(file.fd, outBuf);
    fs.closeSync(file);
    fs.unlinkSync(outPath);
    return new Uint8Array(outBuf);
  } catch (err) {
    if (fs.accessSync(outPath)) {
      fs.unlinkSync(outPath);
    }
    throw err as Error;
  }
}

export async function gunzipBytes(bytes: Uint8Array, maxBytes: number): Promise<Uint8Array> {
  if (gzipTempDir === '') {
    throw new Error('gzip temp dir not initialized');
  }
  const inPath: string = tempPath('gz');
  const file = fs.openSync(inPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  fs.writeSync(file.fd, toArrayBuffer(bytes));
  fs.closeSync(file);
  const gz: zlib.GZip = zlib.createGZipSync();
  try {
    await gz.gzopen(inPath, 'rb');
    const outBuf: ArrayBuffer = new ArrayBuffer(maxBytes);
    const read: number = await gz.gzfread(outBuf, 1, maxBytes);
    await gz.gzclose();
    fs.unlinkSync(inPath);
    if (read < 0) {
      throw new Error('The recovered gzip payload failed to decode.');
    }
    return new Uint8Array(outBuf, 0, read);
  } catch (err) {
    if (fs.accessSync(inPath)) {
      fs.unlinkSync(inPath);
    }
    throw err as Error;
  }
}
