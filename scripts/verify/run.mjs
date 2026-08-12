// Wire-format verification harness: compiles the ArkTS common/ ports (pure
// logic only) into Node, shadows the system kits, and runs the repository's
// golden vectors against them. Run from the repo root:
//
//   node --import tsx ohos/scripts/verify/run.mjs
//
// Any failure here means the ArkTS port has drifted from the web wire format.

import * as fs from 'node:fs';
import * as path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '../../..');
const srcDir = path.join(repoRoot, 'ohos/entry/src/main/ets/common');
const tmp = fs.mkdtempSync(path.join(process.env.TEMP || '/tmp', 'decimen-verify-'));

const SHIMS = {
  'shims/arkts.ts': `export const util = {
  TextEncoder: globalThis.TextEncoder,
  TextDecoder: class extends TextDecoder {
    decodeToString(input, options) { return this.decode(input); }
  },
};
`,
  'shims/performance.ts': `export const hilog = {
  info() {}, warn() {}, error() {}, debug() {},
};
`,
  'shims/corefile.ts': `import * as nodeFs from 'node:fs';
export const fileIo = {
  OpenMode: { READ_ONLY: 0, READ_WRITE: 2, CREATE: 256, TRUNC: 512 },
  openSync(path, mode) { const fd = nodeFs.openSync(path, mode === undefined ? 0 : mode); return { fd }; },
  statSync(file) { return typeof file === 'number' ? nodeFs.fstatSync(file) : nodeFs.statSync(file); },
  readSync(fd, buffer) {
    if (buffer instanceof ArrayBuffer) {
      const view = new Uint8Array(buffer);
      return nodeFs.readSync(fd, view);
    }
    return nodeFs.readSync(fd, buffer);
  },
  writeSync(fd, buffer) {
    if (buffer instanceof ArrayBuffer) {
      return nodeFs.writeSync(fd, new Uint8Array(buffer));
    }
    return nodeFs.writeSync(fd, buffer);
  },
  closeSync(file) { nodeFs.closeSync(file.fd !== undefined ? file.fd : file); },
  unlinkSync(path) { nodeFs.unlinkSync(path); },
  accessSync(path) { return nodeFs.existsSync(path); },
};
`,
  'shims/basic.ts': `import * as nodeZlib from 'node:zlib';
import * as nodeFs from 'node:fs';
export const zlib = {
  CompressLevel: { COMPRESS_LEVEL_DEFAULT_COMPRESSION: -1 },
  CompressMethod: { DEFLATED: 8 },
  MemLevel: { MEM_LEVEL_DEFAULT: 8 },
  CompressStrategy: { COMPRESS_STRATEGY_DEFAULT_STRATEGY: 0 },
  CompressFlushMode: { FINISH: 4 },
  ReturnStatus: { OK: 0, STREAM_END: 1, BUF_ERROR: -5, DATA_ERROR: -3 },
  createZipSync() {
    return {
      async compressBound(len) { return len + 1024; },
      async getZStream() {
        return { nextIn: undefined, availableIn: undefined, nextOut: undefined, availableOut: undefined, totalOut: undefined };
      },
      async deflateInit2() { return 0; },
      async deflate(strm) {
        const input = new Uint8Array(strm.nextIn, 0, strm.availableIn);
        const out = nodeZlib.gzipSync(input);
        new Uint8Array(strm.nextOut).set(out);
        strm.totalOut = out.length;
        strm.availableOut = strm.nextOut.byteLength - out.length;
        return 1;
      },
      async deflateEnd() { return 0; },
      async inflateInit2() { return 0; },
      async inflate(strm) {
        const input = new Uint8Array(strm.nextIn, 0, strm.availableIn);
        try {
          const out = nodeZlib.gunzipSync(input);
          if (out.length > strm.availableOut) return -5;
          new Uint8Array(strm.nextOut).set(out);
          strm.totalOut = out.length;
          strm.availableOut = strm.nextOut.byteLength - out.length;
          return 1;
        } catch (e) {
          return -3;
        }
      },
      async inflateEnd() { return 0; },
    };
  },
  createGZipSync() {
    return {
      async gzopen(path, mode) { this.path = path; this.mode = mode; this.writeBuf = undefined; return undefined; },
      async gzwrite(buf, len) { this.writeBuf = new Uint8Array(buf, 0, len); return len; },
      async gzflush() { return 0; },
      async gzclose() {
        if (this.mode === 'wb' && this.writeBuf) {
          nodeFs.writeFileSync(this.path, nodeZlib.gzipSync(this.writeBuf));
        }
        return 0;
      },
      async gzfread(buf, size, nitems) {
        const gz = nodeFs.readFileSync(this.path);
        const out = nodeZlib.gunzipSync(gz);
        const max = size * nitems;
        const n = Math.min(out.length, max);
        new Uint8Array(buf).set(out.subarray(0, n));
        return n;
      },
    };
  },
};
`,
  'shims/crypto.ts': `import * as nodeCrypto from 'node:crypto';
export const cryptoFramework = {
  createMd(alg) {
    return {
      async update(input) { this.hash = nodeCrypto.createHash(alg.toLowerCase()); this.hash.update(input.data); },
      async digest() { return { data: new Uint8Array(this.hash.digest()) }; },
    };
  },
};
`,
};

