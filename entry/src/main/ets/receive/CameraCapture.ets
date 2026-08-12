import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xdc1;

export interface CameraFrame {
  gray: Uint8Array;
  width: number;
  height: number;
}

export class CameraCapture {
  private manager: camera.CameraManager | undefined = undefined;
  private cameraInput: camera.CameraInput | undefined = undefined;
  private displayOutput: camera.PreviewOutput | undefined = undefined;
  private processOutput: camera.PreviewOutput | undefined = undefined;
  private session: camera.Session | undefined = undefined;
  private receiver: image.ImageReceiver | undefined = undefined;
  private onFrameCb: ((frame: CameraFrame) => void) | undefined = undefined;
  private active: boolean = false;
  displayWidth: number = 0;
  displayHeight: number = 0;
  frameWidth: number = 0;
  frameHeight: number = 0;

  async start(
    context: common.UIAbilityContext,
    displaySurfaceId: string,
    onFrame: (frame: CameraFrame) => void,
  ): Promise<void> {
    const manager: camera.CameraManager = camera.getCameraManager(context);
    this.manager = manager;
    const devices: Array<camera.CameraDevice> = manager.getSupportedCameras();
    let back: camera.CameraDevice | undefined = undefined;
    for (const device of devices) {
      if (device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) {
        back = device;
        break;
      }
    }
    if (back === undefined && devices.length > 0) {
      back = devices[0];
    }
    if (back === undefined) {
      throw new Error('no camera available');
    }

    const capability: camera.CameraOutputCapability =
      manager.getSupportedOutputCapability(back, camera.SceneMode.NORMAL_PHOTO);
    const displayProfile: camera.Profile = this.pickPreviewProfile(capability.previewProfiles, 640, 480);
    const processProfile: camera.Profile = this.pickPreviewProfile(capability.previewProfiles, 1280, 960);    const size: image.Size = processProfile.size;
    this.frameWidth = size.width;
    this.frameHeight = size.height;
    this.displayWidth = displayProfile.size.width;
    this.displayHeight = displayProfile.size.height;
    hilog.info(DOMAIN, 'Decimen', 'cam display %{public}dx%{public}d process %{public}dx%{public}d',
      displayProfile.size.width, displayProfile.size.height, size.width, size.height);

    const cameraInput: camera.CameraInput = manager.createCameraInput(back);
    this.cameraInput = cameraInput;
    await cameraInput.open();

    const displayOutput: camera.PreviewOutput = manager.createPreviewOutput(displayProfile, displaySurfaceId);
    this.displayOutput = displayOutput;

    const receiver: image.ImageReceiver =
      image.createImageReceiver(size.width, size.height, image.ImageFormat.JPEG, 8);
    this.receiver = receiver;
    this.onFrameCb = onFrame;
    receiver.on('imageArrival', () => {
      this.pullFrame();
    });
    const processSurfaceId: string = await receiver.getReceivingSurfaceId();
    const processOutput: camera.PreviewOutput = manager.createPreviewOutput(processProfile, processSurfaceId);
    this.processOutput = processOutput;

    const session: camera.Session = manager.createSession(camera.SceneMode.NORMAL_PHOTO);
    this.session = session;
    session.beginConfig();
    session.addInput(cameraInput);
    session.addOutput(displayOutput);
    session.addOutput(processOutput);
    await session.commitConfig();
    await session.start();
    this.active = true;
    hilog.info(DOMAIN, 'Decimen', 'cam dual session started');
  }

  async stop(): Promise<void> {
    this.active = false;
    const session: camera.Session | undefined = this.session;
    if (session !== undefined) {
      try {
        await session.stop();
      } catch (err) {
        hilog.warn(DOMAIN, 'Decimen', 'session stop failed: %{public}s', JSON.stringify(err));
      }
    }
    const displayOutput: camera.PreviewOutput | undefined = this.displayOutput;
    if (displayOutput !== undefined) {
      await displayOutput.release();
    }
    const processOutput: camera.PreviewOutput | undefined = this.processOutput;
    if (processOutput !== undefined) {
      await processOutput.release();
    }
    const cameraInput: camera.CameraInput | undefined = this.cameraInput;
    if (cameraInput !== undefined) {
      await cameraInput.close();
    }
    if (session !== undefined) {
      try {
        await session.release();
      } catch (err) {
        hilog.warn(DOMAIN, 'Decimen', 'session release failed: %{public}s', JSON.stringify(err));
      }
    }
    const receiver: image.ImageReceiver | undefined = this.receiver;
    if (receiver !== undefined) {
      receiver.off('imageArrival');
      await receiver.release();
    }
    this.session = undefined;
    this.displayOutput = undefined;
    this.processOutput = undefined;
    this.cameraInput = undefined;
    this.receiver = undefined;
    this.onFrameCb = undefined;
  }

  private pickPreviewProfile(profiles: Array<camera.Profile>, tw: number, th: number): camera.Profile {
    let best: camera.Profile | undefined = undefined;
    let bestScore: number = Number.MAX_SAFE_INTEGER;
    const targetAspect: number = tw / th;
    for (const profile of profiles) {
      const w: number = profile.size.width;
      const h: number = profile.size.height;
      const aspect: number = w / h;
      const score: number = Math.abs(w - tw) + Math.abs(h - th) + Math.abs(aspect - targetAspect) * 1000;
      if (score < bestScore) {
        bestScore = score;
        best = profile;
      }
    }
    if (best === undefined) {
      throw new Error('no preview profile available');
    }
    return best;
  }

  private async pullFrame(): Promise<void> {
    const receiver: image.ImageReceiver | undefined = this.receiver;
    const cb: ((frame: CameraFrame) => void) | undefined = this.onFrameCb;
    if (receiver === undefined || cb === undefined || !this.active) {
      return;
    }
    let img: image.Image | undefined = undefined;
    try {
      img = await receiver.readLatestImage();
      if (img === undefined) {
        return;
      }
      const comp: image.Component = await img.getComponent(image.ComponentType.JPEG);
      const buf: ArrayBuffer = comp.byteBuffer;
      const rowStride: number = comp.rowStride;
      const w: number = this.frameWidth;
      const h: number = this.frameHeight;
      const gray: Uint8Array = new Uint8Array(w * h);
      const src: Uint8Array = new Uint8Array(buf);
      for (let y = 0; y < h; y++) {
        const row: number = y * rowStride;
        gray.set(src.subarray(row, row + w), y * w);
      }
      cb({ gray, width: w, height: h });
    } catch (err) {
      hilog.warn(DOMAIN, 'Decimen', 'frame pull failed: %{public}s', String(err));
    } finally {
      if (img !== undefined) {
        img.release();
      }
    }
  }
}
