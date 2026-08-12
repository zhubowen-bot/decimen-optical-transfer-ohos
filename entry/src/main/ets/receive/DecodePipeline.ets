import { taskpool } from '@kit.ArkTS';
import { runQrDecode, DecodeTaskResult } from './DecodeTask';

export interface SymbolBox {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface Region {
  x: number;
  y: number;
  w: number;
  h: number;
  seen: number;
  decoded: boolean;
  drift: number;
}

const REGION_TTL_MS: number = 1500;
const EXPECTED_REGIONS_DECAY_MS: number = 10000;
const REGION_PAD: number = 0.35;
const MAX_REGIONS: number = 9;
const ACQ_TARGET_W: number = 640;
const ACQUISITION_SCAN_MS: number = 100;
const FULL_SCAN_DEGRADED_MS: number = 250;
const FULL_SCAN_INTERVAL_MS: number = 1500;

export class DecodePipeline {
  private regions: Region[] = [];
  private onDecodedCb: ((bytes: Uint8Array) => void) | undefined = undefined;
  private onRegionsCb: ((boxes: SymbolBox[]) => void) | undefined = undefined;
  private lastFullScan: number = 0;
  private cropRotate: number = 0;
  private expectedRegions: number = 0;
  private expectedRegionsAt: number = 0;
  private inFlight: number = 0;
  private maxInFlight: number = 6;
  private stopped: boolean = false;
  private forceFull: boolean = false;

  constructor(onDecoded: (bytes: Uint8Array) => void, onRegions: (boxes: SymbolBox[]) => void) {
    this.onDecodedCb = onDecoded;
    this.onRegionsCb = onRegions;
  }

  get busyCount(): number {
    return this.inFlight;
  }

  reset(): void {
    this.regions = [];
    this.lastFullScan = 0;
    this.cropRotate = 0;
    this.expectedRegions = 0;
    this.inFlight = 0;
    this.stopped = false;
  }

  stop(): void {
    this.stopped = true;
  }

  submitFrame(gray: Uint8Array, w: number, h: number, now: number): void {
    if (this.stopped) {
      return;
    }
    for (let i = this.regions.length - 1; i >= 0; i--) {
      if (now - this.regions[i].seen > REGION_TTL_MS) {
        this.regions.splice(i, 1);
      }
    }
    const located: number = this.regions.length;
    const live: number = this.decodedCount();
    if (live >= this.expectedRegions || now - this.expectedRegionsAt > EXPECTED_REGIONS_DECAY_MS) {
      this.expectedRegions = live;
      this.expectedRegionsAt = now;
    }
    const scanInterval: number =
      located === 0 ? ACQUISITION_SCAN_MS :
      live === 0 ? FULL_SCAN_DEGRADED_MS :
      live < this.expectedRegions ? FULL_SCAN_DEGRADED_MS : FULL_SCAN_INTERVAL_MS;
    let fullScanDue: boolean = now - this.lastFullScan > scanInterval;
    if (this.forceFull) {
      fullScanDue = true;
    }

    const free: number = this.maxInFlight - this.inFlight;
    if (free <= 0) {
      return;
    }
    // Region crops get priority: they re-decode the tracked code at full
    // resolution. A full scan only fills leftover slots.
    let slots: number = free;
    for (let i = 0; i < this.regions.length && slots > 0; i++) {
      const r: Region = this.regions[(i + this.cropRotate) % this.regions.length];
      const size: number = Math.max(r.w, r.h);
      const pad: number = Math.round(size * REGION_PAD + Math.min(size, 2 * r.drift));
      const x: number = Math.max(0, Math.floor(r.x - pad));
      const y: number = Math.max(0, Math.floor(r.y - pad));
      const cw: number = Math.min(w - x, Math.ceil(r.w + 2 * pad));
      const ch: number = Math.min(h - y, Math.ceil(r.h + 2 * pad));
      if (cw >= 32 && ch >= 32) {
        slots--;
        r.seen = now;
        this.dispatchCrop(gray, w, x, y, cw, ch);
      }
    }
    this.cropRotate++;
    if (slots > 0 && fullScanDue) {
      this.forceFull = false;
      this.lastFullScan = now;
      this.dispatchFull(gray, w, h);
    }
  }

  private decodedCount(): number {
    let n: number = 0;
    for (const r of this.regions) {
      if (r.decoded) {
        n++;
      }
    }
    return n;
  }

