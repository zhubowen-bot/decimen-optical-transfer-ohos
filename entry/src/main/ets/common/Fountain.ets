import { splitmix32 } from './Protocol';

const LN2: number = 0.6931471805599453;

export function dlog(x: number): number {
  let e: number = 0;
  let m: number = x;
  while (m >= 1.5) {
    m /= 2;
    e++;
  }
  while (m < 0.75) {
    m *= 2;
    e--;
  }
  const z: number = (m - 1) / (m + 1);
  const z2: number = z * z;
  let term: number = z;
  let sum: number = 0;
  for (let n = 1; n <= 21; n += 2) {
    sum += term / n;
    term *= z2;
  }
  return e * LN2 + 2 * sum;
}

const SOLITON_C: number = 0.1;
const SOLITON_DELTA: number = 0.5;

export function solitonCdf(k: number): Float64Array {
  const cdf: Float64Array = new Float64Array(k);
  if (k === 1) {
    cdf[0] = 1;
    return cdf;
  }
  const R: number = Math.max(1, SOLITON_C * dlog(k / SOLITON_DELTA) * Math.sqrt(k));
  const spike: number = Math.min(k, Math.ceil(k / R));
  let total: number = 0;
  for (let d = 1; d <= k; d++) {
    const rho: number = d === 1 ? 1 / k : 1 / (d * (d - 1));
    let tau: number = 0;
    if (d < spike) {
      tau = R / (d * k);
    } else if (d === spike) {
      tau = (R * Math.max(0, dlog(R / SOLITON_DELTA))) / k;
    }
    total += rho + tau;
    cdf[d - 1] = total;
  }
  for (let i = 0; i < k; i++) {
    cdf[i] = cdf[i] / total;
  }
  cdf[k - 1] = 1;
  return cdf;
}

function frameSeed(sessionId: number, seq: number): number {
  let h: number = (Math.imul(sessionId + 1, 0x9e3779b1) ^ (seq + 0x85ebca6b)) | 0;
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
  return (h ^ (h >>> 16)) | 0;
}

