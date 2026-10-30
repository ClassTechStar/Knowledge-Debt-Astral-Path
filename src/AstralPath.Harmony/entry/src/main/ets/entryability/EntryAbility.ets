import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Breakpoint, LayoutSize } from '../common/Breakpoint';
import { StoreService } from '../service/StoreService';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, TAG, 'onCreate');
    AppStorage.setOrCreate('layoutSize', LayoutSize.SM as number);
    AppStorage.setOrCreate('foldable', false);
    AppStorage.setOrCreate('foldStatus', 0);
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
      const win = windowStage.getMainWindowSync();

      // 先取折叠状态再算首次布局：Mate X7 展开态只有 707vp，单看宽度会误判成单栏，
      // 顺序反了会先渲染一帧单栏再跳双栏（能肉眼看到闪）。
      try {
        const foldable = display.isFoldable();
        AppStorage.setOrCreate('foldable', foldable);
        AppStorage.setOrCreate('foldStatus', display.getFoldStatus() as number);
        hilog.info(0x0000, TAG, `foldable=${foldable} foldStatus=${display.getFoldStatus()}`);
        if (foldable) {
          display.on('foldStatusChange', (st: display.FoldStatus) => {
            hilog.info(0x0000, TAG, `foldStatusChange -> ${st}`);
            AppStorage.setOrCreate('foldStatus', st as number);
            EntryAbility.applyLayout(windowStage.getMainWindowSync());
          });
        }
      } catch (e) {
        hilog.warn(0x0000, TAG, `fold api unavailable: ${(e as Error).message}`);
      }

      EntryAbility.applyLayout(win);
      win.on('windowSizeChange', () => {
        EntryAbility.applyLayout(win);
      });
    });
  }

  private static applyLayout(win: window.Window): void {
    const rect = win.getWindowProperties().windowRect;
    const widthVp = px2vp(rect.width);
    const foldable = (AppStorage.get<boolean>('foldable') ?? false) as boolean;
    const foldStatus = (AppStorage.get<number>('foldStatus') ?? 0) as number;
    const size = Breakpoint.ofFold(widthVp, foldable, foldStatus) as number;
    AppStorage.setOrCreate('layoutSize', size);
    AppStorage.setOrCreate('windowWidthVp', widthVp);
    hilog.info(0x0000, TAG, `window ${widthVp}vp fold=${foldable}/${foldStatus} -> layoutSize ${size}`);
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, TAG, 'onWindowStageDestroy');
  }

  onDestroy(): void {
    hilog.info(0x0000, TAG, 'onDestroy');
  }
}
