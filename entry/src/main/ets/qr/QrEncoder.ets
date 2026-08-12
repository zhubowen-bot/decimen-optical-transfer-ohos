// QR Code symbol generator — a faithful ArkTS port of the `qrcode` npm
// package's byte-mode core (MIT, Ryan Day / Kazuhiko Arase), stripped to what
// the Decimen sender needs: byte-mode segments, explicit version selection and
// a pinned mask pattern. Every table and every arithmetic operation is copied
// verbatim so the emitted symbols decode identically on the web receiver.

export class EcLevel {
  readonly bit: number;
  readonly tableIndex: number;

  constructor(bit: number, tableIndex: number) {
    this.bit = bit;
    this.tableIndex = tableIndex;
  }
}

export const ECC_L: EcLevel = new EcLevel(1, 0);
export const ECC_M: EcLevel = new EcLevel(0, 1);
export const ECC_Q: EcLevel = new EcLevel(3, 2);
export const ECC_H: EcLevel = new EcLevel(2, 3);

export function eccFromString(value: string): EcLevel {
  switch (value.toLowerCase()) {
    case 'l':
    case 'low':
      return ECC_L;
    case 'm':
    case 'medium':
      return ECC_M;
    case 'q':
    case 'quartile':
      return ECC_Q;
    case 'h':
    case 'high':
      return ECC_H;
    default:
      throw new Error(`Unknown EC Level: ${value}`);
  }
}

class Mode {
  readonly bit: number;
  readonly ccBits: number[];

  constructor(bit: number, ccBits: number[]) {
    this.bit = bit;
    this.ccBits = ccBits;
  }
}

const MODE_BYTE: Mode = new Mode(1 << 2, [8, 16, 16]);

function getCharCountIndicator(mode: Mode, version: number): number {
  if (version >= 1 && version < 10) {
    return mode.ccBits[0];
  } else if (version < 27) {
    return mode.ccBits[1];
  }
  return mode.ccBits[2];
}

class ByteSegment {
  readonly mode: Mode = MODE_BYTE;
  readonly data: Uint8Array;

  constructor(data: Uint8Array) {
    this.data = data;
  }

  getLength(): number {
    return this.data.length;
  }

  getBitsLength(): number {
    return this.data.length * 8;
  }

  write(bitBuffer: BitBuffer): void {
    for (let i = 0; i < this.data.length; i++) {
      bitBuffer.put(this.data[i], 8);
    }
  }
}

// ------------------------------------------------------------- tables

const CODEWORDS_COUNT: number[] = [
  0, 26, 44, 70, 100, 134, 172, 196, 242, 292, 346,
  404, 466, 532, 581, 655, 733, 815, 901, 991, 1085,
  1156, 1258, 1364, 1474, 1588, 1706, 1828, 1921, 2051, 2185,
  2323, 2465, 2611, 2761, 2876, 3034, 3196, 3362, 3532, 3706,
];

const EC_BLOCKS_TABLE: number[] = [
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 1, 2, 2, 4, 1, 2, 4, 4,
  2, 4, 4, 4, 2, 4, 6, 5, 2, 4, 6, 6, 2, 5, 8, 8, 4, 5, 8, 8,
  4, 5, 8, 11, 4, 8, 10, 11, 4, 9, 12, 16, 4, 9, 16, 16, 6, 10, 12, 18,
  6, 10, 17, 16, 6, 11, 16, 19, 6, 13, 18, 21, 7, 14, 21, 25, 8, 16, 20, 25,
  8, 17, 23, 25, 9, 17, 23, 34, 9, 18, 25, 30, 10, 20, 27, 32, 12, 21, 29, 35,
  12, 23, 34, 37, 12, 25, 34, 40, 13, 26, 35, 42, 14, 28, 38, 45, 15, 29, 40, 48,
  16, 31, 43, 51, 17, 33, 45, 54, 18, 35, 48, 57, 19, 37, 51, 60, 19, 38, 53, 63,
  20, 40, 56, 66, 21, 43, 59, 70, 22, 45, 62, 74, 24, 47, 65, 77, 25, 49, 68, 81,
];

