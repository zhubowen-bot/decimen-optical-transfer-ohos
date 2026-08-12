import { taskpool } from '@kit.ArkTS';
import { decodeQr, QrDecodeResult } from '../qr/QrDecoder';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface DecodeTaskResult {
  bytes: ArrayBuffer;
  x: number;
  y: number;
  w: number;
  h: number;
  ok: boolean;
  version: number;
}

@Concurrent
export function runQrDecode(
  grayBuf: ArrayBuffer,
  w: number,
  h: number,
  ox: number,
  oy: number,
  scale: number,
): DecodeTaskResult {
  const gray: Uint8Array = new Uint8Array(grayBuf);
  const rgba: Uint8ClampedArray = new Uint8ClampedArray(w * h * 4);
  let o: number = 0;
  for (let i = 0; i < gray.length; i++) {
    rgba[o++] = gray[i];
    rgba[o++] = gray[i];
    rgba[o++] = gray[i];
    rgba[o++] = 255;
  }
  const t0: number = Date.now();
  const result: QrDecodeResult | undefined = decodeQr(rgba, w, h);
  const dt: number = Date.now() - t0;
  if (dt > 50) {
    hilog.info(0xdc1, 'Decimen', 'qr decode %{public}dx%{public}d took %{public}dms ok=%{public}d',
      w, h, dt, result === undefined ? 0 : result.ok ? 1 : 0);
  }
  if (result === undefined) {
    return { bytes: new ArrayBuffer(0), x: ox, y: oy, w: 0, h: 0, ok: false, version: 0 };
  }
  if (!result.ok) {
    // Finder patterns located, but the grid could not be extracted at this
    // resolution. Pass the box through so the pipeline can re-decode the
    // region from a higher-resolution frame.
    return {
      bytes: new ArrayBuffer(0),
      x: ox + result.x * scale,
      y: oy + result.y * scale,
      w: result.w * scale,
      h: result.h * scale,
      ok: false,
      version: 0,
    };
  }
  const bytes: ArrayBuffer = new ArrayBuffer(result.bytes.byteLength);
  new Uint8Array(bytes).set(result.bytes);
  return {
    bytes,
    x: ox + result.x * scale,
    y: oy + result.y * scale,
    w: result.w * scale,
    h: result.h * scale,
    ok: true,
    version: result.version,
  };
}
