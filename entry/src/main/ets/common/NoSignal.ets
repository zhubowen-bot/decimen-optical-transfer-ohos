export class NoSignalHintTimer {
  private readonly firstDelayMs: number;
  private readonly dismissedDelayMs: number;
  private armed: boolean = false;
  private armedAt: number = 0;
  private delayMs: number;
  private visible: boolean = false;
  private sawFrame: boolean = false;

  constructor(firstDelayMs: number, dismissedDelayMs: number) {
    this.firstDelayMs = firstDelayMs;
    this.dismissedDelayMs = dismissedDelayMs;
    this.delayMs = firstDelayMs;
  }

  get isVisible(): boolean {
    return this.visible;
  }

  cameraStarted(now: number): void {
    if (this.sawFrame) {
      return;
    }
    this.armed = true;
    this.armedAt = now;
    this.delayMs = this.firstDelayMs;
    this.visible = false;
  }

  tick(now: number): boolean {
    if (!this.armed || this.visible || this.sawFrame) {
      return false;
    }
    if (now - this.armedAt <= this.delayMs) {
      return false;
    }
    this.visible = true;
    return true;
  }

  dismiss(now: number): void {
    this.visible = false;
    this.armedAt = now;
    this.delayMs = this.dismissedDelayMs;
  }

  frameDecoded(): boolean {
    const wasVisible: boolean = this.visible;
    this.sawFrame = true;
    this.armed = false;
    this.visible = false;
    return wasVisible;
  }
}
