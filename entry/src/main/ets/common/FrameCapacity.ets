import { HEADER_LEN } from './Protocol';

export const MAX_SOURCE_BLOCKS: number = 0xffff;

export function blockLength(frameBytes: number): number {
  return frameBytes - HEADER_LEN;
}

export function sourceBlockCount(payloadBytes: number, frameBytes: number): number {
  return Math.ceil(payloadBytes / blockLength(frameBytes));
}

export function fitsInOneStream(payloadBytes: number, frameBytes: number): boolean {
  return sourceBlockCount(payloadBytes, frameBytes) <= MAX_SOURCE_BLOCKS;
}

export function minimumFrameBytes(payloadBytes: number): number {
  return Math.ceil(payloadBytes / MAX_SOURCE_BLOCKS) + HEADER_LEN;
}

export function smallestSufficientFrameSize(
  payloadBytes: number,
  options: number[],
): number | undefined {
  const minimum: number = minimumFrameBytes(payloadBytes);
  const sorted: number[] = options.filter((value: number): boolean => value >= minimum)
    .sort((a: number, b: number): number => a - b);
  return sorted.length > 0 ? sorted[0] : undefined;
}