const EC_CODEWORDS_TABLE: number[] = [
  7, 10, 13, 17, 10, 16, 22, 28, 15, 26, 36, 44, 20, 36, 52, 64,
  26, 48, 72, 88, 36, 64, 96, 112, 40, 72, 108, 130, 48, 88, 132, 156,
  60, 110, 160, 192, 72, 130, 192, 224, 80, 150, 224, 264, 96, 176, 260, 308,
  104, 198, 288, 352, 120, 216, 320, 384, 132, 240, 360, 432, 144, 280, 408, 480,
  168, 308, 448, 532, 180, 338, 504, 588, 196, 364, 546, 650, 224, 416, 600, 700,
  224, 442, 644, 750, 252, 476, 690, 816, 270, 504, 750, 900, 300, 560, 810, 960,
  312, 588, 870, 1050, 336, 644, 952, 1110, 360, 700, 1020, 1200, 390, 728, 1050, 1260,
  420, 784, 1140, 1350, 450, 812, 1200, 1440, 480, 868, 1290, 1530, 510, 924, 1350, 1620,
  540, 980, 1440, 1710, 570, 1036, 1530, 1800, 570, 1064, 1590, 1890, 600, 1120, 1680, 1980,
  630, 1204, 1770, 2100, 660, 1260, 1860, 2220, 720, 1316, 1950, 2310, 750, 1372, 2040, 2430,
];

function getSymbolSize(version: number): number {
  return version * 4 + 17;
}

function getSymbolTotalCodewords(version: number): number {
  return CODEWORDS_COUNT[version];
}

function getBCHDigit(data: number): number {
  let digit: number = 0;
  let d: number = data;
  while (d !== 0) {
    digit++;
    d >>>= 1;
  }
  return digit;
}

function getBlocksCount(version: number, level: EcLevel): number {
  return EC_BLOCKS_TABLE[(version - 1) * 4 + level.tableIndex];
}

function getTotalCodewordsCount(version: number, level: EcLevel): number {
  return EC_CODEWORDS_TABLE[(version - 1) * 4 + level.tableIndex];
}

// ------------------------------------------------------------- Galois field

const EXP_TABLE: Uint8Array = new Uint8Array(512);
const LOG_TABLE: Uint8Array = new Uint8Array(256);

function initGaloisTables(): void {
  let x: number = 1;
  for (let i = 0; i < 255; i++) {
    EXP_TABLE[i] = x;
    LOG_TABLE[x] = i;
    x <<= 1;
    if (x & 0x100) {
      x ^= 0x11d;
    }
  }
  for (let i = 255; i < 512; i++) {
    EXP_TABLE[i] = EXP_TABLE[i - 255];
  }
}

function gfExp(n: number): number {
  return EXP_TABLE[n];
}

function gfMul(x: number, y: number): number {
  if (x === 0 || y === 0) {
    return 0;
  }
  return EXP_TABLE[LOG_TABLE[x] + LOG_TABLE[y]];
}

// ------------------------------------------------------------- polynomials

function polyMul(p1: Uint8Array, p2: Uint8Array): Uint8Array {
  const coeff: Uint8Array = new Uint8Array(p1.length + p2.length - 1);
  for (let i = 0; i < p1.length; i++) {
    for (let j = 0; j < p2.length; j++) {
      coeff[i + j] = coeff[i + j] ^ gfMul(p1[i], p2[j]);
    }
  }
  return coeff;
}

function polyMod(divident: Uint8Array, divisor: Uint8Array): Uint8Array {
  let result: Uint8Array = new Uint8Array(divident);
  while ((result.length - divisor.length) >= 0) {
    const coeff: number = result[0];
    for (let i = 0; i < divisor.length; i++) {
      result[i] = result[i] ^ gfMul(divisor[i], coeff);
    }
    let offset: number = 0;
    while (offset < result.length && result[offset] === 0) {
      offset++;
    }
    result = result.slice(offset);
  }
  return result;
}

