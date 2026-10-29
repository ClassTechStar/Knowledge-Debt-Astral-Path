import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Breakpoint, LayoutSize } from '../common/Breakpoint';
import { StoreService } from '../service/StoreService';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate');
    AppStorage.setOrCreate('layoutSize', LayoutSize.SM as number);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, TAG, 'onWindowStageCreate');
    // 存储初始化要拿到 UIAbilityContext，放在这里最稳
    StoreService.init(this.context).catch((err: Error) => {
      hilog.error(0x0000, TAG, `store init failed: ${err.message}`);
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, TAG, `loadContent failed: ${JSON.stringify(err)}`);
        return;
      }
      // 监听窗口尺寸变化：折叠屏展开/折叠、分屏、自由窗口都会触发
      const win = windowStage.getMainWindowSync();
      EntryAbility.applyLayout(win);
      win.on('windowSizeChange', () => {
        EntryAbility.applyLayout(win);
      });
    });
  }

  private static applyLayout(win: window.Window): void {
    const rect = win.getWindowProperties().windowRect;
    const widthVp = px2vp(rect.width);
    const size = Breakpoint.of(widthVp) as number;
    AppStorage.setOrCreate('layoutSize', size);
    AppStorage.setOrCreate('windowWidthVp', widthVp);
    hilog.info(0x0000, TAG, `window ${widthVp}vp -> layoutSize ${size}`);
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'onWindowStageDestroy');
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'onDestroy');
  }
}