const REWRITES = [
  [/\bfrom '\.\/Protocol'/g, `from './Protocol.ts'`],
  [/\bfrom '\.\/CryptoWrap'/g, `from './CryptoWrap.ts'`],
  [/\bfrom '\.\/GzipWrap'/g, `from './GzipWrap.ts'`],
  [/from '@kit\.ArkTS'/g, `from './shims/arkts.ts'`],
  [/from '@kit\.BasicServicesKit'/g, `from './shims/basic.ts'`],
  [/from '@kit\.CryptoArchitectureKit'/g, `from './shims/crypto.ts'`],
  [/from '@kit\.PerformanceAnalysisKit'/g, `from './shims/performance.ts'`],
  [/from '@kit\.CoreFileKit'/g, `from './shims/corefile.ts'`],
];

// Copy every common/*.ets -> *.ts with kit imports shadowed.
for (const entry of fs.readdirSync(srcDir)) {
  if (!entry.endsWith('.ets')) continue;
  const raw = fs.readFileSync(path.join(srcDir, entry), 'utf8');
  let out = raw;
  for (const [re, to] of REWRITES) out = out.replace(re, to);
  fs.writeFileSync(path.join(tmp, entry.replace(/\.ets$/, '.ts')), out);
}

// QrEncoder is self-contained; copy it verbatim for QR golden checks.
const qrSrc = path.join(repoRoot, 'ohos/entry/src/main/ets/qr/QrEncoder.ets');
fs.writeFileSync(path.join(tmp, 'QrEncoder.ts'), fs.readFileSync(qrSrc, 'utf8'));

// QrDecoder is copied with kit imports shadowed (it now logs via hilog).
const qrDecSrc = path.join(repoRoot, 'ohos/entry/src/main/ets/qr/QrDecoder.ets');
let qrDecOut = fs.readFileSync(qrDecSrc, 'utf8');
for (const [re, to] of REWRITES) qrDecOut = qrDecOut.replace(re, to);
fs.writeFileSync(path.join(tmp, 'QrDecoder.ts'), qrDecOut);
for (const [rel, content] of Object.entries(SHIMS)) {
  const p = path.join(tmp, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content);
}