function generateECPolynomial(degree: number): Uint8Array {
  let poly: Uint8Array = new Uint8Array([1]);
  for (let i = 0; i < degree; i++) {
    poly = polyMul(poly, new Uint8Array([1, gfExp(i)]));
  }
  return poly;
}

class ReedSolomonEncoder {
  private genPoly: Uint8Array | undefined;
  private degree: number;

  constructor(degree: number) {
    this.degree = degree;
    if (degree > 0) {
      this.genPoly = generateECPolynomial(degree);
    }
  }

  encode(data: Uint8Array): Uint8Array {
    const gen: Uint8Array | undefined = this.genPoly;
    if (gen === undefined) {
      throw new Error('Encoder not initialized');
    }
    const paddedData: Uint8Array = new Uint8Array(data.length + this.degree);
    paddedData.set(data);
    const remainder: Uint8Array = polyMod(paddedData, gen);
    const start: number = this.degree - remainder.length;
    if (start > 0) {
      const buff: Uint8Array = new Uint8Array(this.degree);
      buff.set(remainder, start);
      return buff;
    }
    return remainder;
  }
}

// ------------------------------------------------------------- bit buffer

class BitBuffer {
  buffer: number[] = [];
  length: number = 0;

  put(num: number, len: number): void {
    for (let i = 0; i < len; i++) {
      this.putBit(((num >>> (len - i - 1)) & 1) === 1);
    }
  }

  getLengthInBits(): number {
    return this.length;
  }

  putBit(bit: boolean): void {
    const bufIndex: number = Math.floor(this.length / 8);
    if (this.buffer.length <= bufIndex) {
      this.buffer.push(0);
    }
    if (bit) {
      this.buffer[bufIndex] = this.buffer[bufIndex] | (0x80 >>> (this.length % 8));
    }
    this.length++;
  }
}

// ------------------------------------------------------------- bit matrix

export class BitMatrix {
  readonly size: number;
  readonly data: Uint8Array;
  readonly reservedBit: Uint8Array;

  constructor(size: number) {
    this.size = size;
    this.data = new Uint8Array(size * size);
    this.reservedBit = new Uint8Array(size * size);
  }

  set(row: number, col: number, value: boolean, reserved?: boolean): void {
    const index: number = row * this.size + col;
    this.data[index] = value ? 1 : 0;
    if (reserved !== undefined && reserved) {
      this.reservedBit[index] = 1;
    }
  }

  get(row: number, col: number): number {
    return this.data[row * this.size + col];
  }

  xor(row: number, col: number, value: boolean): void {
    const index: number = row * this.size + col;
    this.data[index] = this.data[index] ^ (value ? 1 : 0);
  }

  isReserved(row: number, col: number): boolean {
    return this.reservedBit[row * this.size + col] === 1;
  }
}

// ------------------------------------------------------------- patterns

function finderPositions(version: number): number[][] {
  const size: number = getSymbolSize(version);
  return [[0, 0], [size - 7, 0], [0, size - 7]];
}

function alignmentRowColCoords(version: number): number[] {
  if (version === 1) {
    return [];
  }
  const posCount: number = Math.floor(version / 7) + 2;
  const size: number = getSymbolSize(version);
  const intervals: number =
    size === 145 ? 26 : Math.ceil((size - 13) / (2 * posCount - 2)) * 2;
  const positions: number[] = [size - 7];
  for (let i = 1; i < posCount - 1; i++) {
    positions[i] = positions[i - 1] - intervals;
  }
  positions.push(6);
  return positions.reverse();
}

function alignmentPositions(version: number): number[][] {
  const coords: number[][] = [];
  const pos: number[] = alignmentRowColCoords(version);
  const posLength: number = pos.length;
  for (let i = 0; i < posLength; i++) {
    for (let j = 0; j < posLength; j++) {
      if ((i === 0 && j === 0) || (i === 0 && j === posLength - 1) ||
        (i === posLength - 1 && j === 0)) {
        continue;
      }
      coords.push([pos[i], pos[j]]);
    }
  }
  return coords;
}

