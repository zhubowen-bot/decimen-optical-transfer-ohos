export function expectedFountainOverhead(sourceBlocks: number): number {
  return sourceBlocks <= 1 ? 1 : 1.02;
}

export interface TransferProgressEstimate {
  fraction: number;
  expectedFrames: number;
  etaSeconds?: number;
  phase: 'collecting' | 'decoding';
}

export function estimateTransferProgress(
  sourceBlocks: number,
  uniqueFrames: number,
  elapsedSeconds: number,
  solvedBlocks: number,
): TransferProgressEstimate {
  const minimumFrames: number = Math.max(1, sourceBlocks);
  const expectedFrames: number = Math.max(
    minimumFrames + 1,
    Math.ceil(minimumFrames * expectedFountainOverhead(minimumFrames)),
  );
  const expectedRedundancy: number = expectedFrames - minimumFrames;

  let frameFraction: number;
  if (uniqueFrames < minimumFrames) {
    frameFraction = 0.86 * (uniqueFrames / minimumFrames);
  } else if (uniqueFrames <= expectedFrames) {
    frameFraction = 0.86 + 0.1 * ((uniqueFrames - minimumFrames) / expectedRedundancy);
  } else {
    const extra: number = (uniqueFrames - expectedFrames) / expectedRedundancy;
    frameFraction = 0.96 + 0.03 * (1 - Math.exp(-extra));
  }
  if (solvedBlocks > 0) {
    const lead: number = 0.12 * minimumFrames;
    frameFraction = Math.min(
      frameFraction,
      0.86 * Math.min(1, (solvedBlocks + lead) / minimumFrames),
    );
  }
  const decodedFraction: number = 0.99 * Math.min(1, solvedBlocks / minimumFrames);
  const fraction: number = Math.min(0.99, Math.max(frameFraction, decodedFraction));
  const phase: 'collecting' | 'decoding' = uniqueFrames < minimumFrames ? 'collecting' : 'decoding';
  const rate: number = elapsedSeconds > 0 ? uniqueFrames / elapsedSeconds : 0;

  const overshoot: number = uniqueFrames - expectedFrames;
  const step: number = Math.max(expectedRedundancy, Math.ceil(minimumFrames / 10));
  const target: number =
    overshoot < 0 ? expectedFrames : expectedFrames + step * (Math.floor(overshoot / step) + 1);
  const etaSeconds: number | undefined =
    uniqueFrames >= 3 && elapsedSeconds >= 1 && rate > 0 ? (target - uniqueFrames) / rate : undefined;
  return { fraction, expectedFrames, etaSeconds, phase };
}

export function formatDuration(seconds: number): string {
  const rounded: number = Math.max(1, Math.ceil(seconds));
  if (rounded < 60) {
    return `${rounded}s`;
  }
  const minutes: number = Math.floor(rounded / 60);
  const remainder: number = rounded % 60;
  if (minutes < 60) {
    return remainder === 0 ? `${minutes}m` : `${minutes}m ${remainder}s`;
  }
  const hours: number = Math.floor(minutes / 60);
  const remainingMinutes: number = minutes % 60;
  return remainingMinutes === 0 ? `${hours}h` : `${hours}h ${remainingMinutes}m`;
}
