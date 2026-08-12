import { EcLevel, ECC_H, ECC_L, ECC_M, ECC_Q, createQrSymbol } from '../qr/QrEncoder';
import { rasterizeQr } from '../common/QrRaster';

export interface FrameCellResult {
  seq: number;
  cellIndex: number;
  cellSize: number;
  modules: number;
  version: number;
  pixels: ArrayBuffer;
}

@Concurrent
export function generateFrameRaster(
  frameBytes: ArrayBuffer,
  eccName: string,
  margin: number,
  cellIndex: number,
  seq: number,
): FrameCellResult {
  let ecc: EcLevel = ECC_L;
  if (eccName === 'M') {
    ecc = ECC_M;
  } else if (eccName === 'Q') {
    ecc = ECC_Q;
  } else if (eccName === 'H') {
    ecc = ECC_H;
  }
  const bytes: Uint8Array = new Uint8Array(frameBytes);
  const symbol = createQrSymbol(bytes, ecc, undefined, 4);
  const raster = rasterizeQr(symbol.modules.size, symbol.modules.data, margin);
  const cellSize: number = symbol.modules.size + 2 * margin;
  const modules: number = symbol.modules.size;
  const version: number = symbol.version;
  return {
    seq: seq,
    cellIndex: cellIndex,
    cellSize: cellSize,
    modules: modules,
    version: version,
    pixels: raster.pixels.buffer as ArrayBuffer,
  };
}