const G15: number = (1 << 10) | (1 << 8) | (1 << 5) | (1 << 4) | (1 << 2) | (1 << 1) | (1 << 0);
const G15_MASK: number = (1 << 14) | (1 << 12) | (1 << 10) | (1 << 4) | (1 << 1);
const G15_BCH: number = getBCHDigit(G15);

function getFormatEncodedBits(level: EcLevel, mask: number): number {
  const data: number = ((level.bit << 3) | mask);
  let d: number = data << 10;
  while (getBCHDigit(d) - G15_BCH >= 0) {
    d = d ^ (G15 << (getBCHDigit(d) - G15_BCH));
  }
  return ((data << 10) | d) ^ G15_MASK;
}

const G18: number = (1 << 12) | (1 << 11) | (1 << 10) | (1 << 9) | (1 << 8) | (1 << 5) | (1 << 2) | (1 << 0);
const G18_BCH: number = getBCHDigit(G18);

function getVersionEncodedBits(version: number): number {
  let d: number = version << 12;
  while (getBCHDigit(d) - G18_BCH >= 0) {
    d = d ^ (G18 << (getBCHDigit(d) - G18_BCH));
  }
  return (version << 12) | d;
}

function getCapacity(version: number, level: EcLevel, mode: Mode): number {
  const totalCodewords: number = getSymbolTotalCodewords(version);
  const ecTotalCodewords: number = getTotalCodewordsCount(version, level);
  const dataTotalCodewordsBits: number = (totalCodewords - ecTotalCodewords) * 8;
  const usableBits: number = dataTotalCodewordsBits -
    (getCharCountIndicator(mode, version) + 4);
  return Math.floor(usableBits / 8);
}

function getBestVersionForDataLength(length: number, level: EcLevel): number | undefined {
  for (let currentVersion = 1; currentVersion <= 40; currentVersion++) {
    if (length <= getCapacity(currentVersion, level, MODE_BYTE)) {
      return currentVersion;
    }
  }
  return undefined;
}

function getMaskAt(maskPattern: number, i: number, j: number): boolean {
  switch (maskPattern) {
    case 0:
      return (i + j) % 2 === 0;
    case 1:
      return i % 2 === 0;
    case 2:
      return j % 3 === 0;
    case 3:
      return (i + j) % 3 === 0;
    case 4:
      return (Math.floor(i / 2) + Math.floor(j / 3)) % 2 === 0;
    case 5:
      return (i * j) % 2 + (i * j) % 3 === 0;
    case 6:
      return ((i * j) % 2 + (i * j) % 3) % 2 === 0;
    case 7:
      return ((i * j) % 3 + (i + j) % 2) % 2 === 0;
    default:
      throw new Error(`bad maskPattern:${maskPattern}`);
  }
}

function applyMask(pattern: number, data: BitMatrix): void {
  const size: number = data.size;
  for (let col = 0; col < size; col++) {
    for (let row = 0; row < size; row++) {
      if (data.isReserved(row, col)) {
        continue;
      }
      data.xor(row, col, getMaskAt(pattern, row, col));
    }
  }
}

// ------------------------------------------------------------- symbol build

function setupFinderPattern(matrix: BitMatrix, version: number): void {
  const size: number = matrix.size;
  const pos: number[][] = finderPositions(version);
  for (let i = 0; i < pos.length; i++) {
    const row: number = pos[i][0];
    const col: number = pos[i][1];
    for (let r = -1; r <= 7; r++) {
      if (row + r <= -1 || size <= row + r) {
        continue;
      }
      for (let c = -1; c <= 7; c++) {
        if (col + c <= -1 || size <= col + c) {
          continue;
        }
        if ((r >= 0 && r <= 6 && (c === 0 || c === 6)) ||
          (c >= 0 && c <= 6 && (r === 0 || r === 6)) ||
          (r >= 2 && r <= 4 && c >= 2 && c <= 4)) {
          matrix.set(row + r, col + c, true, true);
        } else {
          matrix.set(row + r, col + c, false, true);
        }
      }
    }
  }
}

