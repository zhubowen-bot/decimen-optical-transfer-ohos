import { hilog } from '@kit.PerformanceAnalysisKit';

export interface QrDecodeResult {
  bytes: Uint8Array;
  version: number;
  x: number;
  y: number;
  w: number;
  h: number;
  ok: boolean;
}

interface Point {
  x: number;
  y: number;
}

interface QrBox {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface QRLocation {
  topRight: Point;
  bottomLeft: Point;
  topLeft: Point;
  alignmentPattern: Point;
  dimension: number;
}

interface QuadLine {
  startX: number;
  endX: number;
  y: number;
}

interface Quad {
  top: QuadLine;
  bottom: QuadLine;
}

interface FinderPatternOrder {
  bottomLeft: Point;
  topLeft: Point;
  topRight: Point;
}

interface ScoreResult {
  averageSize: number;
  error: number;
}

interface ScoredFinder {
  x: number;
  y: number;
  size: number;
  score: number;
}

interface FinderPatternGroup {
  points: Point[];
  score: number;
}

interface AlignmentResult {
  alignmentPattern: Point;
  dimension: number;
}

interface DimensionResult {
  dimension: number;
  moduleSize: number;
}

interface AlignmentCandidate {
  x: number;
  y: number;
  score: number;
}

interface PerspectiveTransform {
  a11: number;
  a21: number;
  a31: number;
  a12: number;
  a22: number;
  a32: number;
  a13: number;
  a23: number;
  a33: number;
}

interface FormatInformation {
  errorCorrectionLevel: number;
  dataMask: number;
}

interface FormatInfoEntry {
  bits: number;
  formatInfo: FormatInformation;
}

interface ECBlockInfo {
  numBlocks: number;
  dataCodewordsPerBlock: number;
}

interface ECLevelInfo {
  ecCodewordsPerBlock: number;
  ecBlocks: ECBlockInfo[];
}

interface VersionInfo {
  infoBits: number;
  versionNumber: number;
  alignmentPatternCenters: number[];
  errorCorrectionLevels: ECLevelInfo[];
}

interface DataBlock {
  numDataCodewords: number;
  codewords: number[];
}

interface DecodedQR {
  text: string;
  bytes: number[];
  chunks: Chunk[];
  version: number;
  box?: QrBox;
}

function boundingBox(location: QRLocation): QrBox {
  let minX: number = location.topLeft.x;
  let minY: number = location.topLeft.y;
  let maxX: number = location.topLeft.x;
  let maxY: number = location.topLeft.y;
  const pts: Point[] = [location.topRight, location.bottomLeft, location.alignmentPattern];
  for (const p of pts) {
    if (p.x < minX) {
      minX = p.x;
    }
    if (p.y < minY) {
      minY = p.y;
    }
    if (p.x > maxX) {
      maxX = p.x;
    }
    if (p.y > maxY) {
      maxY = p.y;
    }
  }
  return { x: minX, y: minY, w: maxX - minX, h: maxY - minY };
}

interface NumericResult {
  bytes: number[];
  text: string;
}

enum Mode {
  Numeric = "numeric",
  Alphanumeric = "alphanumeric",
  Byte = "byte",
  Kanji = "kanji",
  ECI = "eci",
}

enum ModeByte {
  Terminator = 0x0,
  Numeric = 0x1,
  Alphanumeric = 0x2,
  Byte = 0x4,
  Kanji = 0x8,
  ECI = 0x7,
}

class Chunk {
  type: Mode = Mode.Numeric;
  text: string = "";
  bytes: number[] = [];
  assignmentNumber: number = 0;
}

class BitMatrix {
  public static createEmpty(width: number, height: number): BitMatrix {
    return new BitMatrix(new Uint8ClampedArray(width * height), width);
  }

  public width: number;
  public height: number;
  public data: Uint8ClampedArray;

  constructor(data: Uint8ClampedArray, width: number) {
    this.width = width;
    this.height = data.length / width;
    this.data = data;
  }

  public get(x: number, y: number): boolean {
    if (x < 0 || x >= this.width || y < 0 || y >= this.height) {
      return false;
    }
    return this.data[y * this.width + x] === 1;
  }

  public set(x: number, y: number, v: boolean): void {
    this.data[y * this.width + x] = v ? 1 : 0;
  }

  public setRegion(left: number, top: number, width: number, height: number, v: boolean): void {
    for (let y = top; y < top + height; y++) {
      for (let x = left; x < left + width; x++) {
        this.set(x, y, v);
      }
    }
  }
}

class Matrix {
  private data: Uint8ClampedArray;
  private width: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.data = new Uint8ClampedArray(width * height);
  }

  public get(x: number, y: number): number {
    return this.data[y * this.width + x];
  }

  public set(x: number, y: number, value: number): void {
    this.data[y * this.width + x] = value;
  }
}

class BitStream {
  private bytes: Uint8ClampedArray;
  private byteOffset: number = 0;
  private bitOffset: number = 0;

  constructor(bytes: Uint8ClampedArray) {
    this.bytes = bytes;
  }

  public readBits(numBits: number): number {
    if (numBits < 1 || numBits > 32 || numBits > this.available()) {
      throw new Error("Cannot read " + numBits.toString() + " bits");
    }

    let result = 0;
    if (this.bitOffset > 0) {
      const bitsLeft = 8 - this.bitOffset;
      const toRead = numBits < bitsLeft ? numBits : bitsLeft;
      const bitsToNotRead = bitsLeft - toRead;
      const mask = (0xFF >> (8 - toRead)) << bitsToNotRead;
      result = (this.bytes[this.byteOffset] & mask) >> bitsToNotRead;
      numBits -= toRead;
      this.bitOffset += toRead;
      if (this.bitOffset === 8) {
        this.bitOffset = 0;
        this.byteOffset++;
      }
    }

    if (numBits > 0) {
      while (numBits >= 8) {
        result = (result << 8) | (this.bytes[this.byteOffset] & 0xFF);
        this.byteOffset++;
        numBits -= 8;
      }

      if (numBits > 0) {
        const bitsToNotRead = 8 - numBits;
        const mask = (0xFF >> bitsToNotRead) << bitsToNotRead;
        result = (result << numBits) | ((this.bytes[this.byteOffset] & mask) >> bitsToNotRead);
        this.bitOffset += numBits;
      }
    }
    return result;
  }

  public available(): number {
    return 8 * (this.bytes.length - this.byteOffset) - this.bitOffset;
  }
}

function addOrSubtractGF(a: number, b: number): number {
  return a ^ b;
}

class GenericGF {
  public primitive: number;
  public size: number;
  public generatorBase: number;
  public zero: GenericGFPoly;
  public one: GenericGFPoly;
  private expTable: number[];
  private logTable: number[];

  constructor(primitive: number, size: number, genBase: number) {
    this.primitive = primitive;
    this.size = size;
    this.generatorBase = genBase;
    this.expTable = new Array<number>(size);
    this.logTable = new Array<number>(size);

    let x = 1;
    for (let i = 0; i < size; i++) {
      this.expTable[i] = x;
      x = x * 2;
      if (x >= size) {
        x = (x ^ primitive) & (size - 1);
      }
    }

    for (let i = 0; i < size - 1; i++) {
      const e = this.expTable[i];
      if (e !== undefined) {
        this.logTable[e] = i;
      }
    }
    this.zero = new GenericGFPoly(this, Uint8ClampedArray.from([0]));
    this.one = new GenericGFPoly(this, Uint8ClampedArray.from([1]));
  }

  public multiply(a: number, b: number): number {
    if (a === 0 || b === 0) {
      return 0;
    }
    const la = this.logTable[a];
    const lb = this.logTable[b];
    const idx = ((la === undefined ? 0 : la) + (lb === undefined ? 0 : lb)) % (this.size - 1);
    const result = this.expTable[idx];
    return result === undefined ? 0 : result;
  }

  public inverse(a: number): number {
    if (a === 0) {
      throw new Error("Can't invert 0");
    }
    const la = this.logTable[a];
    const result = this.expTable[this.size - (la === undefined ? 0 : la) - 1];
    return result === undefined ? 0 : result;
  }

  public buildMonomial(degree: number, coefficient: number): GenericGFPoly {
    if (degree < 0) {
      throw new Error("Invalid monomial degree less than 0");
    }
    if (coefficient === 0) {
      return this.zero;
    }
    const coefficients = new Uint8ClampedArray(degree + 1);
    coefficients[0] = coefficient;
    return new GenericGFPoly(this, coefficients);
  }

  public log(a: number): number {
    if (a === 0) {
      throw new Error("Can't take log(0)");
    }
    const result = this.logTable[a];
    return result === undefined ? 0 : result;
  }

  public exp(a: number): number {
    const result = this.expTable[a];
    return result === undefined ? 0 : result;
  }
}

class GenericGFPoly {
  private field: GenericGF;
  private coefficients: Uint8ClampedArray;

  constructor(field: GenericGF, coefficients: Uint8ClampedArray) {
    if (coefficients.length === 0) {
      throw new Error("No coefficients.");
    }
    this.field = field;
    const coefficientsLength = coefficients.length;
    if (coefficientsLength > 1 && coefficients[0] === 0) {
      let firstNonZero = 1;
      while (firstNonZero < coefficientsLength && coefficients[firstNonZero] === 0) {
        firstNonZero++;
      }
      if (firstNonZero === coefficientsLength) {
        this.coefficients = field.zero.coefficients;
      } else {
        const trimmed = new Uint8ClampedArray(coefficientsLength - firstNonZero);
        for (let i = 0; i < trimmed.length; i++) {
          trimmed[i] = coefficients[firstNonZero + i];
        }
        this.coefficients = trimmed;
      }
    } else {
      this.coefficients = coefficients;
    }
  }

  public degree(): number {
    return this.coefficients.length - 1;
  }

  public isZero(): boolean {
    return this.coefficients[0] === 0;
  }

  public getCoefficient(degree: number): number {
    return this.coefficients[this.coefficients.length - 1 - degree];
  }

  public addOrSubtract(other: GenericGFPoly): GenericGFPoly {
    if (this.isZero()) {
      return other;
    }
    if (other.isZero()) {
      return this;
    }

    let smallerCoefficients = this.coefficients;
    let largerCoefficients = other.coefficients;
    if (smallerCoefficients.length > largerCoefficients.length) {
      const tmp = smallerCoefficients;
      smallerCoefficients = largerCoefficients;
      largerCoefficients = tmp;
    }
    const sumDiff = new Uint8ClampedArray(largerCoefficients.length);
    const lengthDiff = largerCoefficients.length - smallerCoefficients.length;
    for (let i = 0; i < lengthDiff; i++) {
      sumDiff[i] = largerCoefficients[i];
    }

    for (let i = lengthDiff; i < largerCoefficients.length; i++) {
      sumDiff[i] = addOrSubtractGF(smallerCoefficients[i - lengthDiff], largerCoefficients[i]);
    }

    return new GenericGFPoly(this.field, sumDiff);
  }

  public multiply(scalar: number): GenericGFPoly {
    if (scalar === 0) {
      return this.field.zero;
    }
    if (scalar === 1) {
      return this;
    }
    const size = this.coefficients.length;
    const product = new Uint8ClampedArray(size);
    for (let i = 0; i < size; i++) {
      product[i] = this.field.multiply(this.coefficients[i], scalar);
    }
    return new GenericGFPoly(this.field, product);
  }

