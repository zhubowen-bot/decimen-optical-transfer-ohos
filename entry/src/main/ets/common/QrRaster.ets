const WHITE: number = 0xffffffff;
const BLACK: number = 0xff000000;

export interface QrRaster {
  size: number;
  pixels: Uint32Array;
}

export interface QrGridRaster {
  width: number;
  height: number;
  pixels: Uint32Array;
}

export function rasterizeQr(moduleCount: number, modules: ArrayLike<number>, margin: number): QrRaster {
  const size: number = moduleCount + 2 * margin;
  const pixels: Uint32Array = new Uint32Array(size * size);
  pixels.fill(WHITE);
  for (let y = 0; y < moduleCount; y++) {
    const row: number = (y + margin) * size + margin;
    const src: number = y * moduleCount;
    for (let x = 0; x < moduleCount; x++) {
      if (modules[src + x]) {
        pixels[row + x] = BLACK;
      }
    }
  }
  return { size, pixels };
}

export function gridDims(count: number): GridDims {
  const cols: number = Math.floor(Math.sqrt(count));
  const rows: number = Math.ceil(count / Math.max(1, cols));
  if (count < 1 || cols * rows !== count) {
    throw new Error(`grid needs a count that fills its rows (1, 2, 4, 6, 9…), got ${count}`);
  }
  return { cols, rows };
}

export interface GridDims {
  cols: number;
  rows: number;
}

export function rasterizeQrGrid(
  moduleCount: number,
  matrices: Array<ArrayLike<number>>,
  margin: number,
): QrGridRaster {
  const dims: GridDims = gridDims(matrices.length);
  const cell: number = moduleCount + 2 * margin;
  const width: number = dims.cols * cell;
  const height: number = dims.rows * cell;
  const pixels: Uint32Array = new Uint32Array(width * height);
  pixels.fill(WHITE);
  for (let i = 0; i < matrices.length; i++) {
    const modules: ArrayLike<number> = matrices[i];
    const ox: number = (i % dims.cols) * cell + margin;
    const oy: number = Math.floor(i / dims.cols) * cell + margin;
    for (let y = 0; y < moduleCount; y++) {
      const row: number = (y + oy) * width + ox;
      const src: number = y * moduleCount;
      for (let x = 0; x < moduleCount; x++) {
        if (modules[src + x]) {
          pixels[row + x] = BLACK;
        }
      }
    }
  }
  return { width, height, pixels };
}