function setupTimingPattern(matrix: BitMatrix): void {
  const size: number = matrix.size;
  for (let r = 8; r < size - 8; r++) {
    const value: boolean = r % 2 === 0;
    matrix.set(r, 6, value, true);
    matrix.set(6, r, value, true);
  }
}

function setupAlignmentPattern(matrix: BitMatrix, version: number): void {
  const pos: number[][] = alignmentPositions(version);
  for (let i = 0; i < pos.length; i++) {
    const row: number = pos[i][0];
    const col: number = pos[i][1];
    for (let r = -2; r <= 2; r++) {
      for (let c = -2; c <= 2; c++) {
        if (r === -2 || r === 2 || c === -2 || c === 2 || (r === 0 && c === 0)) {
          matrix.set(row + r, col + c, true, true);
        } else {
          matrix.set(row + r, col + c, false, true);
        }
      }
    }
  }
}

function setupVersionInfo(matrix: BitMatrix, version: number): void {
  const size: number = matrix.size;
  const bits: number = getVersionEncodedBits(version);
  for (let i = 0; i < 18; i++) {
    const row: number = Math.floor(i / 3);
    const col: number = i % 3 + size - 8 - 3;
    const mod: boolean = ((bits >> i) & 1) === 1;
    matrix.set(row, col, mod, true);
    matrix.set(col, row, mod, true);
  }
}

function setupFormatInfo(matrix: BitMatrix, level: EcLevel, maskPattern: number): void {
  const size: number = matrix.size;
  const bits: number = getFormatEncodedBits(level, maskPattern);
  for (let i = 0; i < 15; i++) {
    const mod: boolean = ((bits >> i) & 1) === 1;
    if (i < 6) {
      matrix.set(i, 8, mod, true);
    } else if (i < 8) {
      matrix.set(i + 1, 8, mod, true);
    } else {
      matrix.set(size - 15 + i, 8, mod, true);
    }
    if (i < 8) {
      matrix.set(8, size - i - 1, mod, true);
    } else if (i < 9) {
      matrix.set(8, 15 - i - 1 + 1, mod, true);
    } else {
      matrix.set(8, 15 - i - 1, mod, true);
    }
  }
  matrix.set(size - 8, 8, true, true);
}

function setupData(matrix: BitMatrix, data: Uint8Array): void {
  const size: number = matrix.size;
  let inc: number = -1;
  let row: number = size - 1;
  let bitIndex: number = 7;
  let byteIndex: number = 0;
  for (let col = size - 1; col > 0; col -= 2) {
    if (col === 6) {
      col--;
    }
    while (true) {
      for (let c = 0; c < 2; c++) {
        if (!matrix.isReserved(row, col - c)) {
          let dark: boolean = false;
          if (byteIndex < data.length) {
            dark = (((data[byteIndex] >>> bitIndex) & 1) === 1);
          }
          matrix.set(row, col - c, dark);
          bitIndex--;
          if (bitIndex === -1) {
            byteIndex++;
            bitIndex = 7;
          }
        }
      }
      row += inc;
      if (row < 0 || size <= row) {
        row -= inc;
        inc = -inc;
        break;
      }
    }
  }
}

function createData(version: number, level: EcLevel, segment: ByteSegment): Uint8Array {
  const buffer: BitBuffer = new BitBuffer();
  buffer.put(segment.mode.bit, 4);
  buffer.put(segment.getLength(), getCharCountIndicator(segment.mode, version));
  segment.write(buffer);

  const totalCodewords: number = getSymbolTotalCodewords(version);
  const ecTotalCodewords: number = getTotalCodewordsCount(version, level);
  const dataTotalCodewordsBits: number = (totalCodewords - ecTotalCodewords) * 8;

  if (buffer.getLengthInBits() + 4 <= dataTotalCodewordsBits) {
    buffer.put(0, 4);
  }
  while (buffer.getLengthInBits() % 8 !== 0) {
    buffer.putBit(false);
  }
  const remainingByte: number = (dataTotalCodewordsBits - buffer.getLengthInBits()) / 8;
  for (let i = 0; i < remainingByte; i++) {
    buffer.put(i % 2 ? 0x11 : 0xec, 8);
  }
  return createCodewords(buffer, version, level);
}

