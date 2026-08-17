/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { abilityAccessCtrl, AbilityConstant, ConfigurationConstant, Permissions, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { initGzipTempDir } from '../common/GzipWrap';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private cameraPermissionRequested: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      initGzipTempDir(this.context.filesDir);
      // 应用强制浅色模式（H5 页面均为浅色暖调主题）
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      this.applySystemBarTheme();
      this.requestCameraPermissionOnce();
    });
  }

  // 系统状态栏/导航栏跟随 H5 主题（rawfile 页面 :root --bg: #f5f4f3）
  private applySystemBarTheme(): void {
    try {
      window.getLastWindow(this.context).then((mainWindow: window.Window) => {
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#F5F4F3',
          statusBarContentColor: '#FF000000',
          navigationBarColor: '#F5F4F3',
          navigationBarContentColor: '#FF000000'
        });
      }).catch((e: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to get the main window. Cause: %{public}s', JSON.stringify(e));
      });
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Failed to apply system bar theme. Cause: %{public}s', JSON.stringify(e));
    }
  }

  // 首次进入应用即申请相机权限；loadContent 回调与 onForeground 都可能先触发，
  // 用标志位保证只发起一次，若系统调用失败则允许另一个时机重试。
  private requestCameraPermissionOnce(): void {
    if (this.cameraPermissionRequested) {
      return;
    }
    this.cameraPermissionRequested = true;
    try {
      const permissions: Array<Permissions> = ['ohos.permission.CAMERA'];
      abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context, permissions)
        .then((data) => {
          hilog.info(DOMAIN, 'testTag', 'camera permission result: %{public}s', JSON.stringify(data));
        })
        .catch((err: BusinessError) => {
          this.cameraPermissionRequested = false;
          hilog.error(DOMAIN, 'testTag', 'camera permission request failed: %{public}s', err.message);
        });
    } catch (e) {
      this.cameraPermissionRequested = false;
      hilog.error(DOMAIN, 'testTag', 'camera permission request exception: %{public}s', JSON.stringify(e));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 首次进入前台即申请相机权限；不要在 WebView onControllerAttached 等过早时机申请
    this.requestCameraPermissionOnce();
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}