  public multiplyPoly(other: GenericGFPoly): GenericGFPoly {
    if (this.isZero() || other.isZero()) {
      return this.field.zero;
    }
    const aCoefficients = this.coefficients;
    const aLength = aCoefficients.length;
    const bCoefficients = other.coefficients;
    const bLength = bCoefficients.length;
    const product = new Uint8ClampedArray(aLength + bLength - 1);
    for (let i = 0; i < aLength; i++) {
      const aCoeff = aCoefficients[i];
      for (let j = 0; j < bLength; j++) {
        product[i + j] = addOrSubtractGF(product[i + j],
          this.field.multiply(aCoeff, bCoefficients[j]));
      }
    }
    return new GenericGFPoly(this.field, product);
  }

  public multiplyByMonomial(degree: number, coefficient: number): GenericGFPoly {
    if (degree < 0) {
      throw new Error("Invalid degree less than 0");
    }
    if (coefficient === 0) {
      return this.field.zero;
    }
    const size = this.coefficients.length;
    const product = new Uint8ClampedArray(size + degree);
    for (let i = 0; i < size; i++) {
      product[i] = this.field.multiply(this.coefficients[i], coefficient);
    }
    return new GenericGFPoly(this.field, product);
  }

  public evaluateAt(a: number): number {
    let result = 0;
    if (a === 0) {
      return this.getCoefficient(0);
    }
    const size = this.coefficients.length;
    if (a === 1) {
      for (let i = 0; i < size; i++) {
        result = addOrSubtractGF(result, this.coefficients[i]);
      }
      return result;
    }
    result = this.coefficients[0];
    for (let i = 1; i < size; i++) {
      result = addOrSubtractGF(this.field.multiply(a, result), this.coefficients[i]);
    }
    return result;
  }
}

const AlphanumericCharacterCodes: string[] = [
  "0", "1", "2", "3", "4", "5", "6", "7", "8",
  "9", "A", "B", "C", "D", "E", "F", "G", "H",
  "I", "J", "K", "L", "M", "N", "O", "P", "Q",
  "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
  " ", "$", "%", "*", "+", "-", ".", "/", ":",
];

const FORMAT_INFO_TABLE: FormatInfoEntry[] = [
  { bits: 0x5412, formatInfo: { errorCorrectionLevel: 1, dataMask: 0 } },
  { bits: 0x5125, formatInfo: { errorCorrectionLevel: 1, dataMask: 1 } },
  { bits: 0x5E7C, formatInfo: { errorCorrectionLevel: 1, dataMask: 2 } },
  { bits: 0x5B4B, formatInfo: { errorCorrectionLevel: 1, dataMask: 3 } },
  { bits: 0x45F9, formatInfo: { errorCorrectionLevel: 1, dataMask: 4 } },
  { bits: 0x40CE, formatInfo: { errorCorrectionLevel: 1, dataMask: 5 } },
  { bits: 0x4F97, formatInfo: { errorCorrectionLevel: 1, dataMask: 6 } },
  { bits: 0x4AA0, formatInfo: { errorCorrectionLevel: 1, dataMask: 7 } },
  { bits: 0x77C4, formatInfo: { errorCorrectionLevel: 0, dataMask: 0 } },
  { bits: 0x72F3, formatInfo: { errorCorrectionLevel: 0, dataMask: 1 } },
  { bits: 0x7DAA, formatInfo: { errorCorrectionLevel: 0, dataMask: 2 } },
  { bits: 0x789D, formatInfo: { errorCorrectionLevel: 0, dataMask: 3 } },
  { bits: 0x662F, formatInfo: { errorCorrectionLevel: 0, dataMask: 4 } },
  { bits: 0x6318, formatInfo: { errorCorrectionLevel: 0, dataMask: 5 } },
  { bits: 0x6C41, formatInfo: { errorCorrectionLevel: 0, dataMask: 6 } },
  { bits: 0x6976, formatInfo: { errorCorrectionLevel: 0, dataMask: 7 } },
  { bits: 0x1689, formatInfo: { errorCorrectionLevel: 3, dataMask: 0 } },
  { bits: 0x13BE, formatInfo: { errorCorrectionLevel: 3, dataMask: 1 } },
  { bits: 0x1CE7, formatInfo: { errorCorrectionLevel: 3, dataMask: 2 } },
  { bits: 0x19D0, formatInfo: { errorCorrectionLevel: 3, dataMask: 3 } },
  { bits: 0x0762, formatInfo: { errorCorrectionLevel: 3, dataMask: 4 } },
  { bits: 0x0255, formatInfo: { errorCorrectionLevel: 3, dataMask: 5 } },
  { bits: 0x0D0C, formatInfo: { errorCorrectionLevel: 3, dataMask: 6 } },
  { bits: 0x083B, formatInfo: { errorCorrectionLevel: 3, dataMask: 7 } },
  { bits: 0x355F, formatInfo: { errorCorrectionLevel: 2, dataMask: 0 } },
  { bits: 0x3068, formatInfo: { errorCorrectionLevel: 2, dataMask: 1 } },
  { bits: 0x3F31, formatInfo: { errorCorrectionLevel: 2, dataMask: 2 } },
  { bits: 0x3A06, formatInfo: { errorCorrectionLevel: 2, dataMask: 3 } },
  { bits: 0x24B4, formatInfo: { errorCorrectionLevel: 2, dataMask: 4 } },
  { bits: 0x2183, formatInfo: { errorCorrectionLevel: 2, dataMask: 5 } },
  { bits: 0x2EDA, formatInfo: { errorCorrectionLevel: 2, dataMask: 6 } },
  { bits: 0x2BED, formatInfo: { errorCorrectionLevel: 2, dataMask: 7 } },
];

const DATA_MASKS: ((p: Point) => boolean)[] = [
  (p: Point): boolean => ((p.y + p.x) % 2) === 0,
  (p: Point): boolean => (p.y % 2) === 0,
  (p: Point): boolean => p.x % 3 === 0,
  (p: Point): boolean => (p.y + p.x) % 3 === 0,
  (p: Point): boolean => (Math.floor(p.y / 2) + Math.floor(p.x / 3)) % 2 === 0,
  (p: Point): boolean => ((p.x * p.y) % 2) + ((p.x * p.y) % 3) === 0,
  (p: Point): boolean => ((((p.y * p.x) % 2) + (p.y * p.x) % 3) % 2) === 0,
  (p: Point): boolean => ((((p.y + p.x) % 2) + (p.y * p.x) % 3) % 2) === 0,
];