function createCodewords(bitBuffer: BitBuffer, version: number, level: EcLevel): Uint8Array {
  const totalCodewords: number = getSymbolTotalCodewords(version);
  const ecTotalCodewords: number = getTotalCodewordsCount(version, level);
  const dataTotalCodewords: number = totalCodewords - ecTotalCodewords;
  const ecTotalBlocks: number = getBlocksCount(version, level);

  const blocksInGroup2: number = totalCodewords % ecTotalBlocks;
  const blocksInGroup1: number = ecTotalBlocks - blocksInGroup2;
  const totalCodewordsInGroup1: number = Math.floor(totalCodewords / ecTotalBlocks);
  const dataCodewordsInGroup1: number = Math.floor(dataTotalCodewords / ecTotalBlocks);
  const dataCodewordsInGroup2: number = dataCodewordsInGroup1 + 1;
  const ecCount: number = totalCodewordsInGroup1 - dataCodewordsInGroup1;

  const rs: ReedSolomonEncoder = new ReedSolomonEncoder(ecCount);
  let offset: number = 0;
  const dcData: Uint8Array[] = [];
  const ecData: Uint8Array[] = [];
  let maxDataSize: number = 0;
  const buffer: Uint8Array = new Uint8Array(bitBuffer.buffer);

  for (let b = 0; b < ecTotalBlocks; b++) {
    const dataSize: number = b < blocksInGroup1 ? dataCodewordsInGroup1 : dataCodewordsInGroup2;
    dcData[b] = buffer.slice(offset, offset + dataSize);
    ecData[b] = rs.encode(dcData[b]);
    offset += dataSize;
    maxDataSize = Math.max(maxDataSize, dataSize);
  }

  const data: Uint8Array = new Uint8Array(totalCodewords);
  let index: number = 0;
  for (let i = 0; i < maxDataSize; i++) {
    for (let r = 0; r < ecTotalBlocks; r++) {
      const block: Uint8Array = dcData[r];
      if (i < block.length) {
        data[index++] = block[i];
      }
    }
  }
  for (let i = 0; i < ecCount; i++) {
    for (let r = 0; r < ecTotalBlocks; r++) {
      const block: Uint8Array = ecData[r];
      data[index++] = block[i];
    }
  }
  return data;
}

export interface QrSymbol {
  modules: BitMatrix;
  version: number;
}

export function createQrSymbol(
  bytes: Uint8Array,
  level: EcLevel,
  version: number | undefined,
  maskPattern: number,
): QrSymbol {
  initGaloisTables();
  const segment: ByteSegment = new ByteSegment(bytes);
  const bestVersion: number | undefined = getBestVersionForDataLength(segment.getLength(), level);
  if (bestVersion === undefined) {
    throw new Error('The amount of data is too big to be stored in a QR Code');
  }
  let finalVersion: number;
  if (version === undefined) {
    finalVersion = bestVersion;
  } else if (version < bestVersion) {
    throw new Error(
      `The chosen QR Code version cannot contain this amount of data.\n` +
      `Minimum version required to store current data is: ${bestVersion}.\n`);
  } else {
    finalVersion = version;
  }

  const dataBits: Uint8Array = createData(finalVersion, level, segment);
  const moduleCount: number = getSymbolSize(finalVersion);
  const modules: BitMatrix = new BitMatrix(moduleCount);

  setupFinderPattern(modules, finalVersion);
  setupTimingPattern(modules);
  setupAlignmentPattern(modules, finalVersion);
  setupFormatInfo(modules, level, 0);
  if (finalVersion >= 7) {
    setupVersionInfo(modules, finalVersion);
  }
  setupData(modules, dataBits);
  applyMask(maskPattern, modules);
  setupFormatInfo(modules, level, maskPattern);

  return { modules, version: finalVersion };
}