export function frameIndices(
  k: number,
  cdf: Float64Array,
  sessionId: number,
  seq: number,
): number[] {
  const rnd: () => number = splitmix32(frameSeed(sessionId, seq));
  const u: number = rnd() * 2 ** -32;
  let lo: number = 0;
  let hi: number = k - 1;
  while (lo < hi) {
    const mid: number = (lo + hi) >> 1;
    if (cdf[mid] >= u) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  const d: number = Math.min(k, lo + 1);
  if (d > k >> 3) {
    const scratch: Uint32Array = new Uint32Array(k);
    for (let i = 0; i < k; i++) {
      scratch[i] = i;
    }
    const out: number[] = new Array<number>(d);
    for (let i = 0; i < d; i++) {
      const j: number = i + (rnd() % (k - i));
      const t: number = scratch[i];
      scratch[i] = scratch[j];
      scratch[j] = t;
      out[i] = scratch[i];
    }
    return out;
  }
  const set: Set<number> = new Set<number>();
  while (set.size < d) {
    set.add(rnd() % k);
  }
  return Array.from(set);
}

export function cycleLength(k: number): number {
  return 2 * k;
}

const REPAIR_DEGREE_MIN: number = 4;
const REPAIR_DEGREE_MAX: number = 24;

function repairIndices(k: number, sessionId: number, seq: number): number[] {
  const rnd: () => number = splitmix32(frameSeed(sessionId, seq));
  const d: number = Math.min(k,
    REPAIR_DEGREE_MIN + (rnd() % (REPAIR_DEGREE_MAX - REPAIR_DEGREE_MIN + 1)));
  const set: Set<number> = new Set<number>();
  while (set.size < d) {
    set.add(rnd() % k);
  }
  return Array.from(set);
}

export function frameComposition(k: number, sessionId: number, seq: number): number[] {
  const pos: number = seq % cycleLength(k);
  return pos < k ? [pos] : repairIndices(k, sessionId, seq);
}

function xorInto(dst: Uint32Array, src: Uint32Array): void {
  for (let i = 0; i < dst.length; i++) {
    dst[i] = (dst[i] ^ src[i]) >>> 0;
  }
}

export class LTEncoder {
  readonly k: number;
  readonly blockLen: number;
  readonly sessionId: number;
  private readonly words: number;
  private readonly blocks: Uint32Array;

  constructor(payload: Uint8Array, blockLen: number, sessionId: number) {
    this.blockLen = blockLen;
    this.sessionId = sessionId;
    this.k = Math.max(1, Math.ceil(payload.length / blockLen));
    this.words = Math.ceil(blockLen / 4);
    this.blocks = new Uint32Array(this.k * this.words);
    const bytes: Uint8Array = new Uint8Array(this.blocks.buffer);
    for (let b = 0; b < this.k; b++) {
      const start: number = b * blockLen;
      const end: number = Math.min((b + 1) * blockLen, payload.length);
      if (end > start) {
        bytes.set(payload.subarray(start, end), b * this.words * 4);
      }
    }
  }

  encode(seq: number): Uint8Array {
    const idx: number[] = frameComposition(this.k, this.sessionId, seq);
    const out: Uint32Array = new Uint32Array(this.words);
    for (const b of idx) {
      const off: number = b * this.words;
      for (let w = 0; w < this.words; w++) {
        out[w] = (out[w] ^ this.blocks[off + w]) >>> 0;
      }
    }
    return new Uint8Array(out.buffer, 0, this.blockLen);
  }
}

interface PendingFrame {
  idx: Set<number>;
  words: Uint32Array;
}

export class LTDecoder {
  readonly k: number;
  readonly blockLen: number;
  readonly sessionId: number;
  readonly totalLen: number;
  private readonly words: number;
  private readonly solved: Array<Uint32Array | undefined>;
  private readonly byBlock: Map<number, Set<PendingFrame>> = new Map<number, Set<PendingFrame>>();
  private readonly seen: Set<number> = new Set<number>();
  solvedCount: number = 0;
  framesNew: number = 0;
  framesDup: number = 0;
  framesRedundant: number = 0;

  constructor(k: number, blockLen: number, sessionId: number, totalLen: number) {
    this.k = k;
    this.blockLen = blockLen;
    this.sessionId = sessionId;
    this.totalLen = totalLen;
    this.words = Math.ceil(blockLen / 4);
    this.solved = new Array<Uint32Array | undefined>(k).fill(undefined);
  }

  get isComplete(): boolean {
    return this.solvedCount >= this.k;
  }

  addFrame(seq: number, block: Uint8Array): void {
    if (this.seen.has(seq)) {
      this.framesDup++;
      return;
    }
    this.seen.add(seq);
    this.framesNew++;
    if (this.isComplete) {
      return;
    }

    const idx: Set<number> = new Set<number>(frameComposition(this.k, this.sessionId, seq));
    const words: Uint32Array = new Uint32Array(this.words);
    new Uint8Array(words.buffer).set(block.subarray(0, this.blockLen));
    const blockList: number[] = Array.from(idx);
    for (const b of blockList) {
      const s: Uint32Array | undefined = this.solved[b];
      if (s !== undefined) {
        xorInto(words, s);
        idx.delete(b);
      }
    }
    if (idx.size === 0) {
      this.framesRedundant++;
      return;
    }
    if (idx.size === 1) {
      const single: number[] = Array.from(idx);
      const b0: number | undefined = single[0];
      if (b0 !== undefined) {
        this.resolve(b0, words);
      }
      return;
    }
    const pf: PendingFrame = { idx, words };
    const remaining: number[] = Array.from(idx);
    for (const b of remaining) {
      let set: Set<PendingFrame> | undefined = this.byBlock.get(b);
      if (set === undefined) {
        set = new Set<PendingFrame>();
        this.byBlock.set(b, set);
      }
      set.add(pf);
    }
  }

  private resolve(b0: number, w0: Uint32Array): void {
    const blockStack: number[] = [b0];
    const wordStack: Uint32Array[] = [w0];
    while (blockStack.length > 0) {
      const b: number = blockStack.pop() as number;
      const w: Uint32Array = wordStack.pop() as Uint32Array;
      if (this.solved[b] !== undefined) {
        continue;
      }
      this.solved[b] = w;
      this.solvedCount++;
      const waiting: Set<PendingFrame> | undefined = this.byBlock.get(b);
      if (waiting === undefined) {
        continue;
      }
      this.byBlock.delete(b);
      const pendingList: PendingFrame[] = Array.from(waiting);
      for (const pf of pendingList) {
        xorInto(pf.words, w);
        pf.idx.delete(b);
        if (pf.idx.size === 1) {
          const single: number[] = Array.from(pf.idx);
          const r: number | undefined = single[0];
          if (r !== undefined) {
            const set: Set<PendingFrame> | undefined = this.byBlock.get(r);
            if (set !== undefined) {
              set.delete(pf);
            }
            if (this.solved[r] === undefined) {
              blockStack.push(r);
              wordStack.push(pf.words);
            }
          }
        }
      }
    }
  }

  assemble(): Uint8Array | null {
    if (!this.isComplete) {
      return null;
    }
    const out: Uint8Array = new Uint8Array(this.totalLen);
    for (let b = 0; b < this.k; b++) {
      const start: number = b * this.blockLen;
      const len: number = Math.min(this.blockLen, this.totalLen - start);
      if (len > 0) {
        const block: Uint32Array | undefined = this.solved[b];
        if (block === undefined) {
          return null;
        }
        out.set(new Uint8Array(block.buffer, 0, len), start);
      }
    }
    return out;
  }
}