const VERSIONS: VersionInfo[] = [
  {
    infoBits: 0,
    versionNumber: 1,
    alignmentPatternCenters: [],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 7, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 19 }] },
      { ecCodewordsPerBlock: 10, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 16 }] },
      { ecCodewordsPerBlock: 13, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 13 }] },
      { ecCodewordsPerBlock: 17, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 9 }] },
    ],
  },
  {
    infoBits: 0,
    versionNumber: 2,
    alignmentPatternCenters: [6, 18],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 10, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 34 }] },
      { ecCodewordsPerBlock: 16, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 28 }] },
      { ecCodewordsPerBlock: 22, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 22 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0,
    versionNumber: 3,
    alignmentPatternCenters: [6, 22],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 15, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 55 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 44 }] },
      { ecCodewordsPerBlock: 18, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 17 }] },
      { ecCodewordsPerBlock: 22, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 13 }] },
    ],
  },
  {
    infoBits: 0,
    versionNumber: 4,
    alignmentPatternCenters: [6, 26],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 20, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 80 }] },
      { ecCodewordsPerBlock: 18, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 32 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 24 }] },
      { ecCodewordsPerBlock: 16, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 9 }] },
    ],
  },
  {
    infoBits: 0,
    versionNumber: 5,
    alignmentPatternCenters: [6, 30],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 108 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 43 }] },
      { ecCodewordsPerBlock: 18, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 15 }, { numBlocks: 2, dataCodewordsPerBlock: 16 }] },
      { ecCodewordsPerBlock: 22, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 11 }, { numBlocks: 2, dataCodewordsPerBlock: 12 }] },
    ],
  },
  {
    infoBits: 0,
    versionNumber: 6,
    alignmentPatternCenters: [6, 34],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 18, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 68 }] },
      { ecCodewordsPerBlock: 16, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 27 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 19 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 15 }] },
    ],
  },
  {
    infoBits: 0x07C94,
    versionNumber: 7,
    alignmentPatternCenters: [6, 22, 38],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 20, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 78 }] },
      { ecCodewordsPerBlock: 18, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 31 }] },
      { ecCodewordsPerBlock: 18, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 14 }, { numBlocks: 4, dataCodewordsPerBlock: 15 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 13 }, { numBlocks: 1, dataCodewordsPerBlock: 14 }] },
    ],
  },
  {
    infoBits: 0x085BC,
    versionNumber: 8,
    alignmentPatternCenters: [6, 24, 42],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 97 }] },
      { ecCodewordsPerBlock: 22, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 38 }, { numBlocks: 2, dataCodewordsPerBlock: 39 }] },
      { ecCodewordsPerBlock: 22, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 18 }, { numBlocks: 2, dataCodewordsPerBlock: 19 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 14 }, { numBlocks: 2, dataCodewordsPerBlock: 15 }] },
    ],
  },
  {
    infoBits: 0x09A99,
    versionNumber: 9,
    alignmentPatternCenters: [6, 26, 46],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 116 }] },
      { ecCodewordsPerBlock: 22, ecBlocks: [{ numBlocks: 3, dataCodewordsPerBlock: 36 }, { numBlocks: 2, dataCodewordsPerBlock: 37 }] },
      { ecCodewordsPerBlock: 20, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 16 }, { numBlocks: 4, dataCodewordsPerBlock: 17 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 12 }, { numBlocks: 4, dataCodewordsPerBlock: 13 }] },
    ],
  },
  {
    infoBits: 0x0A4D3,
    versionNumber: 10,
    alignmentPatternCenters: [6, 28, 50],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 18, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 68 }, { numBlocks: 2, dataCodewordsPerBlock: 69 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 43 }, { numBlocks: 1, dataCodewordsPerBlock: 44 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 6, dataCodewordsPerBlock: 19 }, { numBlocks: 2, dataCodewordsPerBlock: 20 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 6, dataCodewordsPerBlock: 15 }, { numBlocks: 2, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x0BBF6,
    versionNumber: 11,
    alignmentPatternCenters: [6, 30, 54],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 20, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 81 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 50 }, { numBlocks: 4, dataCodewordsPerBlock: 51 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 22 }, { numBlocks: 4, dataCodewordsPerBlock: 23 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 3, dataCodewordsPerBlock: 12 }, { numBlocks: 8, dataCodewordsPerBlock: 13 }] },
    ],
  },
  {
    infoBits: 0x0C762,
    versionNumber: 12,
    alignmentPatternCenters: [6, 32, 58],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 92 }, { numBlocks: 2, dataCodewordsPerBlock: 93 }] },
      { ecCodewordsPerBlock: 22, ecBlocks: [{ numBlocks: 6, dataCodewordsPerBlock: 36 }, { numBlocks: 2, dataCodewordsPerBlock: 37 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 20 }, { numBlocks: 6, dataCodewordsPerBlock: 21 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 7, dataCodewordsPerBlock: 14 }, { numBlocks: 4, dataCodewordsPerBlock: 15 }] },
    ],
  },
  {
    infoBits: 0x0D847,
    versionNumber: 13,
    alignmentPatternCenters: [6, 34, 62],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 107 }] },
      { ecCodewordsPerBlock: 22, ecBlocks: [{ numBlocks: 8, dataCodewordsPerBlock: 37 }, { numBlocks: 1, dataCodewordsPerBlock: 38 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 8, dataCodewordsPerBlock: 20 }, { numBlocks: 4, dataCodewordsPerBlock: 21 }] },
      { ecCodewordsPerBlock: 22, ecBlocks: [{ numBlocks: 12, dataCodewordsPerBlock: 11 }, { numBlocks: 4, dataCodewordsPerBlock: 12 }] },
    ],
  },
  {
    infoBits: 0x0E60D,
    versionNumber: 14,
    alignmentPatternCenters: [6, 26, 46, 66],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 3, dataCodewordsPerBlock: 115 }, { numBlocks: 1, dataCodewordsPerBlock: 116 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 40 }, { numBlocks: 5, dataCodewordsPerBlock: 41 }] },
      { ecCodewordsPerBlock: 20, ecBlocks: [{ numBlocks: 11, dataCodewordsPerBlock: 16 }, { numBlocks: 5, dataCodewordsPerBlock: 17 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 11, dataCodewordsPerBlock: 12 }, { numBlocks: 5, dataCodewordsPerBlock: 13 }] },
    ],
  },
  {
    infoBits: 0x0F928,
    versionNumber: 15,
    alignmentPatternCenters: [6, 26, 48, 70],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 22, ecBlocks: [{ numBlocks: 5, dataCodewordsPerBlock: 87 }, { numBlocks: 1, dataCodewordsPerBlock: 88 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 5, dataCodewordsPerBlock: 41 }, { numBlocks: 5, dataCodewordsPerBlock: 42 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 5, dataCodewordsPerBlock: 24 }, { numBlocks: 7, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 11, dataCodewordsPerBlock: 12 }, { numBlocks: 7, dataCodewordsPerBlock: 13 }] },
    ],
  },
  {
    infoBits: 0x10B78,
    versionNumber: 16,
    alignmentPatternCenters: [6, 26, 50, 74],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 5, dataCodewordsPerBlock: 98 }, { numBlocks: 1, dataCodewordsPerBlock: 99 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 7, dataCodewordsPerBlock: 45 }, { numBlocks: 3, dataCodewordsPerBlock: 46 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 15, dataCodewordsPerBlock: 19 }, { numBlocks: 2, dataCodewordsPerBlock: 20 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 3, dataCodewordsPerBlock: 15 }, { numBlocks: 13, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x1145D,
    versionNumber: 17,
    alignmentPatternCenters: [6, 30, 54, 78],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 107 }, { numBlocks: 5, dataCodewordsPerBlock: 108 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 10, dataCodewordsPerBlock: 46 }, { numBlocks: 1, dataCodewordsPerBlock: 47 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 22 }, { numBlocks: 15, dataCodewordsPerBlock: 23 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 14 }, { numBlocks: 17, dataCodewordsPerBlock: 15 }] },
    ],
  },
  {
    infoBits: 0x12A17,
    versionNumber: 18,
    alignmentPatternCenters: [6, 30, 56, 82],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 5, dataCodewordsPerBlock: 120 }, { numBlocks: 1, dataCodewordsPerBlock: 121 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 9, dataCodewordsPerBlock: 43 }, { numBlocks: 4, dataCodewordsPerBlock: 44 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 17, dataCodewordsPerBlock: 22 }, { numBlocks: 1, dataCodewordsPerBlock: 23 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 14 }, { numBlocks: 19, dataCodewordsPerBlock: 15 }] },
    ],
  },
  {
    infoBits: 0x13532,
    versionNumber: 19,
    alignmentPatternCenters: [6, 30, 58, 86],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 3, dataCodewordsPerBlock: 113 }, { numBlocks: 4, dataCodewordsPerBlock: 114 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 3, dataCodewordsPerBlock: 44 }, { numBlocks: 11, dataCodewordsPerBlock: 45 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 17, dataCodewordsPerBlock: 21 }, { numBlocks: 4, dataCodewordsPerBlock: 22 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 9, dataCodewordsPerBlock: 13 }, { numBlocks: 16, dataCodewordsPerBlock: 14 }] },
    ],
  },
  {
    infoBits: 0x149A6,
    versionNumber: 20,
    alignmentPatternCenters: [6, 34, 62, 90],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 3, dataCodewordsPerBlock: 107 }, { numBlocks: 5, dataCodewordsPerBlock: 108 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 3, dataCodewordsPerBlock: 41 }, { numBlocks: 13, dataCodewordsPerBlock: 42 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 15, dataCodewordsPerBlock: 24 }, { numBlocks: 5, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 15, dataCodewordsPerBlock: 15 }, { numBlocks: 10, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x15683,
    versionNumber: 21,
    alignmentPatternCenters: [6, 28, 50, 72, 94],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 116 }, { numBlocks: 4, dataCodewordsPerBlock: 117 }] },
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 17, dataCodewordsPerBlock: 42 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 17, dataCodewordsPerBlock: 22 }, { numBlocks: 6, dataCodewordsPerBlock: 23 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 19, dataCodewordsPerBlock: 16 }, { numBlocks: 6, dataCodewordsPerBlock: 17 }] },
    ],
  },
  {
    infoBits: 0x168C9,
    versionNumber: 22,
    alignmentPatternCenters: [6, 26, 50, 74, 98],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 111 }, { numBlocks: 7, dataCodewordsPerBlock: 112 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 17, dataCodewordsPerBlock: 46 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 7, dataCodewordsPerBlock: 24 }, { numBlocks: 16, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 24, ecBlocks: [{ numBlocks: 34, dataCodewordsPerBlock: 13 }] },
    ],
  },
  {
    infoBits: 0x177EC,
    versionNumber: 23,
    alignmentPatternCenters: [6, 30, 54, 74, 102],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 121 }, { numBlocks: 5, dataCodewordsPerBlock: 122 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 47 }, { numBlocks: 14, dataCodewordsPerBlock: 48 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 11, dataCodewordsPerBlock: 24 }, { numBlocks: 14, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 16, dataCodewordsPerBlock: 15 }, { numBlocks: 14, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x18EC4,
    versionNumber: 24,
    alignmentPatternCenters: [6, 28, 54, 80, 106],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 6, dataCodewordsPerBlock: 117 }, { numBlocks: 4, dataCodewordsPerBlock: 118 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 6, dataCodewordsPerBlock: 45 }, { numBlocks: 14, dataCodewordsPerBlock: 46 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 11, dataCodewordsPerBlock: 24 }, { numBlocks: 16, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 30, dataCodewordsPerBlock: 16 }, { numBlocks: 2, dataCodewordsPerBlock: 17 }] },
    ],
  },
  {
    infoBits: 0x191E1,
    versionNumber: 25,
    alignmentPatternCenters: [6, 32, 58, 84, 110],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 26, ecBlocks: [{ numBlocks: 8, dataCodewordsPerBlock: 106 }, { numBlocks: 4, dataCodewordsPerBlock: 107 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 8, dataCodewordsPerBlock: 47 }, { numBlocks: 13, dataCodewordsPerBlock: 48 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 7, dataCodewordsPerBlock: 24 }, { numBlocks: 22, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 22, dataCodewordsPerBlock: 15 }, { numBlocks: 13, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x1AFAB,
    versionNumber: 26,
    alignmentPatternCenters: [6, 30, 58, 86, 114],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 10, dataCodewordsPerBlock: 114 }, { numBlocks: 2, dataCodewordsPerBlock: 115 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 19, dataCodewordsPerBlock: 46 }, { numBlocks: 4, dataCodewordsPerBlock: 47 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 28, dataCodewordsPerBlock: 22 }, { numBlocks: 6, dataCodewordsPerBlock: 23 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 33, dataCodewordsPerBlock: 16 }, { numBlocks: 4, dataCodewordsPerBlock: 17 }] },
    ],
  },
  {
    infoBits: 0x1B08E,
    versionNumber: 27,
    alignmentPatternCenters: [6, 34, 62, 90, 118],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 8, dataCodewordsPerBlock: 122 }, { numBlocks: 4, dataCodewordsPerBlock: 123 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 22, dataCodewordsPerBlock: 45 }, { numBlocks: 3, dataCodewordsPerBlock: 46 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 8, dataCodewordsPerBlock: 23 }, { numBlocks: 26, dataCodewordsPerBlock: 24 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 12, dataCodewordsPerBlock: 15 }, { numBlocks: 28, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x1CC1A,
    versionNumber: 28,
    alignmentPatternCenters: [6, 26, 50, 74, 98, 122],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 3, dataCodewordsPerBlock: 117 }, { numBlocks: 10, dataCodewordsPerBlock: 118 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 3, dataCodewordsPerBlock: 45 }, { numBlocks: 23, dataCodewordsPerBlock: 46 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 24 }, { numBlocks: 31, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 11, dataCodewordsPerBlock: 15 }, { numBlocks: 31, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x1D33F,
    versionNumber: 29,
    alignmentPatternCenters: [6, 30, 54, 78, 102, 126],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 7, dataCodewordsPerBlock: 116 }, { numBlocks: 7, dataCodewordsPerBlock: 117 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 21, dataCodewordsPerBlock: 45 }, { numBlocks: 7, dataCodewordsPerBlock: 46 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 1, dataCodewordsPerBlock: 23 }, { numBlocks: 37, dataCodewordsPerBlock: 24 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 19, dataCodewordsPerBlock: 15 }, { numBlocks: 26, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x1ED75,
    versionNumber: 30,
    alignmentPatternCenters: [6, 26, 52, 78, 104, 130],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 5, dataCodewordsPerBlock: 115 }, { numBlocks: 10, dataCodewordsPerBlock: 116 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 19, dataCodewordsPerBlock: 47 }, { numBlocks: 10, dataCodewordsPerBlock: 48 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 15, dataCodewordsPerBlock: 24 }, { numBlocks: 25, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 23, dataCodewordsPerBlock: 15 }, { numBlocks: 25, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x1F250,
    versionNumber: 31,
    alignmentPatternCenters: [6, 30, 56, 82, 108, 134],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 13, dataCodewordsPerBlock: 115 }, { numBlocks: 3, dataCodewordsPerBlock: 116 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 46 }, { numBlocks: 29, dataCodewordsPerBlock: 47 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 42, dataCodewordsPerBlock: 24 }, { numBlocks: 1, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 23, dataCodewordsPerBlock: 15 }, { numBlocks: 28, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x209D5,
    versionNumber: 32,
    alignmentPatternCenters: [6, 34, 60, 86, 112, 138],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 17, dataCodewordsPerBlock: 115 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 10, dataCodewordsPerBlock: 46 }, { numBlocks: 23, dataCodewordsPerBlock: 47 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 10, dataCodewordsPerBlock: 24 }, { numBlocks: 35, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 19, dataCodewordsPerBlock: 15 }, { numBlocks: 35, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x216F0,
    versionNumber: 33,
    alignmentPatternCenters: [6, 30, 58, 86, 114, 142],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 17, dataCodewordsPerBlock: 115 }, { numBlocks: 1, dataCodewordsPerBlock: 116 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 14, dataCodewordsPerBlock: 46 }, { numBlocks: 21, dataCodewordsPerBlock: 47 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 29, dataCodewordsPerBlock: 24 }, { numBlocks: 19, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 11, dataCodewordsPerBlock: 15 }, { numBlocks: 46, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x228BA,
    versionNumber: 34,
    alignmentPatternCenters: [6, 34, 62, 90, 118, 146],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 13, dataCodewordsPerBlock: 115 }, { numBlocks: 6, dataCodewordsPerBlock: 116 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 14, dataCodewordsPerBlock: 46 }, { numBlocks: 23, dataCodewordsPerBlock: 47 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 44, dataCodewordsPerBlock: 24 }, { numBlocks: 7, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 59, dataCodewordsPerBlock: 16 }, { numBlocks: 1, dataCodewordsPerBlock: 17 }] },
    ],
  },
  {
    infoBits: 0x2379F,
    versionNumber: 35,
    alignmentPatternCenters: [6, 30, 54, 78, 102, 126, 150],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 12, dataCodewordsPerBlock: 121 }, { numBlocks: 7, dataCodewordsPerBlock: 122 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 12, dataCodewordsPerBlock: 47 }, { numBlocks: 26, dataCodewordsPerBlock: 48 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 39, dataCodewordsPerBlock: 24 }, { numBlocks: 14, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 22, dataCodewordsPerBlock: 15 }, { numBlocks: 41, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x24B0B,
    versionNumber: 36,
    alignmentPatternCenters: [6, 24, 50, 76, 102, 128, 154],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 6, dataCodewordsPerBlock: 121 }, { numBlocks: 14, dataCodewordsPerBlock: 122 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 6, dataCodewordsPerBlock: 47 }, { numBlocks: 34, dataCodewordsPerBlock: 48 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 46, dataCodewordsPerBlock: 24 }, { numBlocks: 10, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 2, dataCodewordsPerBlock: 15 }, { numBlocks: 64, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x2542E,
    versionNumber: 37,
    alignmentPatternCenters: [6, 28, 54, 80, 106, 132, 158],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 17, dataCodewordsPerBlock: 122 }, { numBlocks: 4, dataCodewordsPerBlock: 123 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 29, dataCodewordsPerBlock: 46 }, { numBlocks: 14, dataCodewordsPerBlock: 47 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 49, dataCodewordsPerBlock: 24 }, { numBlocks: 10, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 24, dataCodewordsPerBlock: 15 }, { numBlocks: 46, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x26A64,
    versionNumber: 38,
    alignmentPatternCenters: [6, 32, 58, 84, 110, 136, 162],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 4, dataCodewordsPerBlock: 122 }, { numBlocks: 18, dataCodewordsPerBlock: 123 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 13, dataCodewordsPerBlock: 46 }, { numBlocks: 32, dataCodewordsPerBlock: 47 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 48, dataCodewordsPerBlock: 24 }, { numBlocks: 14, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 42, dataCodewordsPerBlock: 15 }, { numBlocks: 32, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x27541,
    versionNumber: 39,
    alignmentPatternCenters: [6, 26, 54, 82, 110, 138, 166],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 20, dataCodewordsPerBlock: 117 }, { numBlocks: 4, dataCodewordsPerBlock: 118 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 40, dataCodewordsPerBlock: 47 }, { numBlocks: 7, dataCodewordsPerBlock: 48 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 43, dataCodewordsPerBlock: 24 }, { numBlocks: 22, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 10, dataCodewordsPerBlock: 15 }, { numBlocks: 67, dataCodewordsPerBlock: 16 }] },
    ],
  },
  {
    infoBits: 0x28C69,
    versionNumber: 40,
    alignmentPatternCenters: [6, 30, 58, 86, 114, 142, 170],
    errorCorrectionLevels: [
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 19, dataCodewordsPerBlock: 118 }, { numBlocks: 6, dataCodewordsPerBlock: 119 }] },
      { ecCodewordsPerBlock: 28, ecBlocks: [{ numBlocks: 18, dataCodewordsPerBlock: 47 }, { numBlocks: 31, dataCodewordsPerBlock: 48 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 34, dataCodewordsPerBlock: 24 }, { numBlocks: 34, dataCodewordsPerBlock: 25 }] },
      { ecCodewordsPerBlock: 30, ecBlocks: [{ numBlocks: 20, dataCodewordsPerBlock: 15 }, { numBlocks: 61, dataCodewordsPerBlock: 16 }] },
    ],
  },
];