const goldens = `import assert from 'node:assert/strict';
import { dlog, solitonCdf, frameIndices, cycleLength, frameComposition, LTEncoder, LTDecoder } from './Fountain.ts';
import { packFrame, parseFrame, streamIdentity, fnv1a, splitmix32, packFile, unpackFile, verifyFile, isPrecompressedType, HEADER_LEN } from './Protocol.ts';
import { gridDims, rasterizeQr, rasterizeQrGrid } from './QrRaster.ts';
import { packSnippet, snippetText, isSnippet, MAX_SNIPPET_BYTES, MAX_SNIPPET_LABEL } from './Snippet.ts';
import { initGzipTempDir } from './GzipWrap.ts';

initGzipTempDir(process.cwd());

const WHITE = 0xffffffff;
const BLACK = 0xff000000;

function testPayload(byteLength) {
  const payload = new Uint8Array(byteLength);
  for (let i = 0; i < byteLength; i++) payload[i] = (i * 37 + (i >> 8) * 11) & 0xff;
  return payload;
}

function roundTrip(byteLength, blockLen, sessionId, dropRate = 0) {
  const payload = testPayload(byteLength);
  const encoder = new LTEncoder(payload, blockLen, sessionId);
  const decoder = new LTDecoder(encoder.k, blockLen, sessionId, byteLength);
  const rnd = splitmix32(sessionId);
  let seq = 0;
  const ceiling = encoder.k * 80 + 5000;
  while (!decoder.isComplete && seq < ceiling) {
    if (rnd() * 2 ** -32 >= dropRate) decoder.addFrame(seq, encoder.encode(seq));
    seq++;
  }
  return { frames: decoder.framesNew, overhead: decoder.framesNew / encoder.k, wallClock: seq / encoder.k, recovered: decoder.assemble() };
}

const results = [];
function check(name, fn) {
  try { fn(); results.push(['ok', name]); }
  catch (e) { results.push(['FAIL', name]); console.error('FAIL ' + name + '\\n' + e); }
}
function hex8(n) { return '0x' + (n >>> 0).toString(16).padStart(8, '0'); }
function bytesHex(u8) { return [...u8].map((b) => b.toString(16).padStart(2, '0')).join(' '); }

// ---- dlog goldens
check('dlog bit-exact values', () => {
  const golden = [[1, 0], [1.5, 0.4054651081081644], [2, 0.6931471805599453], [2.718281828459045, 1], [10, 2.3025850929940455], [20, 2.995732273553991], [200, 5.298317366548036], [2000, 7.600902459542082], [2986, 8.001689978099137], [44000, 10.691944912900398], [131070, 11.78348681061359]];
  for (const [x, expected] of golden) assert.equal(dlog(x), expected, 'dlog(' + x + ') drifted');
});

check('dlog exhaustive FNV digest', () => {
  const values = new Float64Array(65535 + 64 * 4096);
  let n = 0;
  for (let k = 1; k <= 65535; k++) values[n++] = dlog(2 * k);
  for (let i = 64; i < 64 * 4096; i++) values[n++] = dlog(i / 64);
  const digest = fnv1a(new Uint8Array(values.buffer, 0, n * 8));
  assert.equal(hex8(digest), '0x27b0f3cc', 'dlog changed');
});

// ---- soliton CDF fingerprints
check('soliton CDF fingerprints', () => {
  const golden = [[1, '0x8c6a9878'], [2, '0x2417b297'], [17, '0x2ba41e3c'], [179, '0xe8b6340a'], [716, '0x28d31438'], [5000, '0x357a4c9a'], [22000, '0xfc512a92']];
  for (const [k, expected] of golden) {
    const cdf = solitonCdf(k);
    const digest = fnv1a(new Uint8Array(cdf.buffer, cdf.byteOffset, cdf.byteLength));
    assert.equal(hex8(digest), expected, 'k=' + k + ' distribution changed');
  }
});

// ---- frameIndices goldens
check('frameIndices recorded subsets', () => {
  const golden = {
    1: [[0], [0], [0], [0], [0]],
    2: [[1], [1], [1], [0], [1]],
    17: [[3, 14], [12, 0], [6, 8], [15, 16, 13], [11, 2, 16]],
    179: [[27, 39], [30, 55], [155, 125], [28, 132, 88], [39, 75, 24]],
    716: [[27, 397], [567, 592], [155, 304], [386, 311, 625], [39, 433, 382]],
  };
  const seqs = [0, 1, 2, 41, 1000];
  for (const rawK of Object.keys(golden)) {
    const k = Number(rawK);
    const cdf = solitonCdf(k);
    seqs.forEach((seq, i) => {
      assert.deepEqual(frameIndices(k, cdf, 4242, seq), golden[rawK][i], 'k=' + k + ' seq=' + seq);
    });
  }
});

// ---- encoder stream fingerprints
check('encoded stream byte-identical fingerprints', () => {
  const golden = [[1, 64, 1, 'k=1 fnv=0xf6a115c5'], [23, 64, 7, 'k=23 fnv=0x4a5d3eaa'], [179, 2933, 4242, 'k=179 fnv=0x54f78d05'], [716, 1445, 65535, 'k=716 fnv=0x75b73b85']];
  for (const [k, blockLen, sessionId, expected] of golden) {
    const encoder = new LTEncoder(testPayload(k * blockLen - 7), blockLen, sessionId);
    const stream = new Uint8Array(64 * blockLen);
    for (let seq = 0; seq < 64; seq++) stream.set(encoder.encode(seq), seq * blockLen);
    const actual = 'k=' + encoder.k + ' fnv=' + hex8(fnv1a(stream));
    assert.equal(actual, expected, 'stream for k=' + k + '/' + blockLen + '/' + sessionId + ' changed');
  }
});

// ---- frame composition
check('carousel composition systematic then mid-degree', () => {
  for (const k of [1, 17, 179, 4096]) {
    assert.equal(cycleLength(k), 2 * k);
    for (const pos of new Set([0, k >> 1, k - 1])) {
      assert.deepEqual(frameComposition(k, 9, pos), [pos]);
      assert.deepEqual(frameComposition(k, 9, pos + 6 * cycleLength(k)), [pos]);
    }
    for (const seq of [k, k + 1, 2 * k - 1]) {
      const idx = frameComposition(k, 9, seq);
      assert.ok(idx.length >= Math.min(k, 4) && idx.length <= Math.min(k, 24));
      assert.equal(new Set(idx).size, idx.length);
      for (const b of idx) assert.ok(Number.isInteger(b) && b >= 0 && b < k);
    }
  }
});

// ---- LT round trips
check('payload survives the fountain exactly', () => {
  for (const [byteLength, blockLen] of [[7, 2933], [2933, 2933], [50000, 1445], [512 * 1024, 2933], [2 * 1024 * 1024, 2933]]) {
    const { recovered } = roundTrip(byteLength, blockLen, 11);
    assert.ok(recovered, byteLength + 'B did not complete');
    assert.deepEqual(recovered, testPayload(byteLength));
  }
});

check('dropping 30% costs time never correctness', () => {
  const { recovered, overhead, wallClock } = roundTrip(512 * 1024, 2933, 23, 0.3);
  assert.ok(recovered);
  assert.deepEqual(recovered, testPayload(512 * 1024));
  assert.ok(wallClock < 2.8, 'wall clock ' + wallClock.toFixed(2));
  assert.ok(overhead < 1.8, 'overhead ' + overhead.toFixed(2));
});

check('clean sweep pays zero overhead', () => {
  const byteLength = 200000;
  const blockLen = 1445;
  const payload = testPayload(byteLength);
  const encoder = new LTEncoder(payload, blockLen, 55);
  const decoder = new LTDecoder(encoder.k, blockLen, 55, byteLength);
  for (let seq = 0; seq < encoder.k; seq++) decoder.addFrame(seq, encoder.encode(seq));
  assert.ok(decoder.isComplete);
  assert.equal(decoder.framesNew, encoder.k);
  assert.deepEqual(decoder.assemble(), payload);
});

check('redundant re-swept blocks counted not as progress', () => {
  const blockLen = 64;
  const payload = testPayload(23 * blockLen - 7);
  const encoder = new LTEncoder(payload, blockLen, 77);
  const decoder = new LTDecoder(encoder.k, blockLen, 77, payload.length);
  decoder.addFrame(0, encoder.encode(0));
  assert.equal(decoder.solvedCount, 1);
  assert.equal(decoder.framesRedundant, 0);
  const nextCycle = cycleLength(encoder.k);
  decoder.addFrame(nextCycle, encoder.encode(nextCycle));
  assert.equal(decoder.framesNew, 2);
  assert.equal(decoder.framesDup, 0);
  assert.equal(decoder.framesRedundant, 1);
  assert.equal(decoder.solvedCount, 1);
  decoder.addFrame(1, encoder.encode(1));
  assert.equal(decoder.framesRedundant, 1);
  assert.equal(decoder.solvedCount, 2);
});

check('frames decode in any order', () => {
  const byteLength = 200000;
  const blockLen = 1445;
  const payload = testPayload(byteLength);
  const encoder = new LTEncoder(payload, blockLen, 77);
  const captured = [];
  for (let seq = 0; seq < Math.ceil(encoder.k * 2.5); seq++) captured.push([seq, encoder.encode(seq)]);
  const shuffled = captured.slice();
  const rnd = splitmix32(5);
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = rnd() % (i + 1);
    const t = shuffled[i]; shuffled[i] = shuffled[j]; shuffled[j] = t;
  }
  const decoder = new LTDecoder(encoder.k, blockLen, 77, byteLength);
  for (const [seq, block] of shuffled) {
    decoder.addFrame(seq, block);
    if (decoder.isComplete) break;
  }
  assert.ok(decoder.isComplete);
  assert.deepEqual(decoder.assemble(), payload);
});

check('duplicate frames never corrupt the decode', () => {
  const byteLength = 60000;
  const blockLen = 1445;
  const payload = testPayload(byteLength);
  const encoder = new LTEncoder(payload, blockLen, 31);
  const decoder = new LTDecoder(encoder.k, blockLen, 31, byteLength);
  let seq = 0;
  while (!decoder.isComplete) {
    const block = encoder.encode(seq);
    decoder.addFrame(seq, block);
    decoder.addFrame(seq, block);
    seq++;
  }
  assert.ok(decoder.framesDup >= decoder.framesNew - 1);
  assert.deepEqual(decoder.assemble(), payload);
});

check('single-block payload completes on first frame', () => {
  const payload = testPayload(900);
  const encoder = new LTEncoder(payload, 2933, 5);
  assert.equal(encoder.k, 1);
  const decoder = new LTDecoder(1, 2933, 5, 900);
  decoder.addFrame(0, encoder.encode(0));
  assert.ok(decoder.isComplete);
  assert.deepEqual(decoder.assemble(), payload);
});

check('incomplete decoder assembles nothing', () => {
  const encoder = new LTEncoder(testPayload(50000), 1445, 13);
  const decoder = new LTDecoder(encoder.k, 1445, 13, 50000);
  decoder.addFrame(0, encoder.encode(0));
  assert.equal(decoder.isComplete, false);
  assert.equal(decoder.assemble(), null);
});

// ---- protocol frame header byte-exact
check('frame header is byte-for-byte what the wire expects', () => {
  const frame = packFrame({ sessionId: 0xbeef, seq: 0x01020304, k: 0x0111, blockLen: 6, totalLen: 0x00fedcba, payloadFnv: 0x89abcdef }, new Uint8Array([1, 2, 3, 4, 5, 6]));
  assert.equal(bytesHex(frame), 'd1 0d ef be 04 03 02 01 11 01 06 00 ba dc fe 00 ef cd ab 89 01 02 03 04 05 06');
  assert.equal(frame.length, HEADER_LEN + 6);
  const parsed = parseFrame(frame);
  assert.ok(parsed);
  assert.deepEqual(parsed.header, { sessionId: 0xbeef, seq: 0x01020304, k: 0x0111, blockLen: 6, totalLen: 0x00fedcba, payloadFnv: 0x89abcdef });
  assert.deepEqual(parsed.block, new Uint8Array([1, 2, 3, 4, 5, 6]));
});

check('bad frames are rejected', () => {
  const good = packFrame({ sessionId: 1, seq: 2, k: 3, blockLen: 4, totalLen: 10, payloadFnv: 0 }, new Uint8Array([9, 9, 9, 9]));
  assert.ok(parseFrame(good));
  const wrongMagic = good.slice(); wrongMagic[0] = 0xd2;
  assert.equal(parseFrame(wrongMagic), undefined);
  assert.equal(parseFrame(good.subarray(0, HEADER_LEN)), undefined);
  assert.equal(parseFrame(good.subarray(0, good.length - 1)), undefined);
  const zeroK = good.slice();
  new DataView(zeroK.buffer).setUint16(8, 0, true);
  assert.equal(parseFrame(zeroK), undefined);
});

// ---- isPrecompressedType
check('isPrecompressedType skips gzip for compressed formats', () => {
  for (const type of ['image/jpeg', 'image/png', 'image/webp', 'image/avif', 'image/heic', 'video/mp4', 'video/quicktime', 'audio/mpeg', 'audio/mp4', 'audio/flac', 'application/zip', 'application/gzip', 'application/x-7z-compressed', 'application/vnd.rar', 'application/epub+zip', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.oasis.opendocument.spreadsheet', 'IMAGE/JPEG', 'image/jpeg; charset=binary']) {
    assert.equal(isPrecompressedType(type), true, type + ' should skip gzip');
  }
});
check('isPrecompressedType still tries compressible types', () => {
  for (const type of ['text/plain', 'text/csv', 'application/json', 'application/pdf', 'application/wasm', 'application/octet-stream', 'application/vnd.decimen.snippet', 'image/svg+xml', 'image/bmp', 'image/tiff', 'image/x-icon', 'audio/wav', 'audio/x-aiff', '']) {
    assert.equal(isPrecompressedType(type), false, type + ' should still try gzip');
  }
});

// ---- packFile / unpackFile / verifyFile
check('arbitrary bytes survive the container (gzip and none)', async () => {
  const source = new Uint8Array([0, 1, 2, 127, 128, 254, 255]);
  const packed = await packFile('résumé.bin', 'application/octet-stream', source);
  const recovered = await unpackFile(packed.container);
  assert.equal(packed.compression, 'none');
  assert.equal(recovered.name, 'résumé.bin');
  assert.equal(recovered.type, 'application/octet-stream');
  assert.deepEqual(recovered.bytes, source);
  assert.equal(await verifyFile(recovered), true);

  const compressible = new TextEncoder().encode('decimen optical transfer\\n'.repeat(4000));
  const p2 = await packFile('notes.txt', 'text/plain', compressible);
  assert.equal(p2.compression, 'gzip');
  assert.ok(p2.transmittedSize < compressible.length / 10);
  const r2 = await unpackFile(p2.container);
  assert.deepEqual(r2.bytes, compressible);
  assert.equal(await verifyFile(r2), true);
});

check('SHA-256 verification rejects changed bytes', async () => {
  const packed = await packFile('message.txt', 'text/plain', new TextEncoder().encode('hello'));
  const recovered = await unpackFile(packed.container);
  recovered.bytes[0] ^= 0xff;
  assert.equal(await verifyFile(recovered), false);
});

check('filename sanitisation on unpack', async () => {
  for (const [sent, expected] of [['../../etc/passwd', 'passwd'], ['C:\\\\Windows\\\\System32\\\\drivers\\\\etc\\\\hosts', 'hosts'], ['évidence.pdf', 'évidence.pdf'], ['report v2 (final).tar.gz', 'report v2 (final).tar.gz']]) {
    const packed = await packFile(sent, 'application/octet-stream', new Uint8Array([1, 2, 3]));
    assert.equal((await unpackFile(packed.container)).name, expected, 'for ' + JSON.stringify(sent));
  }
  for (const sent of ['..', '.', '/', '   ', '\\u0000\\u0007']) {
    const packed = await packFile(sent, 'application/octet-stream', new Uint8Array([1]));
    assert.equal((await unpackFile(packed.container)).name, 'transfer.bin');
  }
});

check('malformed containers rejected', async () => {
  const source = new TextEncoder().encode('bounded output\\n'.repeat(1000));
  const packed = await packFile('bounded.txt', 'text/plain', source);
  const malformed = packed.container.slice();
  new DataView(malformed.buffer).setUint32(9, source.length + 1, true);
  let rejected = false;
  try { await unpackFile(malformed); } catch (e) { rejected = true; }
  assert.ok(rejected, 'gzip length mismatch must reject');
  let rejected2 = false;
  try { await unpackFile(new Uint8Array(49)); } catch (e) { rejected2 = true; }
  assert.ok(rejected2, 'invalid header must reject');
});

check('precompressed file transmitted verbatim and round-trips', async () => {
  const source = new Uint8Array(4096);
  for (let i = 0; i < source.length; i++) source[i] = (i * 2654435761) >>> 24;
  const packed = await packFile('photo.jpg', 'image/jpeg', source);
  assert.equal(packed.compression, 'none');
  assert.equal(packed.transmittedSize, source.length);
  const recovered = await unpackFile(packed.container);
  assert.deepEqual(recovered.bytes, source);
  assert.equal(await verifyFile(recovered), true);
});

check('streamIdentity covers every constant field', () => {
  const base = { sessionId: 7, seq: 0, k: 100, blockLen: 2933, totalLen: 293300, payloadFnv: 0xdeadbeef };
  const identity = streamIdentity(base);
  assert.equal(streamIdentity({ ...base, seq: 9999 }), identity);
  for (const field of ['sessionId', 'k', 'blockLen', 'totalLen', 'payloadFnv']) {
    assert.notEqual(streamIdentity({ ...base, [field]: base[field] + 1 }), identity, field + ' must force new decoder');
  }
  const a = { sessionId: 1, seq: 0, k: 1, blockLen: 23, totalLen: 4, payloadFnv: 5 };
  const b = { sessionId: 1, seq: 0, k: 12, blockLen: 3, totalLen: 4, payloadFnv: 5 };
  assert.notEqual(streamIdentity(a), streamIdentity(b));
});

// ---- snippet
check('snippet survives the container', async () => {
  const text = 'ssh-ed25519 AAAAC3Nz… evan@laptop\\nand a second line.';
  const packed = await packSnippet(text);
  const file = await unpackFile(packed.container);
  assert.ok(await verifyFile(file));
  assert.ok(isSnippet(file));
  assert.equal(snippetText(file), text);
});

check('empty snippets rejected', async () => {
  let rejected = false;
  try { await packSnippet('  \\n\\t '); } catch (e) { rejected = true; }
  assert.ok(rejected);
});

check('snippets capped in UTF-8 bytes', async () => {
  let rejected = false;
  try { await packSnippet('x'.repeat(MAX_SNIPPET_BYTES + 1)); } catch (e) { rejected = true; }
  assert.ok(rejected);
  let rejected2 = false;
  try { await packSnippet('あ'.repeat(Math.ceil(MAX_SNIPPET_BYTES / 3) + 1)); } catch (e) { rejected2 = true; }
  assert.ok(rejected2);
});

check('long snippets compress', async () => {
  const packed = await packSnippet('the same sentence over and over. '.repeat(2000));
  assert.equal(packed.compression, 'gzip');
  assert.ok(packed.transmittedSize < packed.originalSize);
});

// ---- qr raster
check('qr raster goldens', () => {
  assert.deepEqual([...rasterizeQr(1, [1], 0).pixels], [BLACK]);
  const { size, pixels } = rasterizeQr(1, [1], 2);
  assert.equal(size, 5);
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const expected = x === 2 && y === 2 ? BLACK : WHITE;
    assert.equal(pixels[y * size + x], expected, 'pixel (' + x + ',' + y + ')');
  }
  assert.deepEqual([...rasterizeQr(2, [1, 0, 0, 1], 0).pixels], [BLACK, WHITE, WHITE, BLACK]);
  assert.ok([...rasterizeQr(3, new Uint8Array(9), 1).pixels].every((p) => p === WHITE));

  assert.deepEqual(gridDims(1), { cols: 1, rows: 1 });
  assert.deepEqual(gridDims(2), { cols: 1, rows: 2 });
  assert.deepEqual(gridDims(4), { cols: 2, rows: 2 });
  assert.deepEqual(gridDims(6), { cols: 2, rows: 3 });
  assert.deepEqual(gridDims(9), { cols: 3, rows: 3 });

  const g = rasterizeQrGrid(1, [[1], [0], [0], [1]], 1);
  assert.equal(g.width, 6); assert.equal(g.height, 6);
  for (let y = 0; y < g.height; y++) for (let x = 0; x < g.width; x++) {
    const dark = (x === 1 && y === 1) || (x === 4 && y === 4);
    assert.equal(g.pixels[y * g.width + x], dark ? BLACK : WHITE, 'pixel (' + x + ',' + y + ')');
  }

  const col = rasterizeQrGrid(1, [[1], [1]], 1);
  assert.equal(col.width, 3); assert.equal(col.height, 6);
  for (let y = 0; y < col.height; y++) for (let x = 0; x < col.width; x++) {
    const dark = x === 1 && (y === 1 || y === 4);
    assert.equal(col.pixels[y * col.width + x], dark ? BLACK : WHITE, 'pixel (' + x + ',' + y + ')');
  }

  const six = rasterizeQrGrid(1, [[1], [0], [1], [0], [1], [0]], 0);
  assert.deepEqual([...six.pixels], [BLACK, WHITE, BLACK, WHITE, BLACK, WHITE]);

  const one = rasterizeQrGrid(2, [[1, 0, 0, 1]], 2);
  const plain = rasterizeQr(2, [1, 0, 0, 1], 2);
  assert.deepEqual([...one.pixels], [...plain.pixels]);

  let threw = false;
  try { rasterizeQrGrid(1, [[1], [1], [1], [1], [1]], 1); } catch (e) { threw = true; }
  assert.ok(threw);

  const bytes = new Uint8Array(rasterizeQr(1, [1], 1).pixels.buffer);
  const center = 4 * (1 * 3 + 1);
  assert.deepEqual([...bytes.slice(center, center + 4)], [0, 0, 0, 255]);
  assert.deepEqual([...bytes.slice(0, 4)], [255, 255, 255, 255]);
});

setTimeout(() => {
  const failed = results.filter((r) => r[0] === 'FAIL').length;
  console.log('\\n' + (results.length - failed) + '/' + results.length + ' golden checks passed');
  if (failed > 0) { console.error(failed + ' checks FAILED'); process.exit(1); }
}, 0);
`;

