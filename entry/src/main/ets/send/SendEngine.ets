import { taskpool } from '@kit.ArkTS';
import { LTEncoder } from '../common/Fountain';
import { FrameHeader, fnv1a, packFrame } from '../common/Protocol';
import { GridDims, gridDims } from '../common/QrRaster';
import { generateFrameRaster, FrameCellResult } from './SendTask';

export const QR_MARGIN: number = 4;

const LOOKAHEAD: number = 2;

export interface StreamLockSpec {
  fps: number;
  frameBytes: number;
  eccName: string;
  gridCodes: number;
  gridCols: number;
  gridRows: number;
  version: number;
  modules: number;
  cellSize: number;
  k: number;
  blockLen: number;
  sessionId: number;
  payloadName: string;
  payloadSize: number;
  compression: string;
  transmittedSize: number;
}

export interface CellRaster {
  cellIndex: number;
  cellSize: number;
  raster: Uint32Array;
}

export class SendStream {
  private readonly fps: number;
  private readonly frameBytes: number;
  private readonly eccName: string;
  private readonly gridCodes: number;
  private readonly grid: GridDims;
  private payloadName: string = '';
  private payloadSize: number = 0;
  private compression: string = '';
  private transmittedSize: number = 0;
  private encoder: LTEncoder | undefined;
  private header: FrameHeader | undefined;
  private nextSeq: number = 0;
  private ready: FrameCellResult[] = [];
  private generating: boolean = false;
  private locked: boolean = false;
  private timerId: number = -1;
  private running: boolean = false;
  private generation: number = 0;
  private displayInterval: number = 16;
  private nextDisplayAt: number = 0;
  private onFrameCb: ((cell: CellRaster) => void) | undefined;
  private onLockedCb: ((spec: StreamLockSpec) => void) | undefined;
  private onErrorCb: ((message: string) => void) | undefined;

  constructor(fps: number, frameBytes: number, eccName: string, gridCodes: number) {
    this.fps = fps;
    this.frameBytes = frameBytes;
    this.eccName = eccName;
    this.gridCodes = gridCodes;
    this.grid = gridDims(gridCodes);
  }

  get isRunning(): boolean {
    return this.running;
  }

  start(
    payload: Uint8Array,
    payloadName: string,
    payloadSize: number,
    compression: string,
    transmittedSize: number,
    onFrame: (cell: CellRaster) => void,
    onLocked: (spec: StreamLockSpec) => void,
    onError: (message: string) => void,
  ): void {
    this.stop();
    this.payloadName = payloadName;
    this.payloadSize = payloadSize;
    this.compression = compression;
    this.transmittedSize = transmittedSize;
    this.onFrameCb = onFrame;
    this.onLockedCb = onLocked;
    this.onErrorCb = onError;
    const gen: number = ++this.generation;

    const sessionId: number = (Math.floor(Math.random() * 0xffff) + 1) & 0xffff;
    const blockLen: number = this.frameBytes - 20;
    this.encoder = new LTEncoder(payload, blockLen, sessionId);
    this.header = {
      sessionId,
      seq: 0,
      k: this.encoder.k,
      blockLen,
      totalLen: payload.length,
      payloadFnv: fnv1a(payload),
    };
    this.nextSeq = 0;
    this.ready = [];
    this.generating = false;
    this.locked = false;
    this.running = true;
    this.displayInterval = Math.max(16, Math.round(1000 / (this.fps * this.gridCodes)));
    this.nextDisplayAt = Date.now();
    this.pump(gen);
    this.timerId = setInterval(() => this.tick(gen), this.displayInterval);
  }

  stop(): void {
    this.generation++;
    this.running = false;
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    this.ready = [];
    this.onFrameCb = undefined;
    this.onLockedCb = undefined;
    this.onErrorCb = undefined;
  }

  private pump(gen: number): void {
    if (!this.running || this.generating || gen !== this.generation) {
      return;
    }
    if (this.ready.length >= LOOKAHEAD) {
      return;
    }
    const encoder: LTEncoder | undefined = this.encoder;
    const header: FrameHeader | undefined = this.header;
    if (encoder === undefined || header === undefined) {
      return;
    }
    const seq: number = this.nextSeq++;
    const frame: FrameHeader = {
      sessionId: header.sessionId,
      seq,
      k: header.k,
      blockLen: header.blockLen,
      totalLen: header.totalLen,
      payloadFnv: header.payloadFnv,
    };
    const bytes: Uint8Array = packFrame(frame, encoder.encode(seq));
    this.generating = true;
    const task: taskpool.Task = new taskpool.Task(
      generateFrameRaster,
      bytes.buffer,
      this.eccName,
      QR_MARGIN,
      seq % this.gridCodes,
      seq,
    );
    taskpool.execute(task).then((res: Object) => {
      this.generating = false;
      if (!this.running || gen !== this.generation) {
        return;
      }
      const r: FrameCellResult = res as FrameCellResult;
      this.ready.push(r);
      if (!this.locked) {
        this.locked = true;
        this.notifyLocked(r, encoder, header);
      }
      this.pump(gen);
    }).catch((err: Error) => {
      this.generating = false;
      if (gen !== this.generation) {
        return;
      }
      this.stop();
      const onError: ((message: string) => void) | undefined = this.onErrorCb;
      if (onError !== undefined) {
        onError(err.message);
      }
    });
  }

  private notifyLocked(r: FrameCellResult, encoder: LTEncoder, header: FrameHeader): void {
    const onLocked: ((spec: StreamLockSpec) => void) | undefined = this.onLockedCb;
    if (onLocked !== undefined) {
      const spec: StreamLockSpec = {
        fps: this.fps,
        frameBytes: this.frameBytes,
        eccName: this.eccName,
        gridCodes: this.gridCodes,
        gridCols: this.grid.cols,
        gridRows: this.grid.rows,
        version: r.version,
        modules: r.modules,
        cellSize: r.cellSize,
        k: encoder.k,
        blockLen: header.blockLen,
        sessionId: header.sessionId,
        payloadName: this.payloadName,
        payloadSize: this.payloadSize,
        compression: this.compression,
        transmittedSize: this.transmittedSize,
      };
      onLocked(spec);
    }
  }

  private tick(gen: number): void {
    if (!this.running || gen !== this.generation) {
      return;
    }
    const now: number = Date.now();
    if (now < this.nextDisplayAt) {
      return;
    }
    this.nextDisplayAt = now + this.displayInterval;
    if (this.ready.length > 0) {
      const r: FrameCellResult = this.ready.shift() as FrameCellResult;
      const onFrame: ((cell: CellRaster) => void) | undefined = this.onFrameCb;
      if (onFrame !== undefined) {
        onFrame({ cellIndex: r.cellIndex, cellSize: r.cellSize, raster: new Uint32Array(r.pixels) });
      }
    }
    this.pump(gen);
  }
}