const REGION_SIZE = 8;
const MIN_DYNAMIC_RANGE = 24;

const MAX_FINDERPATTERNS_TO_SEARCH = 4;
const MIN_QUAD_RATIO = 0.5;
const MAX_QUAD_RATIO = 1.5;

function numBetween(value: number, min: number, max: number): number {
  return value < min ? min : value > max ? max : value;
}

function binarize(data: Uint8ClampedArray, width: number, height: number): BitMatrix {
  if (data.length !== width * height * 4) {
    throw new Error("Malformed data passed to binarizer.");
  }
  const n: number = width * height;
  const grey: Uint8Array = new Uint8Array(n);
  for (let i = 0; i < n; i++) {
    const o: number = i * 4;
    const r: number = data[o];
    const g: number = data[o + 1];
    const b: number = data[o + 2];
    grey[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
  const horizontalRegionCount: number = Math.ceil(width / REGION_SIZE);
  const verticalRegionCount: number = Math.ceil(height / REGION_SIZE);
  const regionCount: number = horizontalRegionCount * verticalRegionCount;

  const blackPoints: Uint8Array = new Uint8Array(regionCount);
  for (let verticalRegion = 0; verticalRegion < verticalRegionCount; verticalRegion++) {
    for (let hortizontalRegion = 0; hortizontalRegion < horizontalRegionCount; hortizontalRegion++) {
      let sum = 0;
      let min = 1000000;
      let max = -1;
      for (let y = 0; y < REGION_SIZE; y++) {
        const row: number = (verticalRegion * REGION_SIZE + y) * width + hortizontalRegion * REGION_SIZE;
        for (let x = 0; x < REGION_SIZE; x++) {
          const pixelLumosity: number = grey[row + x];
          sum += pixelLumosity;
          if (pixelLumosity < min) {
            min = pixelLumosity;
          }
          if (pixelLumosity > max) {
            max = pixelLumosity;
          }
        }
      }

      let average: number = sum / (REGION_SIZE * REGION_SIZE);
      if (max - min <= MIN_DYNAMIC_RANGE) {
        average = min / 2;

        if (verticalRegion > 0 && hortizontalRegion > 0) {
          const averageNeighborBlackPoint: number = (
            blackPoints[hortizontalRegion + (verticalRegion - 1) * horizontalRegionCount] +
            (2 * blackPoints[hortizontalRegion - 1 + verticalRegion * horizontalRegionCount]) +
            blackPoints[hortizontalRegion - 1 + (verticalRegion - 1) * horizontalRegionCount]
          ) / 4;
          if (min < averageNeighborBlackPoint) {
            average = averageNeighborBlackPoint;
          }
        }
      }
      blackPoints[hortizontalRegion + verticalRegion * horizontalRegionCount] = average;
    }
  }

  const binarized: BitMatrix = BitMatrix.createEmpty(width, height);
  for (let verticalRegion = 0; verticalRegion < verticalRegionCount; verticalRegion++) {
    for (let hortizontalRegion = 0; hortizontalRegion < horizontalRegionCount; hortizontalRegion++) {
      let left: number = hortizontalRegion < 2 ? 2 : hortizontalRegion;
      if (left > horizontalRegionCount - 3) {
        left = horizontalRegionCount - 3;
      }
      let top: number = verticalRegion < 2 ? 2 : verticalRegion;
      if (top > verticalRegionCount - 3) {
        top = verticalRegionCount - 3;
      }
      let sum = 0;
      for (let xRegion = -2; xRegion <= 2; xRegion++) {
        for (let yRegion = -2; yRegion <= 2; yRegion++) {
          sum += blackPoints[(left + xRegion) + (top + yRegion) * horizontalRegionCount];
        }
      }
      const threshold: number = sum / 25;
      for (let yRegion = 0; yRegion < REGION_SIZE; yRegion++) {
        const y: number = verticalRegion * REGION_SIZE + yRegion;
        const greyRow: number = y * width + hortizontalRegion * REGION_SIZE;
        const outRow: number = y * width;
        for (let xRegion = 0; xRegion < REGION_SIZE; xRegion++) {
          const x: number = hortizontalRegion * REGION_SIZE + xRegion;
          binarized.data[outRow + x] = grey[greyRow + xRegion] <= threshold ? 1 : 0;
        }
      }
    }
  }
  return binarized;
}

function distance(a: Point, b: Point): number {
  return Math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
}

function sum(values: number[]): number {
  let total = 0;
  for (const value of values) {
    total += value;
  }
  return total;
}

function reorderFinderPatterns(pattern1: Point, pattern2: Point, pattern3: Point): FinderPatternOrder {
  const oneTwoDistance = distance(pattern1, pattern2);
  const twoThreeDistance = distance(pattern2, pattern3);
  const oneThreeDistance = distance(pattern1, pattern3);

  let bottomLeft: Point = pattern1;
  let topLeft: Point = pattern2;
  let topRight: Point = pattern3;

  if (twoThreeDistance >= oneTwoDistance && twoThreeDistance >= oneThreeDistance) {
    bottomLeft = pattern2;
    topLeft = pattern1;
    topRight = pattern3;
  } else if (oneThreeDistance >= twoThreeDistance && oneThreeDistance >= oneTwoDistance) {
    bottomLeft = pattern1;
    topLeft = pattern2;
    topRight = pattern3;
  } else {
    bottomLeft = pattern1;
    topLeft = pattern3;
    topRight = pattern2;
  }

  if (((topRight.x - topLeft.x) * (bottomLeft.y - topLeft.y)) - ((topRight.y - topLeft.y) * (bottomLeft.x - topLeft.x)) < 0) {
    const temp = bottomLeft;
    bottomLeft = topRight;
    topRight = temp;
  }

  const result: FinderPatternOrder = { bottomLeft: bottomLeft, topLeft: topLeft, topRight: topRight };
  return result;
}

function computeDimension(topLeft: Point, topRight: Point, bottomLeft: Point, matrix: BitMatrix): DimensionResult {
  const moduleSize = (
    sum(countBlackWhiteRun(topLeft, bottomLeft, matrix, 5)) / 7 +
    sum(countBlackWhiteRun(topLeft, topRight, matrix, 5)) / 7 +
    sum(countBlackWhiteRun(bottomLeft, topLeft, matrix, 5)) / 7 +
    sum(countBlackWhiteRun(topRight, topLeft, matrix, 5)) / 7
  ) / 4;

  if (moduleSize < 1) {
    throw new Error("Invalid module size");
  }

  const topDimension = Math.round(distance(topLeft, topRight) / moduleSize);
  const sideDimension = Math.round(distance(topLeft, bottomLeft) / moduleSize);
  let dimension = Math.floor((topDimension + sideDimension) / 2) + 7;
  switch (dimension % 4) {
    case 0:
      dimension++;
      break;
    case 2:
      dimension--;
      break;
  }
  const result: DimensionResult = { dimension: dimension, moduleSize: moduleSize };
  return result;
}

function countBlackWhiteRunTowardsPoint(origin: Point, end: Point, matrix: BitMatrix, length: number): number[] {
  const distances: number[] = [];
  const steep = Math.abs(end.y - origin.y) > Math.abs(end.x - origin.x);

  let fromX: number;
  let fromY: number;
  let toX: number;
  let toY: number;
  if (steep) {
    fromX = Math.floor(origin.y);
    fromY = Math.floor(origin.x);
    toX = Math.floor(end.y);
    toY = Math.floor(end.x);
  } else {
    fromX = Math.floor(origin.x);
    fromY = Math.floor(origin.y);
    toX = Math.floor(end.x);
    toY = Math.floor(end.y);
  }

  const dx = Math.abs(toX - fromX);
  const dy = Math.abs(toY - fromY);
  let error = Math.floor(-dx / 2);
  const xStep = fromX < toX ? 1 : -1;
  const yStep = fromY < toY ? 1 : -1;

  let currentPixel = true;
  let x = fromX;
  let y = fromY;
  let prevX: number = Math.floor(origin.x);
  let prevY: number = Math.floor(origin.y);
  let switchCount = 1;
  while (x !== toX + xStep) {
    const realX = steep ? y : x;
    const realY = steep ? x : y;
    if (matrix.get(realX, realY) !== currentPixel) {
      currentPixel = !currentPixel;
      const ddx = realX - prevX;
      const ddy = realY - prevY;
      distances.push(Math.sqrt(ddx * ddx + ddy * ddy));
      prevX = realX;
      prevY = realY;
      switchCount++;
      if (switchCount === length + 1) {
        break;
      }
    }
    error += dy;
    if (error > 0) {
      if (y === toY) {
        break;
      }
      y += yStep;
      error -= dx;
    }
    x += xStep;
  }
  while (distances.length < length) {
    distances.push(0);
  }
  return distances;
}

function countBlackWhiteRun(origin: Point, end: Point, matrix: BitMatrix, length: number): number[] {
  const rise = end.y - origin.y;
  const run = end.x - origin.x;

  const towardsEnd = countBlackWhiteRunTowardsPoint(origin, end, matrix, Math.ceil(length / 2));
  const awayEnd: Point = { x: origin.x - run, y: origin.y - rise };
  const awayFromEnd = countBlackWhiteRunTowardsPoint(origin, awayEnd, matrix, Math.ceil(length / 2));

  const te = towardsEnd.shift();
  const ae = awayFromEnd.shift();
  const middleValue = (te === undefined ? 0 : te) + (ae === undefined ? 0 : ae) - 1;

  const result: number[] = [];
  for (const v of awayFromEnd) {
    result.push(v);
  }
  result.push(middleValue);
  for (const v of towardsEnd) {
    result.push(v);
  }
  return result;
}

function scoreBlackWhiteRun(sequence: number[], ratios: number[]): ScoreResult {
  const averageSize = sum(sequence) / sum(ratios);
  let error = 0;
  for (let i = 0; i < ratios.length; i++) {
    const seq = sequence[i];
    const ratio = ratios[i];
    const delta = (seq === undefined ? 0 : seq) - ratio * averageSize;
    error += delta * delta;
  }
  const result: ScoreResult = { averageSize: averageSize, error: error };
  return result;
}

function scorePattern(point: Point, ratios: number[], matrix: BitMatrix): number {
  try {
    const horizontalRun = countBlackWhiteRun(point, { x: -1, y: point.y }, matrix, ratios.length);
    const verticalRun = countBlackWhiteRun(point, { x: point.x, y: -1 }, matrix, ratios.length);

    const topLeftPoint: Point = {
      x: Math.max(0, point.x - point.y) - 1,
      y: Math.max(0, point.y - point.x) - 1,
    };
    const topLeftBottomRightRun = countBlackWhiteRun(point, topLeftPoint, matrix, ratios.length);

    const bottomLeftPoint: Point = {
      x: Math.min(matrix.width, point.x + point.y) + 1,
      y: Math.min(matrix.height, point.y + point.x) + 1,
    };
    const bottomLeftTopRightRun = countBlackWhiteRun(point, bottomLeftPoint, matrix, ratios.length);

    const horzError = scoreBlackWhiteRun(horizontalRun, ratios);
    const vertError = scoreBlackWhiteRun(verticalRun, ratios);
    const diagDownError = scoreBlackWhiteRun(topLeftBottomRightRun, ratios);
    const diagUpError = scoreBlackWhiteRun(bottomLeftTopRightRun, ratios);

    const ratioError = Math.sqrt(horzError.error * horzError.error +
      vertError.error * vertError.error +
      diagDownError.error * diagDownError.error +
      diagUpError.error * diagUpError.error);

    const avgSize = (horzError.averageSize + vertError.averageSize + diagDownError.averageSize + diagUpError.averageSize) / 4;

    const sizeError = ((horzError.averageSize - avgSize) * (horzError.averageSize - avgSize) +
      (vertError.averageSize - avgSize) * (vertError.averageSize - avgSize) +
      (diagDownError.averageSize - avgSize) * (diagDownError.averageSize - avgSize) +
      (diagUpError.averageSize - avgSize) * (diagUpError.averageSize - avgSize)) / avgSize;
    return ratioError + sizeError;
  } catch (e) {
    return Infinity;
  }
}

function recenterLocation(matrix: BitMatrix, p: Point): Point {
  let leftX = Math.round(p.x);
  while (matrix.get(leftX, Math.round(p.y))) {
    leftX--;
  }
  let rightX = Math.round(p.x);
  while (matrix.get(rightX, Math.round(p.y))) {
    rightX++;
  }
  const x = (leftX + rightX) / 2;

  let topY = Math.round(p.y);
  while (matrix.get(Math.round(x), topY)) {
    topY--;
  }
  let bottomY = Math.round(p.y);
  while (matrix.get(Math.round(x), bottomY)) {
    bottomY++;
  }
  const y = (topY + bottomY) / 2;

  const result: Point = { x: x, y: y };
  return result;
}

function findAlignmentPattern(matrix: BitMatrix, alignmentPatternQuads: Quad[], topRight: Point, topLeft: Point, bottomLeft: Point): AlignmentResult | undefined {
  let dimension = 0;
  let moduleSize = 0;
  try {
    const dim = computeDimension(topLeft, topRight, bottomLeft, matrix);
    dimension = dim.dimension;
    moduleSize = dim.moduleSize;
  } catch (e) {
    return undefined;
  }

  const bottomRightFinderPattern: Point = {
    x: topRight.x - topLeft.x + bottomLeft.x,
    y: topRight.y - topLeft.y + bottomLeft.y,
  };
  const modulesBetweenFinderPatterns = (distance(topLeft, bottomLeft) + distance(topLeft, topRight)) / 2 / moduleSize;
  const correctionToTopLeft = 1 - (3 / modulesBetweenFinderPatterns);
  const expectedAlignmentPattern: Point = {
    x: topLeft.x + correctionToTopLeft * (bottomRightFinderPattern.x - topLeft.x),
    y: topLeft.y + correctionToTopLeft * (bottomRightFinderPattern.y - topLeft.y),
  };

  const candidates: AlignmentCandidate[] = [];
  for (const q of alignmentPatternQuads) {
    const x = (q.top.startX + q.top.endX + q.bottom.startX + q.bottom.endX) / 4;
    const y = (q.top.y + q.bottom.y + 1) / 2;
    if (!matrix.get(Math.floor(x), Math.floor(y))) {
      continue;
    }

    const sizeScore = scorePattern({ x: Math.floor(x), y: Math.floor(y) }, [1, 1, 1], matrix);
    const score = sizeScore + distance({ x: x, y: y }, expectedAlignmentPattern);
    const cand: AlignmentCandidate = { x: x, y: y, score: score };
    candidates.push(cand);
  }
  candidates.sort((a: AlignmentCandidate, b: AlignmentCandidate): number => a.score - b.score);

  let alignmentPattern: Point = expectedAlignmentPattern;
  if (modulesBetweenFinderPatterns >= 15 && candidates.length > 0) {
    const best = candidates[0];
    if (best !== undefined) {
      alignmentPattern = { x: best.x, y: best.y };
    }
  }

  const result: AlignmentResult = { alignmentPattern: alignmentPattern, dimension: dimension };
  return result;
}

function locate(matrix: BitMatrix): QRLocation[] | undefined {
  const tScan0: number = Date.now();
  const finderPatternQuads: Quad[] = [];
  let activeFinderPatternQuads: Quad[] = [];
  const alignmentPatternQuads: Quad[] = [];
  let activeAlignmentPatternQuads: Quad[] = [];

  for (let y = 0; y <= matrix.height; y++) {
    let length = 0;
    let lastBit = false;
    const scans: number[] = [0, 0, 0, 0, 0];

    for (let x = -1; x <= matrix.width; x++) {
      const v = matrix.get(x, y);
      if (v === lastBit) {
        length++;
      } else {
        scans[0] = scans[1];
        scans[1] = scans[2];
        scans[2] = scans[3];
        scans[3] = scans[4];
        scans[4] = length;
        length = 1;
        lastBit = v;

        const s0 = scans[0];
        const s1 = scans[1];
        const s2 = scans[2];
        const s3 = scans[3];
        const s4 = scans[4];

        const averageFinderPatternBlocksize = (s0 + s1 + s2 + s3 + s4) / 7;
        const validFinderPattern =
          Math.abs(s0 - averageFinderPatternBlocksize) < averageFinderPatternBlocksize &&
          Math.abs(s1 - averageFinderPatternBlocksize) < averageFinderPatternBlocksize &&
          Math.abs(s2 - 3 * averageFinderPatternBlocksize) < 3 * averageFinderPatternBlocksize &&
          Math.abs(s3 - averageFinderPatternBlocksize) < averageFinderPatternBlocksize &&
          Math.abs(s4 - averageFinderPatternBlocksize) < averageFinderPatternBlocksize &&
          !v;

        const averageAlignmentPatternBlocksize = (s2 + s3 + s4) / 3;
        const validAlignmentPattern =
          Math.abs(s2 - averageAlignmentPatternBlocksize) < averageAlignmentPatternBlocksize &&
          Math.abs(s3 - averageAlignmentPatternBlocksize) < averageAlignmentPatternBlocksize &&
          Math.abs(s4 - averageAlignmentPatternBlocksize) < averageAlignmentPatternBlocksize &&
          v;

        if (validFinderPattern) {
          const endX = x - s3 - s4;
          const startX = endX - s2;

          const line: QuadLine = { startX: startX, endX: endX, y: y };
          let mq: Quad | undefined = undefined;
          for (let ai = 0; ai < activeFinderPatternQuads.length; ai++) {
            const q: Quad = activeFinderPatternQuads[ai];
            if ((startX >= q.bottom.startX && startX <= q.bottom.endX) ||
              (endX >= q.bottom.startX && startX <= q.bottom.endX) ||
              (startX <= q.bottom.startX && endX >= q.bottom.endX && (
                (s2 / (q.bottom.endX - q.bottom.startX)) < MAX_QUAD_RATIO &&
                (s2 / (q.bottom.endX - q.bottom.startX)) > MIN_QUAD_RATIO
              ))) {
              mq = q;
              break;
            }
          }
          if (mq !== undefined) {
            mq.bottom = line;
          } else {
            const quad: Quad = { top: line, bottom: line };
            activeFinderPatternQuads.push(quad);
          }
        }
        if (validAlignmentPattern) {
          const endX = x - s4;
          const startX = endX - s3;

          const line: QuadLine = { startX: startX, y: y, endX: endX };
          let mq2: Quad | undefined = undefined;
          for (let ai = 0; ai < activeAlignmentPatternQuads.length; ai++) {
            const q: Quad = activeAlignmentPatternQuads[ai];
            if ((startX >= q.bottom.startX && startX <= q.bottom.endX) ||
              (endX >= q.bottom.startX && startX <= q.bottom.endX) ||
              (startX <= q.bottom.startX && endX >= q.bottom.endX && (
                (s2 / (q.bottom.endX - q.bottom.startX)) < MAX_QUAD_RATIO &&
                (s2 / (q.bottom.endX - q.bottom.startX)) > MIN_QUAD_RATIO
              ))) {
              mq2 = q;
              break;
            }
          }
          if (mq2 !== undefined) {
            mq2.bottom = line;
          } else {
            const quad: Quad = { top: line, bottom: line };
            activeAlignmentPatternQuads.push(quad);
          }
        }
      }
    }
    const keptF: Quad[] = [];
    for (let ai = 0; ai < activeFinderPatternQuads.length; ai++) {
      const q: Quad = activeFinderPatternQuads[ai];
      if (q.bottom.y !== y && q.bottom.y - q.top.y >= 2) {
        finderPatternQuads.push(q);
      }
      if (q.bottom.y === y) {
        keptF.push(q);
      }
    }
    activeFinderPatternQuads = keptF;

    const keptA: Quad[] = [];
    for (let ai = 0; ai < activeAlignmentPatternQuads.length; ai++) {
      const q: Quad = activeAlignmentPatternQuads[ai];
      if (q.bottom.y !== y) {
        alignmentPatternQuads.push(q);
      }
      if (q.bottom.y === y) {
        keptA.push(q);
      }
    }
    activeAlignmentPatternQuads = keptA;
  }

  for (const q of activeFinderPatternQuads) {
    if (q.bottom.y - q.top.y >= 2) {
      finderPatternQuads.push(q);
    }
  }
  for (const q of activeAlignmentPatternQuads) {
    alignmentPatternQuads.push(q);
  }

  const tScan1: number = Date.now();

  const tallQuads: Quad[] = [];
  for (const q of finderPatternQuads) {
    if (q.bottom.y - q.top.y >= 2) {
      tallQuads.push(q);
    }
  }
  // The real finder patterns are the tallest, most regular quads; a QR that
  // fills the frame spawns dozens of short spurious quads from the data area.
  // Only score the top 24 by height — that keeps scorePattern's long scans
  // bounded and makes the O(n^2) grouping below cheap.
  const scoredFinders: ScoredFinder[] = [];
  for (const q of tallQuads) {
    const x = (q.top.startX + q.top.endX + q.bottom.startX + q.bottom.endX) / 4;
    const y = (q.top.y + q.bottom.y + 1) / 2;
    if (!matrix.get(Math.round(x), Math.round(y))) {
      continue;
    }
    const lengths: number[] = [q.top.endX - q.top.startX, q.bottom.endX - q.bottom.startX, q.bottom.y - q.top.y + 1];
    const size = sum(lengths) / lengths.length;
    const score = scorePattern({ x: Math.round(x), y: Math.round(y) }, [1, 1, 3, 1, 1], matrix);
    const sf: ScoredFinder = { score: score, x: x, y: y, size: size };
    scoredFinders.push(sf);
  }
  scoredFinders.sort((a: ScoredFinder, b: ScoredFinder): number => a.score - b.score);

  const groups: FinderPatternGroup[] = [];
  for (let i = 0; i < scoredFinders.length; i++) {
    if (i > MAX_FINDERPATTERNS_TO_SEARCH) {
      break;
    }
    const point = scoredFinders[i];
    if (point === undefined) {
      continue;
    }
    const otherPoints: ScoredFinder[] = [];
    for (let ii = 0; ii < scoredFinders.length; ii++) {
      if (i === ii) {
        continue;
      }
      const p = scoredFinders[ii];
      if (p === undefined) {
        continue;
      }
      const score = p.score + ((p.size - point.size) * (p.size - point.size)) / point.size;
      const sp: ScoredFinder = { x: p.x, y: p.y, score: score, size: p.size };
      otherPoints.push(sp);
    }
    otherPoints.sort((a: ScoredFinder, b: ScoredFinder): number => a.score - b.score);
    if (otherPoints.length < 2) {
      continue;
    }
    const op0 = otherPoints[0];
    const op1 = otherPoints[1];
    const score = point.score + (op0 === undefined ? 0 : op0.score) + (op1 === undefined ? 0 : op1.score);
    const pts: Point[] = [];
    pts.push({ x: point.x, y: point.y });
    if (op0 !== undefined) {
      pts.push({ x: op0.x, y: op0.y });
    }
    if (op1 !== undefined) {
      pts.push({ x: op1.x, y: op1.y });
    }
    const group: FinderPatternGroup = { points: pts, score: score };
    groups.push(group);
  }
  groups.sort((a: FinderPatternGroup, b: FinderPatternGroup): number => a.score - b.score);

  if (groups.length === 0) {
    return undefined;
  }

  const first = groups[0];
  if (first === undefined) {
    return undefined;
  }
  const p0 = first.points[0];
  const p1 = first.points[1];
  const p2 = first.points[2];
  if (p0 === undefined || p1 === undefined || p2 === undefined) {
    return undefined;
  }
  const reordered = reorderFinderPatterns(p0, p1, p2);
  const topRight = reordered.topRight;
  const topLeft = reordered.topLeft;
  const bottomLeft = reordered.bottomLeft;
  const alignment = findAlignmentPattern(matrix, alignmentPatternQuads, topRight, topLeft, bottomLeft);
  const result: QRLocation[] = [];
  if (alignment !== undefined) {
    const loc: QRLocation = {
      alignmentPattern: { x: alignment.alignmentPattern.x, y: alignment.alignmentPattern.y },
      bottomLeft: { x: bottomLeft.x, y: bottomLeft.y },
      dimension: alignment.dimension,
      topLeft: { x: topLeft.x, y: topLeft.y },
      topRight: { x: topRight.x, y: topRight.y },
    };
    result.push(loc);
  }

  const midTopRight = recenterLocation(matrix, topRight);
  const midTopLeft = recenterLocation(matrix, topLeft);
  const midBottomLeft = recenterLocation(matrix, bottomLeft);
  const centeredAlignment = findAlignmentPattern(matrix, alignmentPatternQuads, midTopRight, midTopLeft, midBottomLeft);
  if (centeredAlignment !== undefined) {
    const loc2: QRLocation = {
      alignmentPattern: { x: centeredAlignment.alignmentPattern.x, y: centeredAlignment.alignmentPattern.y },
      bottomLeft: { x: midBottomLeft.x, y: midBottomLeft.y },
      topLeft: { x: midTopLeft.x, y: midTopLeft.y },
      topRight: { x: midTopRight.x, y: midTopRight.y },
      dimension: centeredAlignment.dimension,
    };
    result.push(loc2);
  }

  if (result.length === 0) {
    hilog.info(0xdc1, 'Decimen', 'locate scan=%{public}dms post=%{public}dms quads=%{public}d result=0',
      tScan1 - tScan0, Date.now() - tScan1, tallQuads.length);
    return undefined;
  }
  hilog.info(0xdc1, 'Decimen', 'locate scan=%{public}dms post=%{public}dms quads=%{public}d locs=%{public}d',
    tScan1 - tScan0, Date.now() - tScan1, tallQuads.length, result.length);

  return result;
}

function squareToQuadrilateral(p1: Point, p2: Point, p3: Point, p4: Point): PerspectiveTransform {
  const dx3 = p1.x - p2.x + p3.x - p4.x;
  const dy3 = p1.y - p2.y + p3.y - p4.y;
  if (dx3 === 0 && dy3 === 0) {
    const result: PerspectiveTransform = {
      a11: p2.x - p1.x,
      a12: p2.y - p1.y,
      a13: 0,
      a21: p3.x - p2.x,
      a22: p3.y - p2.y,
      a23: 0,
      a31: p1.x,
      a32: p1.y,
      a33: 1,
    };
    return result;
  } else {
    const dx1 = p2.x - p3.x;
    const dx2 = p4.x - p3.x;
    const dy1 = p2.y - p3.y;
    const dy2 = p4.y - p3.y;
    const denominator = dx1 * dy2 - dx2 * dy1;
    const a13 = (dx3 * dy2 - dx2 * dy3) / denominator;
    const a23 = (dx1 * dy3 - dx3 * dy1) / denominator;
    const result: PerspectiveTransform = {
      a11: p2.x - p1.x + a13 * p2.x,
      a12: p2.y - p1.y + a13 * p2.y,
      a13: a13,
      a21: p4.x - p1.x + a23 * p4.x,
      a22: p4.y - p1.y + a23 * p4.y,
      a23: a23,
      a31: p1.x,
      a32: p1.y,
      a33: 1,
    };
    return result;
  }
}

function quadrilateralToSquare(p1: Point, p2: Point, p3: Point, p4: Point): PerspectiveTransform {
  const sToQ = squareToQuadrilateral(p1, p2, p3, p4);
  const result: PerspectiveTransform = {
    a11: sToQ.a22 * sToQ.a33 - sToQ.a23 * sToQ.a32,
    a12: sToQ.a13 * sToQ.a32 - sToQ.a12 * sToQ.a33,
    a13: sToQ.a12 * sToQ.a23 - sToQ.a13 * sToQ.a22,
    a21: sToQ.a23 * sToQ.a31 - sToQ.a21 * sToQ.a33,
    a22: sToQ.a11 * sToQ.a33 - sToQ.a13 * sToQ.a31,
    a23: sToQ.a13 * sToQ.a21 - sToQ.a11 * sToQ.a23,
    a31: sToQ.a21 * sToQ.a32 - sToQ.a22 * sToQ.a31,
    a32: sToQ.a12 * sToQ.a31 - sToQ.a11 * sToQ.a32,
    a33: sToQ.a11 * sToQ.a22 - sToQ.a12 * sToQ.a21,
  };
  return result;
}

function times(a: PerspectiveTransform, b: PerspectiveTransform): PerspectiveTransform {
  const result: PerspectiveTransform = {
    a11: a.a11 * b.a11 + a.a21 * b.a12 + a.a31 * b.a13,
    a12: a.a12 * b.a11 + a.a22 * b.a12 + a.a32 * b.a13,
    a13: a.a13 * b.a11 + a.a23 * b.a12 + a.a33 * b.a13,
    a21: a.a11 * b.a21 + a.a21 * b.a22 + a.a31 * b.a23,
    a22: a.a12 * b.a21 + a.a22 * b.a22 + a.a32 * b.a23,
    a23: a.a13 * b.a21 + a.a23 * b.a22 + a.a33 * b.a23,
    a31: a.a11 * b.a31 + a.a21 * b.a32 + a.a31 * b.a33,
    a32: a.a12 * b.a31 + a.a22 * b.a32 + a.a32 * b.a33,
    a33: a.a13 * b.a31 + a.a23 * b.a32 + a.a33 * b.a33,
  };
  return result;
}

function extract(image: BitMatrix, location: QRLocation): BitMatrix {
  const qToS = quadrilateralToSquare(
    { x: 3.5, y: 3.5 },
    { x: location.dimension - 3.5, y: 3.5 },
    { x: location.dimension - 6.5, y: location.dimension - 6.5 },
    { x: 3.5, y: location.dimension - 3.5 }
  );
  const sToQ = squareToQuadrilateral(location.topLeft, location.topRight, location.alignmentPattern, location.bottomLeft);
  const transform = times(sToQ, qToS);

  const matrix = BitMatrix.createEmpty(location.dimension, location.dimension);

  for (let y = 0; y < location.dimension; y++) {
    for (let x = 0; x < location.dimension; x++) {
      const xValue = x + 0.5;
      const yValue = y + 0.5;
      const denominator = transform.a13 * xValue + transform.a23 * yValue + transform.a33;
      const sourceX = (transform.a11 * xValue + transform.a21 * yValue + transform.a31) / denominator;
      const sourceY = (transform.a12 * xValue + transform.a22 * yValue + transform.a32) / denominator;
      matrix.set(x, y, image.get(Math.floor(sourceX), Math.floor(sourceY)));
    }
  }

  return matrix;
}

function numBitsDiffering(x: number, y: number): number {
  let z = x ^ y;
  let bitCount = 0;
  while (z !== 0) {
    bitCount++;
    z &= z - 1;
  }
  return bitCount;
}

function pushBit(bit: boolean, byte: number): number {
  return (byte << 1) | (bit ? 1 : 0);
}

function buildFunctionPatternMask(version: VersionInfo): BitMatrix {
  const dimension = 17 + 4 * version.versionNumber;
  const matrix = BitMatrix.createEmpty(dimension, dimension);

  matrix.setRegion(0, 0, 9, 9, true);
  matrix.setRegion(dimension - 8, 0, 8, 9, true);
  matrix.setRegion(0, dimension - 8, 9, 8, true);

  for (const x of version.alignmentPatternCenters) {
    for (const y of version.alignmentPatternCenters) {
      if (!(x === 6 && y === 6 || x === 6 && y === dimension - 7 || x === dimension - 7 && y === 6)) {
        matrix.setRegion(x - 2, y - 2, 5, 5, true);
      }
    }
  }

  matrix.setRegion(6, 9, 1, dimension - 17, true);
  matrix.setRegion(9, 6, dimension - 17, 1, true);

  if (version.versionNumber > 6) {
    matrix.setRegion(dimension - 11, 0, 3, 6, true);
    matrix.setRegion(0, dimension - 11, 6, 3, true);
  }

  return matrix;
}

function readCodewords(matrix: BitMatrix, version: VersionInfo, formatInfo: FormatInformation): number[] {
  let dataMask: (p: Point) => boolean = (p: Point): boolean => false;
  const dm = DATA_MASKS[formatInfo.dataMask];
  if (dm !== undefined) {
    dataMask = dm;
  }
  const dimension = matrix.height;

  const functionPatternMask = buildFunctionPatternMask(version);

  const codewords: number[] = [];
  let currentByte = 0;
  let bitsRead = 0;

  let readingUp = true;
  for (let columnIndex = dimension - 1; columnIndex > 0; columnIndex -= 2) {
    if (columnIndex === 6) {
      columnIndex--;
    }
    for (let i = 0; i < dimension; i++) {
      const y = readingUp ? dimension - 1 - i : i;
      for (let columnOffset = 0; columnOffset < 2; columnOffset++) {
        const x = columnIndex - columnOffset;
        if (!functionPatternMask.get(x, y)) {
          bitsRead++;
          let bit = matrix.get(x, y);
          if (dataMask({ y: y, x: x })) {
            bit = !bit;
          }
          currentByte = pushBit(bit, currentByte);
          if (bitsRead === 8) {
            codewords.push(currentByte);
            bitsRead = 0;
            currentByte = 0;
          }
        }
      }
    }
    readingUp = !readingUp;
  }
  return codewords;
}

function readVersion(matrix: BitMatrix): VersionInfo | undefined {
  const dimension = matrix.height;

  const provisionalVersion = Math.floor((dimension - 17) / 4);
  if (provisionalVersion <= 6) {
    return VERSIONS[provisionalVersion - 1];
  }

  let topRightVersionBits = 0;
  for (let y = 5; y >= 0; y--) {
    for (let x = dimension - 9; x >= dimension - 11; x--) {
      topRightVersionBits = pushBit(matrix.get(x, y), topRightVersionBits);
    }
  }

  let bottomLeftVersionBits = 0;
  for (let x = 5; x >= 0; x--) {
    for (let y = dimension - 9; y >= dimension - 11; y--) {
      bottomLeftVersionBits = pushBit(matrix.get(x, y), bottomLeftVersionBits);
    }
  }

  let bestDifference = Infinity;
  let bestVersion: VersionInfo | undefined = undefined;
  for (const version of VERSIONS) {
    if (version.infoBits === topRightVersionBits || version.infoBits === bottomLeftVersionBits) {
      return version;
    }

    let difference = numBitsDiffering(topRightVersionBits, version.infoBits);
    if (difference < bestDifference) {
      bestVersion = version;
      bestDifference = difference;
    }

    difference = numBitsDiffering(bottomLeftVersionBits, version.infoBits);
    if (difference < bestDifference) {
      bestVersion = version;
      bestDifference = difference;
    }
  }
  if (bestDifference <= 3) {
    return bestVersion;
  }
  return undefined;
}

function readFormatInformation(matrix: BitMatrix): FormatInformation | undefined {
  let topLeftFormatInfoBits = 0;
  for (let x = 0; x <= 8; x++) {
    if (x !== 6) {
      topLeftFormatInfoBits = pushBit(matrix.get(x, 8), topLeftFormatInfoBits);
    }
  }
  for (let y = 7; y >= 0; y--) {
    if (y !== 6) {
      topLeftFormatInfoBits = pushBit(matrix.get(8, y), topLeftFormatInfoBits);
    }
  }

  const dimension = matrix.height;
  let topRightBottomRightFormatInfoBits = 0;
  for (let y = dimension - 1; y >= dimension - 7; y--) {
    topRightBottomRightFormatInfoBits = pushBit(matrix.get(8, y), topRightBottomRightFormatInfoBits);
  }
  for (let x = dimension - 8; x < dimension; x++) {
    topRightBottomRightFormatInfoBits = pushBit(matrix.get(x, 8), topRightBottomRightFormatInfoBits);
  }

  let bestDifference = Infinity;
  let bestFormatInfo: FormatInformation | undefined = undefined;
  for (const entry of FORMAT_INFO_TABLE) {
    if (entry.bits === topLeftFormatInfoBits || entry.bits === topRightBottomRightFormatInfoBits) {
      return entry.formatInfo;
    }
    let difference = numBitsDiffering(topLeftFormatInfoBits, entry.bits);
    if (difference < bestDifference) {
      bestFormatInfo = entry.formatInfo;
      bestDifference = difference;
    }
    if (topLeftFormatInfoBits !== topRightBottomRightFormatInfoBits) {
      difference = numBitsDiffering(topRightBottomRightFormatInfoBits, entry.bits);
      if (difference < bestDifference) {
        bestFormatInfo = entry.formatInfo;
        bestDifference = difference;
      }
    }
  }
  if (bestDifference <= 3) {
    return bestFormatInfo;
  }
  return undefined;
}

function getDataBlocks(codewords: number[], version: VersionInfo, ecLevel: number): DataBlock[] | undefined {
  const ecInfo = version.errorCorrectionLevels[ecLevel];
  if (ecInfo === undefined) {
    return undefined;
  }
  const dataBlocks: DataBlock[] = [];

  let totalCodewords = 0;
  for (const block of ecInfo.ecBlocks) {
    for (let i = 0; i < block.numBlocks; i++) {
      const db: DataBlock = { numDataCodewords: block.dataCodewordsPerBlock, codewords: [] };
      dataBlocks.push(db);
      totalCodewords += block.dataCodewordsPerBlock + ecInfo.ecCodewordsPerBlock;
    }
  }

  if (codewords.length < totalCodewords) {
    return undefined;
  }
  const remainingCodewords = codewords.slice(0, totalCodewords);

  const shortBlockSize = ecInfo.ecBlocks[0]?.dataCodewordsPerBlock ?? 0;
  for (let i = 0; i < shortBlockSize; i++) {
    for (const dataBlock of dataBlocks) {
      const cw = remainingCodewords.shift();
      if (cw !== undefined) {
        dataBlock.codewords.push(cw);
      }
    }
  }

  if (ecInfo.ecBlocks.length > 1) {
    const smallBlockCount = ecInfo.ecBlocks[0]?.numBlocks ?? 0;
    const largeBlockCount = ecInfo.ecBlocks[1]?.numBlocks ?? 0;
    for (let i = 0; i < largeBlockCount; i++) {
      const db = dataBlocks[smallBlockCount + i];
      const cw = remainingCodewords.shift();
      if (db !== undefined && cw !== undefined) {
        db.codewords.push(cw);
      }
    }
  }

  while (remainingCodewords.length > 0) {
    for (const dataBlock of dataBlocks) {
      const cw = remainingCodewords.shift();
      if (cw !== undefined) {
        dataBlock.codewords.push(cw);
      }
    }
  }

  return dataBlocks;
}

function runEuclideanAlgorithm(field: GenericGF, a: GenericGFPoly, b: GenericGFPoly, R: number): GenericGFPoly[] | undefined {
  let polyA = a;
  let polyB = b;
  if (polyA.degree() < polyB.degree()) {
    const tmp = polyA;
    polyA = polyB;
    polyB = tmp;
  }

  let rLast = polyA;
  let r = polyB;
  let tLast = field.zero;
  let t = field.one;

  while (r.degree() >= R / 2) {
    const rLastLast = rLast;
    const tLastLast = tLast;
    rLast = r;
    tLast = t;

    if (rLast.isZero()) {
      return undefined;
    }
    r = rLastLast;
    let q = field.zero;
    const denominatorLeadingTerm = rLast.getCoefficient(rLast.degree());
    const dltInverse = field.inverse(denominatorLeadingTerm);
    while (r.degree() >= rLast.degree() && !r.isZero()) {
      const degreeDiff = r.degree() - rLast.degree();
      const scale = field.multiply(r.getCoefficient(r.degree()), dltInverse);
      q = q.addOrSubtract(field.buildMonomial(degreeDiff, scale));
      r = r.addOrSubtract(rLast.multiplyByMonomial(degreeDiff, scale));
    }

    t = q.multiplyPoly(tLast).addOrSubtract(tLastLast);

    if (r.degree() >= rLast.degree()) {
      return undefined;
    }
  }

  const sigmaTildeAtZero = t.getCoefficient(0);
  if (sigmaTildeAtZero === 0) {
    return undefined;
  }

  const inverse = field.inverse(sigmaTildeAtZero);
  const result: GenericGFPoly[] = [t.multiply(inverse), r.multiply(inverse)];
  return result;
}

function findErrorLocations(field: GenericGF, errorLocator: GenericGFPoly): number[] | undefined {
  const numErrors = errorLocator.degree();
  if (numErrors === 1) {
    return [errorLocator.getCoefficient(1)];
  }
  const result: number[] = [];
  let errorCount = 0;
  for (let i = 1; i < field.size && errorCount < numErrors; i++) {
    if (errorLocator.evaluateAt(i) === 0) {
      result.push(field.inverse(i));
      errorCount++;
    }
  }
  if (errorCount !== numErrors) {
    return undefined;
  }
  return result;
}

function findErrorMagnitudes(field: GenericGF, errorEvaluator: GenericGFPoly, errorLocations: number[]): number[] {
  const s = errorLocations.length;
  const result: number[] = [];
  for (let i = 0; i < s; i++) {
    const loc = errorLocations[i];
    const xiInverse = loc === undefined ? 0 : field.inverse(loc);
    let denominator = 1;
    for (let j = 0; j < s; j++) {
      if (i !== j) {
        const locJ = errorLocations[j];
        denominator = field.multiply(denominator, addOrSubtractGF(1, field.multiply(locJ === undefined ? 0 : locJ, xiInverse)));
      }
    }
    let magnitude = field.multiply(errorEvaluator.evaluateAt(xiInverse), field.inverse(denominator));
    if (field.generatorBase !== 0) {
      magnitude = field.multiply(magnitude, xiInverse);
    }
    result.push(magnitude);
  }
  return result;
}

function rsDecode(bytes: number[], twoS: number): Uint8ClampedArray | undefined {
  const outputBytes = new Uint8ClampedArray(bytes.length);
  outputBytes.set(bytes);

  const field = new GenericGF(0x011D, 256, 0);
  const poly = new GenericGFPoly(field, outputBytes);

  const syndromeCoefficients = new Uint8ClampedArray(twoS);
  let error = false;
  for (let s = 0; s < twoS; s++) {
    const evaluation = poly.evaluateAt(field.exp(s + field.generatorBase));
    syndromeCoefficients[syndromeCoefficients.length - 1 - s] = evaluation;
    if (evaluation !== 0) {
      error = true;
    }
  }
  if (!error) {
    return outputBytes;
  }

  const syndrome = new GenericGFPoly(field, syndromeCoefficients);

  const sigmaOmega = runEuclideanAlgorithm(field, field.buildMonomial(twoS, 1), syndrome, twoS);
  if (sigmaOmega === undefined) {
    return undefined;
  }

  const errorLocations = findErrorLocations(field, sigmaOmega[0]);
  if (errorLocations === undefined) {
    return undefined;
  }

  const errorMagnitudes = findErrorMagnitudes(field, sigmaOmega[1], errorLocations);
  for (let i = 0; i < errorLocations.length; i++) {
    const loc = errorLocations[i];
    if (loc === undefined) {
      return undefined;
    }
    const position = outputBytes.length - 1 - field.log(loc);
    if (position < 0) {
      return undefined;
    }
    const mag = errorMagnitudes[i];
    if (mag === undefined) {
      return undefined;
    }
    outputBytes[position] = addOrSubtractGF(outputBytes[position], mag);
  }

  return outputBytes;
}

function decodeNumeric(stream: BitStream, size: number): NumericResult {
  const bytes: number[] = [];
  let text = "";

  const characterCountSizes: number[] = [10, 12, 14];
  const characterCountSize = characterCountSizes[size] ?? 0;
  let length = stream.readBits(characterCountSize);
  while (length >= 3) {
    const num = stream.readBits(10);
    if (num >= 1000) {
      throw new Error("Invalid numeric value above 999");
    }

    const a = Math.floor(num / 100);
    const b = Math.floor(num / 10) % 10;
    const c = num % 10;

    bytes.push(48 + a, 48 + b, 48 + c);
    text += a.toString() + b.toString() + c.toString();
    length -= 3;
  }

  if (length === 2) {
    const num = stream.readBits(7);
    if (num >= 100) {
      throw new Error("Invalid numeric value above 99");
    }

    const a = Math.floor(num / 10);
    const b = num % 10;

    bytes.push(48 + a, 48 + b);
    text += a.toString() + b.toString();
  } else if (length === 1) {
    const num = stream.readBits(4);
    if (num >= 10) {
      throw new Error("Invalid numeric value above 9");
    }

    bytes.push(48 + num);
    text += num.toString();
  }

  const result: NumericResult = { bytes: bytes, text: text };
  return result;
}

function decodeAlphanumeric(stream: BitStream, size: number): NumericResult {
  const bytes: number[] = [];
  let text = "";

  const characterCountSizes: number[] = [9, 11, 13];
  const characterCountSize = characterCountSizes[size] ?? 0;
  let length = stream.readBits(characterCountSize);
  while (length >= 2) {
    const v = stream.readBits(11);

    const a = Math.floor(v / 45);
    const b = v % 45;

    const codeA = AlphanumericCharacterCodes[a];
    const codeB = AlphanumericCharacterCodes[b];
    const ca = codeA === undefined ? "" : codeA;
    const cb = codeB === undefined ? "" : codeB;

    bytes.push(ca.charCodeAt(0), cb.charCodeAt(0));
    text += ca + cb;
    length -= 2;
  }

  if (length === 1) {
    const a = stream.readBits(6);
    const codeA = AlphanumericCharacterCodes[a];
    const ca = codeA === undefined ? "" : codeA;
    bytes.push(ca.charCodeAt(0));
    text += ca;
  }

  const result: NumericResult = { bytes: bytes, text: text };
  return result;
}

function decodeByte(stream: BitStream, size: number): NumericResult {
  const bytes: number[] = [];
  let text = "";

  const characterCountSizes: number[] = [8, 16, 16];
  const characterCountSize = characterCountSizes[size] ?? 0;
  const length = stream.readBits(characterCountSize);
  for (let i = 0; i < length; i++) {
    const b = stream.readBits(8);
    bytes.push(b);
  }
  try {
    let encoded = "";
    for (let i = 0; i < bytes.length; i++) {
      const b = bytes[i];
      const value = b === undefined ? 0 : b;
      encoded += "%" + ("0" + value.toString(16)).slice(-2);
    }
    text += decodeURIComponent(encoded);
  } catch (e) {
    // Failed to decode bytes as a valid string; keep the raw bytes.
  }

  const result: NumericResult = { bytes: bytes, text: text };
  return result;
}

function decodeKanji(stream: BitStream, size: number): NumericResult {
  throw new Error("kanji not supported");
}

function decodeData(data: Uint8ClampedArray, version: number): DecodedQR | undefined {
  const stream = new BitStream(data);

  const size = version <= 9 ? 0 : version <= 26 ? 1 : 2;

  const result: DecodedQR = {
    text: "",
    bytes: [],
    chunks: [],
    version: version,
  };

  while (stream.available() >= 4) {
    const mode = stream.readBits(4);
    if (mode === ModeByte.Terminator) {
      return result;
    } else if (mode === ModeByte.ECI) {
      if (stream.readBits(1) === 0) {
        const chunk: Chunk = new Chunk();
        chunk.type = Mode.ECI;
        chunk.assignmentNumber = stream.readBits(7);
        result.chunks.push(chunk);
      } else if (stream.readBits(1) === 0) {
        const chunk: Chunk = new Chunk();
        chunk.type = Mode.ECI;
        chunk.assignmentNumber = stream.readBits(14);
        result.chunks.push(chunk);
      } else if (stream.readBits(1) === 0) {
        const chunk: Chunk = new Chunk();
        chunk.type = Mode.ECI;
        chunk.assignmentNumber = stream.readBits(21);
        result.chunks.push(chunk);
      } else {
        const chunk: Chunk = new Chunk();
        chunk.type = Mode.ECI;
        chunk.assignmentNumber = -1;
        result.chunks.push(chunk);
      }
    } else if (mode === ModeByte.Numeric) {
      const numericResult = decodeNumeric(stream, size);
      result.text += numericResult.text;
      for (const b of numericResult.bytes) {
        result.bytes.push(b);
      }
      const chunk: Chunk = new Chunk();
      chunk.type = Mode.Numeric;
      chunk.text = numericResult.text;
      result.chunks.push(chunk);
    } else if (mode === ModeByte.Alphanumeric) {
      const alphanumericResult = decodeAlphanumeric(stream, size);
      result.text += alphanumericResult.text;
      for (const b of alphanumericResult.bytes) {
        result.bytes.push(b);
      }
      const chunk: Chunk = new Chunk();
      chunk.type = Mode.Alphanumeric;
      chunk.text = alphanumericResult.text;
      result.chunks.push(chunk);
    } else if (mode === ModeByte.Byte) {
      const byteResult = decodeByte(stream, size);
      result.text += byteResult.text;
      for (const b of byteResult.bytes) {
        result.bytes.push(b);
      }
      const chunk: Chunk = new Chunk();
      chunk.type = Mode.Byte;
      chunk.bytes = byteResult.bytes;
      chunk.text = byteResult.text;
      result.chunks.push(chunk);
    } else if (mode === ModeByte.Kanji) {
      decodeKanji(stream, size);
    }
  }

  if (stream.available() === 0 || stream.readBits(stream.available()) === 0) {
    return result;
  }
  return undefined;
}

function decodeMatrix(matrix: BitMatrix): DecodedQR | undefined {
  const version = readVersion(matrix);
  if (version === undefined) {
    return undefined;
  }

  const formatInfo = readFormatInformation(matrix);
  if (formatInfo === undefined) {
    return undefined;
  }

  const codewords = readCodewords(matrix, version, formatInfo);
  const dataBlocks = getDataBlocks(codewords, version, formatInfo.errorCorrectionLevel);
  if (dataBlocks === undefined) {
    return undefined;
  }

  let totalBytes = 0;
  for (const dataBlock of dataBlocks) {
    totalBytes += dataBlock.numDataCodewords;
  }
  const resultBytes = new Uint8ClampedArray(totalBytes);

  let resultIndex = 0;
  for (const dataBlock of dataBlocks) {
    const correctedBytes = rsDecode(dataBlock.codewords, dataBlock.codewords.length - dataBlock.numDataCodewords);
    if (correctedBytes === undefined) {
      return undefined;
    }
    for (let i = 0; i < dataBlock.numDataCodewords; i++) {
      resultBytes[resultIndex] = correctedBytes[i];
      resultIndex++;
    }
  }

  try {
    return decodeData(resultBytes, version.versionNumber);
  } catch (e) {
    return undefined;
  }
}

function decodeQrMatrix(matrix: BitMatrix): DecodedQR | undefined {
  const result = decodeMatrix(matrix);
  if (result !== undefined) {
    return result;
  }
  for (let x = 0; x < matrix.width; x++) {
    for (let y = x + 1; y < matrix.height; y++) {
      if (matrix.get(x, y) !== matrix.get(y, x)) {
        matrix.set(x, y, !matrix.get(x, y));
        matrix.set(y, x, !matrix.get(y, x));
      }
    }
  }
  return decodeMatrix(matrix);
}

interface ScanOutcome {
  decoded: DecodedQR | undefined;
  located: QrBox | undefined;
}

function scan(matrix: BitMatrix): ScanOutcome {
  const tLocate0: number = Date.now();
  const locations = locate(matrix);
  const tLocate1: number = Date.now();
  if (locations === undefined) {
    hilog.info(0xdc1, 'Decimen', 'scan locate=%{public}dms none', tLocate1 - tLocate0);
    return { decoded: undefined, located: undefined };
  }
  hilog.info(0xdc1, 'Decimen', 'scan locate=%{public}dms locs=%{public}d', tLocate1 - tLocate0, locations.length);

  const first: QrBox = boundingBox(locations[0]);
  for (const location of locations) {
    const tE0: number = Date.now();
    const extracted = extract(matrix, location);
    const decoded = decodeQrMatrix(extracted);
    const tE1: number = Date.now();
    hilog.info(0xdc1, 'Decimen', 'scan extract+decode=%{public}dms ok=%{public}d', tE1 - tE0, decoded === undefined ? 0 : 1);
    if (decoded !== undefined) {
      return {
        decoded: {
          text: decoded.text,
          bytes: decoded.bytes,
          chunks: decoded.chunks,
          version: decoded.version,
          box: boundingBox(location),
        },
        located: first,
      };
    }
  }
  return { decoded: undefined, located: first };
}

export function decodeQr(data: Uint8ClampedArray, width: number, height: number): QrDecodeResult | undefined {
  try {
    const t0: number = Date.now();
    const binarized = binarize(data, width, height);
    const t1: number = Date.now();
    const outcome = scan(binarized);
    const t2: number = Date.now();
    if (t2 - t0 > 100) {
      hilog.info(0xdc1, 'Decimen', 'stage binarize=%{public}dms locate+decode=%{public}dms size=%{public}dx%{public}d',
        t1 - t0, t2 - t1, width, height);
    }
    if (outcome.decoded === undefined) {
      // Finder patterns were located but the module grid could not be
      // extracted (e.g. too few pixels per module). Surface the estimated box
      // so the caller can re-decode that region at a higher resolution.
      const located: QrBox | undefined = outcome.located;
      if (located !== undefined) {
        return {
          bytes: new Uint8Array(0),
          version: 0,
          x: located.x,
          y: located.y,
          w: located.w,
          h: located.h,
          ok: false,
        };
      }
      return undefined;
    }
    const box: QrBox | undefined = outcome.decoded.box;
    if (box === undefined) {
      return undefined;
    }
    const result: QrDecodeResult = {
      bytes: Uint8Array.from(outcome.decoded.bytes),
      version: outcome.decoded.version,
      x: box.x,
      y: box.y,
      w: box.w,
      h: box.h,
      ok: true,
    };
    return result;
  } catch (e) {
    return undefined;
  }
}
