// 底部沉浸式光感导航栏框架参考自 BowenAPP-Web（开源项目）：
// HdsNavigation + HdsTabs（UIDesignKit）实现，原项目版权归原作者所有。
// 本页合并了原 SendPage / ReceivePage 的原生宿主逻辑（文件选择 / 保存 / 剪贴板）。

import { webview } from '@kit.ArkWeb';
import { abilityAccessCtrl, common, Permissions, Want } from '@kit.AbilityKit';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsNavigation, HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xdc1;
const TAG: string = 'LiveQRTransfer';
// H5 主题色（与 rawfile 页面 :root 的 --accent 保持一致）
const ACCENT_COLOR: string = '#1C1B18';

interface MenuItem {
  symbolGlyph: SymbolGlyphModifier;
  symbolGlyph1: SymbolGlyphModifier;
  label: string;
  url: Resource;
}

// 底部导航菜单配置
const MENU_CONFIG: MenuItem[] = [
  {
    symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.paperplane_fill'))
      .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off')]),
    symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.paperplane_fill'))
      .fontColor([ACCENT_COLOR]),
    label: '发送',
    url: $rawfile('decimen-sender.html')
  },
  {
    symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.camera_fill'))
      .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off')]),
    symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.camera_fill'))
      .fontColor([ACCENT_COLOR]),
    label: '接收',
    url: $rawfile('decimen-receiver.html')
  },
  {
    symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.info_circle_fill'))
      .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off')]),
    symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.info_circle_fill'))
      .fontColor([ACCENT_COLOR]),
    label: '关于',
    url: $rawfile('about.html')
  }
];

// 与 Web 页面通信的原生宿主（网页通过 decimenHost 调用）
class TransferHost {
  private owner: Index;

  constructor(owner: Index) {
    this.owner = owner;
  }

  // 发送端
  onFileReady(name: string, size: number): void {
    this.owner.onFileReady(name, size);
  }

  onError(message: string): void {
    this.owner.onError(message);
  }

  pickFile(): void {
    this.owner.pickFile();
  }

  // 接收端
  beginSave(name: string): void {
    this.owner.onBeginSave(name);
  }

  appendChunk(base64: string): void {
    this.owner.onAppendChunk(base64);
  }

  endSave(): void {
    this.owner.onEndSave();
  }

  copyText(text: string): void {
    this.owner.onCopyText(text);
  }
}

@Entry
@Component
struct Index {
  @State currentTabIndex: number = 0;
  // 为每个 Tab 创建独立的 WebviewController
  @State controllers: webview.WebviewController[] = [
    new webview.WebviewController(),
    new webview.WebviewController(),
    new webview.WebviewController()
  ];
  private tabsController: HdsTabsController = new HdsTabsController();
  private host: TransferHost = new TransferHost(this);
  private permissionRequested: boolean = false;
  private saveDir: string = '';
  private saveFile: fs.File | undefined = undefined;
  private saveName: string = '';
  private savePath: string = '';
  private saveBytes: number = 0;

  aboutToAppear(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.saveDir = context.filesDir;
  }

  // ---------- 发送端（decimen-sender.html 调用） ----------

  onFileReady(name: string, size: number): void {
    hilog.info(DOMAIN, TAG, 'file ready: %{public}s (%{public}d)', name, size);
  }

  onError(message: string): void {
    hilog.warn(DOMAIN, TAG, 'error: %{public}s', message);
  }

