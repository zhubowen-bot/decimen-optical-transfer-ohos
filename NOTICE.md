# NOTICE

This directory contains the HarmonyOS port of **Decimen Optical Transfer**
(https://github.com/bashalarmistalt/decimen-optical-transfer), which is
licensed under AGPL-3.0-or-later (see the repository LICENSE).

The port incorporates the following third-party components, ported to ArkTS:

## qrcode (QR symbol generator)

- Source: https://github.com/soldair/node-qrcode
- Copyright (c) 2011 Ryan Day, Copyright (c) 2009 Kazuhiko Arase
- License: MIT
- Used: `entry/src/main/ets/qr/QrEncoder.ets` (byte-mode core port)

## jsQR (QR symbol decoder)

- Source: https://github.com/cozmo/jsQR
- Copyright (c) 2017 David Shim
- License: MIT
- Used: `entry/src/main/ets/qr/QrDecoder.ets` (decoder port; the Kanji
  shift-JIS table is intentionally not included)

Both ports are covered by the MIT license reproduced below:

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
