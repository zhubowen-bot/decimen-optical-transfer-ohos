# LiveQRTransfer（鸿蒙版 · Decimen 光传输）

> 用屏幕和摄像头传文件——不需要网络、不需要蓝牙、不需要数据线，数据以**光**为介质。
> 本项目是开源项目 [Decimen Optical Transfer](https://github.com/bashalarmistalt/decimen-optical-transfer)（© 2026 Evan Crawley，AGPL-3.0-or-later）的 HarmonyOS 移植版，H5 页面源自其 v0.4.0 构建。

## ⚠️ 关于当前架构（嵌套 H5）与鸿蒙原生引擎适配情况

当前版本采用**嵌套H5架构**：界面与收发引擎运行在 WebView 加载的 H5 页面中（`rawfile/` 下的 sender / receiver / about），鸿蒙原生侧通过 `decimenHost` 桥接管文件选择、保存、剪贴板、相机权限等系统能力。

**鸿蒙原生引擎适配情况**：仓库内已完整移植了 ArkTS 原生协议引擎（喷泉码编解码、QR 符号生成/识别、DCF2 帧协议、gzip、SHA-256 等，见 `entry/src/main/ets/`），但原生引擎目前**尚不完善**——性能与稳定性还未达到 H5 引擎（经原项目充分打磨、含 WASM 加速解码）的水准。为优先保证用户体验，当前以 H5 引擎为收发主力，原生引擎持续演进，后续版本将逐步迁移替换。

**HarmonyOS 6.0+（API 23+） · Stage 模型 · ArkTS**

---

## 目录

- [功能特性](#功能特性)
- [界面与使用](#界面与使用)
- [架构实现](#架构实现)
- [传输协议细节](#传输协议细节)
- [参数说明](#参数说明)
- [目录结构](#目录结构)
- [构建与运行](#构建与运行)
- [多端兼容](#多端兼容)
- [常见问题](#常见问题)
- [版权与许可](#版权与许可)

---

## 功能特性

- **纯光传输，全程离线**：发送端将文件编码为高速滚动的动态二维码流（最高 60 帧/秒），接收端用摄像头扫描解码还原。不经过无线信号，无服务器、无账号、无流量。
- **喷泉码容错**：基于 Luby Transform（LT）喷泉码，接收端只需按任意顺序收集约 **K × 1.15** 个分块即可完整还原文件——丢帧、模糊、错过只损失时间，永不损失正确性，无需重传。
- **文件与文本双模式**：
  - 文件：单文件最大 **64 MB**，保留文件名与 MIME 类型；
  - 文本片段：最大 **4 MB**，接收后可一键复制。
- **自动压缩与完整性校验**：发送前按需 gzip 压缩；接收后先做 **SHA-256 校验**再交付，校验失败会明确报错而不是给出损坏文件。
- **多二维码布局**：同一屏幕可同时显示 1 / 2 / 4 / 6 个二维码，速度成倍提升。
- **可调参数**：发送帧率、每帧字节数、纠错级别（L/M/Q/H）、显示大小、采集分辨率、解码线程数全部可调，适配不同设备与光线环境。
- **原生体验**：底部沉浸光感导航栏（HdsTabs），文件选择、保存、剪贴板、相机权限均由鸿蒙原生能力接管；站外链接自动转系统浏览器打开。
- **强制浅色主题**：应用固定浅色模式，系统状态栏/导航栏与 H5 主题色（`#fafaf7` / `#d97706`）融合。

---

## 界面与使用

底部导航三个标签页，均为内嵌 WebView 加载的 H5 页面（`entry/src/main/resources/rawfile/`）：

| 标签  | 页面                      | 说明                       |
| --- | ----------------------- | ------------------------ |
| 发送  | `decimen-sender.html`   | 选择文件或粘贴文本 → 屏幕播放动态二维码流   |
| 接收  | `decimen-receiver.html` | 启动摄像头扫描发送端屏幕 → 自动恢复文件/文本 |
| 关于  | `about.html`            | 版本信息、多端兼容与参数使用说明、常见问题    |

**快速开始**：

1. 一台设备打开「发送」，选择文件（或粘贴文本）；
2. 另一台设备打开「接收」，点击「启动摄像头」，对准发送端屏幕；
3. 保持距离约 20–40 厘米、亮度调高、避免反光，传输完成后自动保存/复制。

---

## 架构实现

```
┌─────────────────────────────────────────────────────────┐
│                    Index.ets（@Entry）                   │
│  HdsNavigation + HdsTabs（UIDesignKit 沉浸光感导航栏）    │
│  3 个 Tab = 3 个独立 WebView（各持 WebviewController）   │
└──────────────────────┬──────────────────────────────────┘
                       │ decimenHost（javaScriptProxy 桥）
┌──────────────────────▼──────────────────────────────────┐
│                原生宿主（ArkTS）                          │
│  · 文件选择（DocumentViewPicker） / 保存（save picker）   │
│  · 剪贴板（pasteboard） / 相机权限（CAMERA）             │
│  · 外部 http(s) 链接 → 系统浏览器（onLoadIntercept）      │
└──────────────────────┬──────────────────────────────────┘
                       │ WebView 加载 rawfile H5
┌──────────────────────▼──────────────────────────────────┐
│        H5 页面（rawfile，CSP 严格锁定，无外网依赖）       │
│  decimen-sender.html / decimen-receiver.html / about.html│
└──────────────────────────────────────────────────────────┘
```

### 分层说明

1. **原生壳（ArkTS）**
   
   - `Index.ets`：页面骨架。`HdsTabs` 底部导航，`barFloatingStyle` 使用 `MaterialType.IMMERSIVE` 沉浸光感材质，光感颜色 `lightColor` 跟随 H5 主题；选中 Tab 图标与文字（`labelStyle`）为琥珀色 `#d97706`；`ignoreLayoutSafeArea` 让内容延伸到底部安全区，Web 侧通过 `env(safe-area-inset-bottom)` 预留导航栏空间。
   - `TransferHost`：暴露给网页的桥对象 `decimenHost`（`onFileReady` / `pickFile` / `beginSave` / `appendChunk` / `endSave` / `copyText` / `onError`）。网页通过 `runJavaScript` 双向调用。
   - `EntryAbility.ets`：强制浅色模式（`COLOR_MODE_LIGHT`），并通过 `setWindowSystemBarProperties` 将状态栏/导航栏设为 H5 背景色 `#FAFAF7`（内容色深色）。

2. **H5 页面（rawfile）**
   
   - 自带完整 Web 版收发引擎（动态二维码渲染、zxing-cpp WASM 解码、喷泉码编解码），功能与 decimen.app 网页版一致；
   - 所有页面 CSP 严格限制（`default-src 'none'`、无外链、`img-src` 仅本地/data/blob），离线可用；
   - 页面与系统栏融合：`viewport-fit=cover` + 安全区 padding。

3. **原生协议引擎（ArkTS，仓库内完整移植，当前版本 UI 以 H5 为主，原生引擎已就绪）**
   
   - `common/Protocol.ets`：帧格式打包/解析（20 字节帧头）、FNV-1a 校验、文件名清洗、gzip 容器（DCF2 魔数）；
   - `common/Fountain.ets`：LT 喷泉码编码器/解码器（splitmix32 随机源）；
   - `qr/QrEncoder.ets`：`node-qrcode` 字节模式核心的逐字移植（MIT，Ryan Day / Kazuhiko Arase），版本显式选择 + 固定掩码，保证与 Web 端符号一致；
   - `qr/QrDecoder.ets`：`jsQR` 解码器移植（MIT，David Shim）；
   - `send/`（SendEngine / SendTask）、`receive/`（ReceiveEngine / DecodePipeline / DecodeTask / CameraCapture）、`common/Progress.ets`（进度/ETA 估算）、`common/NoSignal.ets`（无信号提示时序）、`common/GzipWrap.ets`（zlib 包装）、`common/CryptoWrap.ets`（SHA-256）。

---

## 传输协议细节

**文件容器（DCF2）**：

```
┌────────┬──────┬─────────┬─────────┬──────────┬──────────┬──────────┬──────────┐
│ DCF2   │标志位 │文件名长度│ MIME长度 │ 原始大小 │ 传输大小 │ SHA-256  │ 文件名+MIME+数据 │
│ 4 B    │ 1 B  │ 2 B     │ 2 B     │ 4 B     │ 4 B     │ 32 B     │ 变长     │
└────────┴──────┴─────────┴─────────┴──────────┴──────────┴──────────┴──────────┘
```

- 标志位指示数据是否 gzip 压缩（`≥768 B` 且压缩有收益时启用）；
- 图片/音频/压缩包等已压缩内容跳过二次压缩。

**帧头（20 字节，每帧自带，顺序无关）**：

```
┌─────────┬──────┬───────┬─────────┬───────────┬────────────┬──────────────┐
│ 魔数 0xD1 │ 版本 │ 会话ID │ 序号seq │ K(总块数) │ 块长blockLen│ 载荷FNV-1a    │
│ 1 B      │ 1 B  │ 2 B   │ 4 B    │ 2 B      │ 2 B       │ 4 B          │
└─────────┴──────┴───────┴─────────┴───────────┴────────────┴──────────────┘
```

- 每帧载荷 = 第 `seq` 块与后续块按喷泉编码 XOR 的结果；
- 帧率 × 块长 × 布局数 = 实际吞吐；项目记录：桌面→手机约 418 KB/s，手机→手机约 199 KB/s。

---

## 参数说明

### 发送端（传输设置）

| 参数    | 范围              | 默认   | 建议                              |
| ----- | --------------- | ---- | ------------------------------- |
| 发送帧率  | 10–60 帧/秒       | 60   | 越快越快，但接收端解码压力大；频繁丢帧时降到 30/20    |
| 每帧字节数 | 500–2953 B      | 2953 | 越大越快，二维码越密；弱光/手持抖动时调小           |
| 纠错级别  | L / M / Q / H   | L    | L 最快最怕遮挡；画面常被遮挡时用 H（约容忍 30% 污损） |
| 布局    | 1 / 2 / 4 / 6 码 | 1    | 多码成倍提速但单码变小；手机之间 1–2，固定设备可 4–6  |
| 显示大小  | 300–1200 px     | 900  | 越大越好扫                           |

### 接收端（接收设置）

| 参数   | 范围       | 默认   | 建议                |
| ---- | -------- | ---- | ----------------- |
| 采集宽度 | 960–3840 | 1280 | 越高越准越耗电；老设备降到 960 |
| 采集帧率 | 30 / 60  | 60   | 建议与发送端一致          |
| 解码线程 | 1–6      | 自动   | 越多越快越耗电           |

---

## 目录结构

```
decimen-optical-transfer-ohos/
├── AppScope/                     # 应用级资源（图标分层图、应用名）
├── entry/
│   └── src/main/
│       ├── ets/                  # ArkTS 原生层
│       │   ├── entryability/     # EntryAbility（浅色模式、系统栏主题）
│       │   ├── pages/            # Index.ets（导航壳 + WebView + 原生桥）
│       │   ├── common/           # 协议、喷泉码、进度、gzip、SHA-256、无信号提示
│       │   ├── qr/               # QR 编码器/解码器（qrcode / jsQR 移植）
│       │   ├── send/             # 原生发送引擎
│       │   └── receive/          # 原生接收引擎（摄像头采集 + 解码流水线）
│       └── resources/
│           ├── base/media/       # 应用图标、启动图标（decimen 素材）
│           └── rawfile/          # H5 页面（sender / receiver / about）+ 图标
├── hvigor/                       # 构建配置（modelVersion 6.1.1）
├── build-profile.json5           # 工程签名与 SDK 配置
├── NOTICE.md                     # 第三方组件声明
└── LICENSE                       # AGPL-3.0-or-later
```

---

## 构建与运行

1. 使用 **DevEco Studio 6.1.1+**（对应 modelVersion 6.1.1 / API 23）打开工程根目录；
2. 工程已配置调试签名（`build-profile.json5` → `signingConfigs`），也可在 File → Project Structure → Signing Configs 中重新配置；
3. 连接 HarmonyOS 设备（手机/平板/电脑，HarmonyOS 6.0+），点击 Run 构建安装；
4. 首次进入会申请相机权限（接收端使用）。

> 首次构建需要联网下载 SDK 组件；`hvigor` 目录为构建工具配置，勿删。

---

## 多端兼容

| 端                           | 获取方式                                              |
| --------------------------- | ------------------------------------------------- |
| 鸿蒙手机 / 平板 / 电脑              | 应用市场 AppGallery 搜索 **LiveQRTransfer**（本应用）        |
| 电脑（Windows / macOS / Linux） | 浏览器打开 [decimen.app](https://decimen.app)，可"保存为应用" |
| 安卓 / iOS                    | 浏览器打开 [decimen.app](https://decimen.app)，"添加到主屏幕" |

发送端与接收端可任意组合，协议互认：鸿蒙 ↔ 网页 ↔ 任意 Decimen 兼容设备。

---

## 常见问题

- **收不到信号**：面对面放置、发送端亮度调最高、距离 20–40 厘米、避免反光；发送端页面保持前台（切后台会停滞）；点击二维码可放大；调低帧率/字节数/布局数。
- **传输很慢**：提高帧率/每帧字节数，用多二维码布局；缩短距离、放稳设备；确认解码线程充足。
- **频繁校验失败或卡住**：降低每帧字节数、纠错级别选 H、增大显示大小；固定设备（对焦抖动是最大敌人）。
- **摄像头打不开**：检查系统相机权限是否授予。
- **提示文件超限**：单文件 ≤ 64 MB（浏览器/引擎限制），先压缩再传。

---

## 版权与许可

本项目基于 **Decimen Optical Transfer**（© 2026 Evan Crawley）二次开发，遵循 **AGPL-3.0-or-later**（见 [LICENSE](LICENSE)）。

**第三方组件**（详见 [NOTICE.md](NOTICE.md)）：

- `qrcode`（QR 符号生成，MIT）—— © 2011 Ryan Day / © 2009 Kazuhiko Arase，移植：`entry/src/main/ets/qr/QrEncoder.ets`
- `jsQR`（QR 符号解码，MIT）—— © 2017 David Shim，移植：`entry/src/main/ets/qr/QrDecoder.ets`
- H5 页面内嵌引擎（MIT 部分）—— © 2026 Steve Dakh；Emscripten（zxing-cpp WASM）
- UIDesignKit 沉浸光感导航栏框架参考自 BowenAPP-Web（开源项目）

本应用图标与品牌素材：decimen 图标（© 2026，本仓库资源）。

**许可要点**：本软件为自由软件，可自由使用、修改与分发，但**任何衍生作品必须同样以 AGPL-3.0-or-later 开源**；使用本软件提供的服务（包括网络服务）时，需向用户提供对应源码。

---

## 致谢

- [Decimen Optical Transfer](https://github.com/bashalarmistalt/decimen-optical-transfer) —— 原项目与传输协议设计
- [node-qrcode](https://github.com/soldair/node-qrcode) / [jsQR](https://github.com/cozmo/jsQR) —— QR 编解码
- [BowenAPP-Web](https://github.com/) —— 沉浸光感导航栏框架参考
