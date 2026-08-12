import { LTDecoder } from '../common/Fountain';
import { fnv1a, parseFrame, streamIdentity } from '../common/Protocol';
import { estimateTransferProgress, expectedFountainOverhead, formatDuration } from '../common/Progress';

export interface TransferUpdate {
  percent: number;
  label: string;
  etaLabel: string;
  framesNew: number;
  framesDup: number;
  solved: number;
  k: number;
  goodputKbs: number;
  elapsedSeconds: number;
}

export interface TransferResult {
  container: Uint8Array;
  hashOk: boolean;
  seconds: number;
}

export class ReceiveEngine {
  private decoder: LTDecoder | undefined = undefined;
  private streamKey: string = '';
  private startTs: number = 0;
  private done: boolean = false;
  private onUpdateCb: ((u: TransferUpdate) => void) | undefined = undefined;
  private onDoneCb: ((r: TransferResult) => void) | undefined = undefined;
  private onStreamCb: ((sessionId: number, k: number) => void) | undefined = undefined;

  constructor(
    onUpdate: (u: TransferUpdate) => void,
    onDone: (r: TransferResult) => void,
    onStream: (sessionId: number, k: number) => void,
  ) {
    this.onUpdateCb = onUpdate;
    this.onDoneCb = onDone;
    this.onStreamCb = onStream;
  }

  get isActive(): boolean {
    return this.decoder !== undefined;
  }

  reset(): void {
    this.decoder = undefined;
    this.streamKey = '';
    this.done = false;
  }

  markDone(): void {
    this.done = true;
  }

  onBytes(bytes: Uint8Array): void {
    if (this.done) {
      return;
    }
    const parsed = parseFrame(bytes);
    if (parsed === undefined) {
      return;
    }
    const header = parsed.header;
    const block = parsed.block;
    const identity: string = streamIdentity(header);
    if (this.decoder === undefined || this.streamKey !== identity) {
      this.decoder = new LTDecoder(header.k, header.blockLen, header.sessionId, header.totalLen);
      this.streamKey = identity;
      this.startTs = Date.now();
      const streamCb: ((sessionId: number, k: number) => void) | undefined = this.onStreamCb;
      if (streamCb !== undefined) {
        streamCb(header.sessionId, header.k);
      }
    }
    const decoder: LTDecoder = this.decoder;
    decoder.addFrame(header.seq, block);
    this.updateProgress();
    if (decoder.isComplete) {
      const payload: Uint8Array | null = decoder.assemble();
      const seconds: number = (Date.now() - this.startTs) / 1000;
      const ok: boolean = payload !== null && fnv1a(payload) === header.payloadFnv;
      this.done = true;
      const doneCb: ((r: TransferResult) => void) | undefined = this.onDoneCb;
      if (doneCb !== undefined && payload !== null) {
        doneCb({ container: payload, hashOk: ok, seconds });
      }
    }
  }

  private updateProgress(): void {
    const decoder: LTDecoder | undefined = this.decoder;
    const cb: ((u: TransferUpdate) => void) | undefined = this.onUpdateCb;
    if (decoder === undefined || cb === undefined) {
      return;
    }
    const elapsed: number = Math.max(0, (Date.now() - this.startTs) / 1000);
    const usefulFrames: number = decoder.framesNew - decoder.framesRedundant;
    const estimate = estimateTransferProgress(decoder.k, usefulFrames, elapsed, decoder.solvedCount);
    const percent: number = estimate.fraction * 100;
    const shownPercent: string = percent < 10 ? percent.toFixed(1) : percent.toFixed(0);
    let rate: string = '';
    if (decoder.framesNew >= 4) {
      rate = ` · ${this.goodputKbs(elapsed).toFixed(1)} KB/s`;
    }
    const etaLabel: string =
      (estimate.etaSeconds === undefined
        ? estimate.phase === 'decoding' ? `${decoder.framesNew} frames · decoding` : 'Estimating time…'
        : `About ${formatDuration(estimate.etaSeconds)} · ${decoder.framesNew} frames`) + rate;
    cb({
      percent,
      label: `${shownPercent}% · ${decoder.solvedCount}/${decoder.k} blocks`,
      etaLabel,
      framesNew: decoder.framesNew,
      framesDup: decoder.framesDup,
      solved: decoder.solvedCount,
      k: decoder.k,
      goodputKbs: this.goodputKbs(elapsed),
      elapsedSeconds: elapsed,
    });
  }

  private goodputKbs(elapsed: number): number {
    const decoder: LTDecoder | undefined = this.decoder;
    if (decoder === undefined) {
      return 0;
    }
    return (
      ((decoder.framesNew - decoder.framesRedundant) * decoder.blockLen) /
      expectedFountainOverhead(decoder.k) /
      1024 /
      Math.max(0.1, elapsed)
    );
  }
}
