export const NO_SIGNAL_HINT_FRAME_BYTES: number = 1465;
export const NO_SIGNAL_HINT_TX_FPS: number = 24;

export const DEFAULT_TX_FPS: number = 60;
export const DEFAULT_FRAME_BYTES: number = 2953;

export const TX_FPS_OPTIONS: number[] = [
  10,
  15,
  20,
  NO_SIGNAL_HINT_TX_FPS,
  30,
  55,
  DEFAULT_TX_FPS,
];
export const FRAME_BYTES_OPTIONS: number[] = [
  500,
  1000,
  NO_SIGNAL_HINT_FRAME_BYTES,
  1850,
  2331,
  DEFAULT_FRAME_BYTES,
];