// QR encoder golden checks against the original qrcode library core.
const qrSection = `
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const qrCore = require(process.env.QRCODE_CORE);
const Version = require(process.env.QRCODE_VERSION);
const ECLevel = require(process.env.QRCODE_ECLEVEL);
const Mode = require(process.env.QRCODE_MODE);
const { createQrSymbol, ECC_L, ECC_M, ECC_Q, ECC_H } = await import('./QrEncoder.ts');

function randBytes(n) {
  const a = new Uint8Array(n);
  for (let i = 0; i < n; i++) a[i] = (i * 37 + (i >> 8) * 11) & 0xff;
  return a;
}

check('QR symbols match the qrcode library bit-for-bit across versions 1-40 and all ECC', () => {
  const eccPairs = [['L', ECC_L], ['M', ECC_M], ['Q', ECC_Q], ['H', ECC_H]];
  let compared = 0;
  for (const [name, myEcc] of eccPairs) {
    const origEcc = ECLevel[name];
    for (let v = 1; v <= 40; v++) {
      const cap = Version.getCapacity(v, origEcc, Mode.BYTE);
      const payload = randBytes(cap);
      const orig = qrCore.create([{ data: payload, mode: 'byte' }], { errorCorrectionLevel: name, maskPattern: 4 });
      const mine = createQrSymbol(payload, myEcc, undefined, 4);
      assert.equal(mine.version, orig.version, 'version mismatch ' + name + ' v' + v + ' cap=' + cap);
      assert.equal(mine.modules.size, orig.modules.size, 'size mismatch ' + name + ' v' + v);
      assert.deepEqual([...mine.modules.data], [...orig.modules.data], 'modules mismatch ' + name + ' v' + v + ' cap=' + cap);
      compared++;
    }
    const fixedPayload = randBytes(100);
    const origFixed = qrCore.create([{ data: fixedPayload, mode: 'byte' }], { errorCorrectionLevel: name, version: 10, maskPattern: 4 });
    const mineFixed = createQrSymbol(fixedPayload, myEcc, 10, 4);
    assert.deepEqual([...mineFixed.modules.data], [...origFixed.modules.data], 'fixed v10 ' + name);
    compared++;
  }
  assert.ok(compared >= 160, 'expected >=160 QR comparisons, got ' + compared);
});

check('QR symbols at real sender payload sizes match the library', () => {
  for (const bytesLen of [2933, 1445, 1110, 480, 100, 17]) {
    const payload = randBytes(bytesLen);
    for (const name of ['L', 'M', 'Q', 'H']) {
      let orig;
      try {
        orig = qrCore.create([{ data: payload, mode: 'byte' }], { errorCorrectionLevel: name, maskPattern: 4 });
      } catch (e) { continue; }
      const myEcc = name === 'L' ? ECC_L : name === 'M' ? ECC_M : name === 'Q' ? ECC_Q : ECC_H;
      const mine = createQrSymbol(payload, myEcc, undefined, 4);
      assert.deepEqual([...mine.modules.data], [...orig.modules.data], 'len=' + bytesLen + ' ' + name);
    }
  }
});
`;