  async pickFile(): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const pickerInst = new picker.DocumentViewPicker();
      const uris: string[] = await pickerInst.select(options);
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const size: number = stat.size;
      if (size === 0) {
        fs.closeSync(file);
        this.controllers[0].runJavaScript('alert("该文件为空")');
        return;
      }
      const buf = new ArrayBuffer(size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const name: string = this.nameFromUri(uri);
      const base64 = this.arrayBufferToBase64(buf);
      this.controllers[0].runJavaScript(
        `window.__onFilePicked && window.__onFilePicked(${JSON.stringify(name)}, ${size}, "${base64}")`
      );
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'pick file failed: %{public}s', String(err));
    }
  }

  arrayBufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return binary;
  }

  nameFromUri(uri: string): string {
    const q: number = uri.indexOf('?');
    const clean: string = q >= 0 ? uri.substring(0, q) : uri;
    const parts: string[] = clean.split('/');
    const last: string = parts.length > 0 ? parts[parts.length - 1] : '';
    return last === '' ? 'file.bin' : last;
  }

  // ---------- 接收端（decimen-receiver.html 调用） ----------

  onBeginSave(name: string): void {
    try {
      this.saveName = name;
      this.savePath = `${this.saveDir}/decimen-received.bin`;
      const file: fs.File = fs.openSync(this.savePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      this.saveFile = file;
      this.saveBytes = 0;
      hilog.info(DOMAIN, TAG, 'save begin %{public}s -> %{public}s', name, this.savePath);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'save begin failed: %{public}s', String(err));
    }
  }

  onAppendChunk(base64: string): void {
    const file: fs.File | undefined = this.saveFile;
    if (file === undefined) {
      hilog.warn(DOMAIN, TAG, 'append chunk dropped: saveFile not opened');
      return;
    }
    try {
      const helper: util.Base64Helper = new util.Base64Helper();
      const decoded: ArrayBuffer = helper.decodeSync(base64);
      // decodeSync 返回的原生缓冲区直接写入会报 "Illegal write buffer"，
      // 经 new Uint8Array 重新包装后再取 .buffer（华为开发者论坛验证的 workaround）
      const buf: ArrayBuffer = new Uint8Array(decoded).buffer as ArrayBuffer;
      const n: number = fs.writeSync(file.fd, buf);
      this.saveBytes += n;
      if (this.saveBytes % (4 * 1024 * 1024) < n) {
        hilog.info(DOMAIN, TAG, 'saved %{public}d bytes so far', this.saveBytes);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'save chunk failed: %{public}s', String(err));
    }
  }

  async onEndSave(): Promise<void> {
    const file: fs.File | undefined = this.saveFile;
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'save close failed: %{public}s', String(err));
      }
      this.saveFile = undefined;
    }
    const srcPath: string = this.savePath;
    if (srcPath === '') {
      return;
    }
    hilog.info(DOMAIN, TAG, 'save end, wrote %{public}d bytes, copying from %{public}s', this.saveBytes, srcPath);
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [this.saveName];
      const savePicker = new picker.DocumentViewPicker();
      const uris: string[] = await savePicker.save(options);
      if (uris.length > 0) {
        // 对 picker 返回的 URI 用 copyFileSync 在部分版本会 ENOENT，
        // 改为 openSync(uri) + 流式拷贝（官方文档推荐的 URI 写入方式）
        const dest: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        const src: fs.File = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
        const chunk: ArrayBuffer = new ArrayBuffer(1024 * 1024);
        let got: number = fs.readSync(src.fd, chunk);
        while (got > 0) {
          fs.writeSync(dest.fd, chunk.slice(0, got));
          got = fs.readSync(src.fd, chunk);
        }
        fs.closeSync(src);
        fs.closeSync(dest);
        hilog.info(DOMAIN, TAG, 'saved to %{public}s (%{public}d bytes)', uris[0], this.saveBytes);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'save picker failed: %{public}s', String(err));
    }
  }

  async onCopyText(text: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      hilog.info(DOMAIN, TAG, 'copied text %{public}d chars', text.length);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'copy failed: %{public}s', String(err));
    }
  }

  // ---------- 返回键：优先回退当前 Tab 的 Web 历史 ----------

  onBackPress(): boolean {
    const controller = this.controllers[this.currentTabIndex];
    if (controller.accessStep(-1)) {
      controller.backward();
      return true;
    }
    return false;
  }

  // ---------- 打开系统浏览器 ----------

  private openExternalBrowser(url: string): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    context.startAbility(want).then((data) => {
      hilog.info(DOMAIN, TAG, 'open browser: %{public}s', JSON.stringify(data));
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'open browser failed: %{public}d %{public}s', err.code, err.message);
    });
  }

  // ---------- Web 组件 ----------

  @Builder
  WebContentBuilder(item: MenuItem, index: number) {
    Web({ src: item.url, controller: this.controllers[index] })
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .javaScriptProxy({
        object: this.host,
        name: 'decimenHost',
        methodList: ['onFileReady', 'onError', 'pickFile', 'beginSave', 'appendChunk', 'endSave', 'copyText'],
        controller: this.controllers[index],
      })
      .onLoadIntercept((event) => {
        if (event) {
          const url: string = event.data.getRequestUrl();
          // 站外 http(s) 链接交给系统浏览器打开；本地 rawfile 页面正常放行
          if (url.startsWith('http://') || url.startsWith('https://')) {
            this.openExternalBrowser(url);
            return true;
          }
        }
        return false;
      })
      .onPermissionRequest((event) => {
        if (event) {
          event.request.grant(event.request.getAccessibleResource());
        }
      })
      .onControllerAttached(() => {
        // 相机权限只需申请一次（接收端使用）
        if (this.permissionRequested) {
          return;
        }
        this.permissionRequested = true;
        const perms: Array<Permissions> = ['ohos.permission.CAMERA'];
        try {
          abilityAccessCtrl.createAtManager().requestPermissionsFromUser(
            this.getUIContext().getHostContext() as common.UIAbilityContext, perms)
            .then((data) => {
              hilog.info(DOMAIN, TAG, 'permission result: %{public}s', JSON.stringify(data));
            })
            .catch((err: BusinessError) => {
              hilog.warn(DOMAIN, TAG, 'permission request failed: %{public}s', err.message);
            });
        } catch (error) {
          hilog.warn(DOMAIN, TAG, 'permission request exception: %{public}s', JSON.stringify(error));
        }
      })
      .onPageEnd(() => {
        hilog.info(DOMAIN, TAG, 'page %{public}d loaded', index);
      })
      .onErrorReceive((event) => {
        if (event) {
          hilog.warn(DOMAIN, TAG, 'web error: %{public}s', event.error.getErrorInfo());
        }
      })
      .onConsole((event) => {
        if (event) {
          hilog.info(DOMAIN, TAG, 'web: %{public}s', event.message.getMessage());
        }
        return true;
      })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .databaseAccess(true)
      .copyOptions(CopyOptions.LocalDevice)
      .horizontalScrollBarAccess(false)
      .verticalScrollBarAccess(false)
      .darkMode(WebDarkMode.Auto)
      .backgroundColor(Color.Transparent)
  }

  build() {
    HdsNavigation() {
      Stack() {
        HdsTabs({ controller: this.tabsController }) {
          ForEach(MENU_CONFIG, (item: MenuItem, index: number) => {
            TabContent() {
              this.WebContentBuilder(item, index)
            }
            .width('100%')
            .height('100%')
            .tabBar(new BottomTabBarStyle({
              normal: item.symbolGlyph,
              selected: item.symbolGlyph1
            }, item.label)
              .labelStyle({ selectedColor: ACCENT_COLOR }))
          }, (item: MenuItem, index: number) => index.toString())
        }
        .scrollable(false) // 禁用左右滑动切换，仅通过底部导航栏点击切换
        .barOverlap(true)
        .vertical(false)
        .barPosition(BarPosition.End)
        .animationDuration(0)
        .barHeight(56)
        .barFloatingStyle({
          barBottomMargin: 28,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.IMMERSIVE,
            materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
          },
          // 光感颜色跟随 H5 主题（HTML --accent）
          lightColor: ACCENT_COLOR
        })
        .onChange((index: number) => {
          this.currentTabIndex = index;
          const controller = this.controllers[index];
          if (controller) {
            try {
              controller.runJavaScript("window.__playEntrance && window.__playEntrance()");
            } catch (e) {
              // ignore
            }
          }
        })
      }
      .width('100%')
      .height('100%')
    }
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