  private dispatchFull(gray: Uint8Array, w: number, h: number): void {
    // Fast acquisition pass: downscale to ~640 wide so jsqr runs quickly. If a
    // dense code cannot be extracted at this resolution, the returned box
    // spawns a full-resolution crop of the code region (dispatched by the
    // region loop on the next frame), which has enough pixels per module.
    const scale: number = Math.max(1, Math.round(w / ACQ_TARGET_W));
    const dw: number = Math.round(w / scale);
    const dh: number = Math.round(h / scale);
    const buf: ArrayBuffer = new ArrayBuffer(dw * dh);
    const dst: Uint8Array = new Uint8Array(buf);
    for (let y = 0; y < dh; y++) {
      const srcRow: number = Math.min(h - 1, y * scale) * w;
      const dstRow: number = y * dw;
      for (let x = 0; x < dw; x++) {
        dst[dstRow + x] = gray[srcRow + Math.min(w - 1, x * scale)];
      }
    }
    this.dispatch(buf, dw, dh, 0, 0, scale);
  }

  private dispatchCrop(gray: Uint8Array, frameW: number, ox: number, oy: number, cw: number, ch: number): void {
    const buf: ArrayBuffer = new ArrayBuffer(cw * ch);
    const dst: Uint8Array = new Uint8Array(buf);
    for (let y = oy; y < oy + ch; y++) {
      const srcRow: number = y * frameW + ox;
      dst.set(gray.subarray(srcRow, srcRow + cw), (y - oy) * cw);
    }
    this.dispatch(buf, cw, ch, ox, oy, 1);
  }

  private dispatch(buf: ArrayBuffer, w: number, h: number, ox: number, oy: number, scale: number): void {
    this.inFlight++;
    const task: taskpool.Task = new taskpool.Task(runQrDecode, buf, w, h, ox, oy, scale);
    task.setTransferList([buf]);
    taskpool.execute(task).then((res: Object) => {
      this.inFlight--;
      const r: DecodeTaskResult = res as DecodeTaskResult;
      this.handleResult(r);
    }).catch(() => {
      this.inFlight--;
    });
  }

  private handleResult(r: DecodeTaskResult): void {
    if (this.stopped) {
      return;
    }
    if (r.ok) {
      const bytes: Uint8Array = new Uint8Array(r.bytes);
      const now: number = Date.now();
      this.noteRegion({ x: r.x, y: r.y, w: r.w, h: r.h }, now, true);
      const cb: ((bytes: Uint8Array) => void) | undefined = this.onDecodedCb;
      if (cb !== undefined) {
        cb(bytes);
      }
    } else if (r.w > 0) {
      // Finder patterns located but the grid could not be extracted at the
      // decode resolution (too few pixels per module). Track the box; the
      // region loop re-decodes it as a full-resolution crop.
      this.noteRegion({ x: r.x, y: r.y, w: r.w, h: r.h }, Date.now(), false);
    } else {
      // Nothing found: schedule a prompt full re-scan.
      this.forceFull = true;
    }
    const onRegions: ((boxes: SymbolBox[]) => void) | undefined = this.onRegionsCb;
    if (onRegions !== undefined) {
      onRegions(this.snapshot());
    }
  }

  private noteRegion(box: SymbolBox, now: number, decoded: boolean): void {
    for (const r of this.regions) {
      const dx: number = Math.abs(box.x + box.w / 2 - (r.x + r.w / 2));
      const dy: number = Math.abs(box.y + box.h / 2 - (r.y + r.h / 2));
      if (dx < Math.max(box.w, r.w) / 2 && dy < Math.max(box.h, r.h) / 2) {
        const move: number = Math.sqrt(dx * dx + dy * dy);
        r.drift = 0.5 * r.drift + 0.5 * move;
        r.x = box.x;
        r.y = box.y;
        r.w = box.w;
        r.h = box.h;
        r.seen = now;
        r.decoded = decoded;
        return;
      }
    }
    if (this.regions.length < MAX_REGIONS) {
      this.regions.push({ x: box.x, y: box.y, w: box.w, h: box.h, seen: now, decoded, drift: 0 });
    }
  }

  private snapshot(): SymbolBox[] {
    const out: SymbolBox[] = [];
    for (const r of this.regions) {
      if (r.decoded) {
        out.push({ x: r.x, y: r.y, w: r.w, h: r.h });
      }
    }
    return out;
  }
}