// QR decode golden checks: generate rasters with the original qrcode library,
// run the ArkTS QrDecoder port over their RGBA bytes, and require byte-exact
// recovery — plus a real packFrame/parseFrame round trip through the optical.
const decodeSection = `
const { decodeQr } = await import('./QrDecoder.ts');

function rasterizeRgba(modules, size, margin) {
  const dim = size + 2 * margin;
  const rgba = new Uint8ClampedArray(dim * dim * 4).fill(255);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      if (modules[y * size + x]) {
        const o = ((y + margin) * dim + (x + margin)) * 4;
        rgba[o] = 0; rgba[o + 1] = 0; rgba[o + 2] = 0; rgba[o + 3] = 255;
      }
    }
  }
  return { rgba, dim };
}

function scale4(rgba, dim) {
  const out = new Uint8ClampedArray(dim * 4 * dim * 4 * 4);
  for (let y = 0; y < dim; y++) {
    for (let x = 0; x < dim; x++) {
      const src = (y * dim + x) * 4;
      const r = rgba[src]; const g = rgba[src + 1]; const b = rgba[src + 2]; const a = rgba[src + 3];
      for (let sy = 0; sy < 4; sy++) {
        for (let sx = 0; sx < 4; sx++) {
          const o = (((y * 4 + sy) * dim * 4) + (x * 4 + sx)) * 4;
          out[o] = r; out[o + 1] = g; out[o + 2] = b; out[o + 3] = a;
        }
      }
    }
  }
  return out;
}

check('decodeQr recovers bytes from generated rasters', () => {
  // Version 1 codes (<=17 bytes) cannot be read by jsQR at 1 px/module —
  // the original library fails them identically. Decimen frames are always
  // far larger (>=480 bytes), so we only test real sender payload sizes.
  for (const len of [100, 480, 1110, 1445, 2331, 2933]) {
    const payload = randBytes(len);
    const qr = qrCore.create([{ data: payload, mode: 'byte' }], { errorCorrectionLevel: 'L', maskPattern: 4 });
    const { rgba, dim } = rasterizeRgba(qr.modules.data, qr.modules.size, 4);
    const decoded = decodeQr(rgba, dim, dim);
    assert.ok(decoded, 'len ' + len + ' failed to decode');
    assert.deepEqual([...decoded.bytes], [...payload], 'len ' + len + ' bytes mismatch');
  }
});

check('decodeQr recovers from 4x nearest-neighbour upscaled rasters', () => {
  for (const len of [17, 480, 1445]) {
    const payload = randBytes(len);
    const qr = qrCore.create([{ data: payload, mode: 'byte' }], { errorCorrectionLevel: 'M', maskPattern: 4 });
    const { rgba, dim } = rasterizeRgba(qr.modules.data, qr.modules.size, 4);
    const big = scale4(rgba, dim);
    const decoded = decodeQr(big, dim * 4, dim * 4);
    assert.ok(decoded, '4x len ' + len + ' failed to decode');
    assert.deepEqual([...decoded.bytes], [...payload], '4x len ' + len + ' bytes mismatch');
  }
});

check('decodeQr + parseFrame round trip on real optical frames', () => {
  const frame = packFrame(
    { sessionId: 0xbeef, seq: 123, k: 179, blockLen: 1445, totalLen: 100000, payloadFnv: 0x12345678 },
    new Uint8Array(1445).map((_, i) => i & 0xff),
  );
  const qr = qrCore.create([{ data: frame, mode: 'byte' }], { errorCorrectionLevel: 'L', maskPattern: 4 });
  const { rgba, dim } = rasterizeRgba(qr.modules.data, qr.modules.size, 4);
  const decoded = decodeQr(rgba, dim, dim);
  assert.ok(decoded, 'real frame failed to decode');
  const parsed = parseFrame(new Uint8Array(decoded.bytes));
  assert.ok(parsed, 'real frame failed parseFrame');
  assert.equal(parsed.header.seq, 123);
  assert.equal(parsed.header.sessionId, 0xbeef);
  assert.equal(parsed.block.length, 1445);
});
`;

fs.writeFileSync(path.join(tmp, 'goldens.mts'), goldens + qrSection + decodeSection);

console.log('verifying against ' + tmp);
try {
  execFileSync(process.execPath, ['--experimental-transform-types', 'goldens.mts'], {
    cwd: tmp,
    stdio: 'inherit',
    env: {
      ...process.env,
      QRCODE_CORE: path.join(repoRoot, 'node_modules/qrcode/lib/core/qrcode.js'),
      QRCODE_VERSION: path.join(repoRoot, 'node_modules/qrcode/lib/core/version.js'),
      QRCODE_ECLEVEL: path.join(repoRoot, 'node_modules/qrcode/lib/core/error-correction-level.js'),
      QRCODE_MODE: path.join(repoRoot, 'node_modules/qrcode/lib/core/mode.js'),
    },
  });
} catch (e) {
  process.exit(1);
}
