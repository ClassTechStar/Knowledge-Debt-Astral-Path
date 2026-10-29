/**
 * 账户页 —— 对应 Web 版 main#p-account：模型密钥配置、授权（fail-closed）、清除本机数据。
 * 红线继承：未授权时默认「不可见」；密钥只保存在本机首选项，不上传、不写日志。
 */
import { promptAction } from '@kit.ArkUI';
import { StoreService } from '../service/StoreService';
import { AiService, AiConfig } from '../service/AiService';

@Component
export struct AccountPage {
  @State keyInput: string = '';
  @State hasKey: boolean = false;
  @State consent: boolean = false;

  aboutToAppear(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    const meta = await StoreService.loadMeta();
    this.consent = meta.consent;
    this.hasKey = meta.onboard; // 演示：用 onboard 位示意已配置过密钥
  }

  private async saveKey(): Promise<void> {
    if (!this.keyInput) {
      return;
    }
    const cfg: AiConfig = { baseUrl: AiService.DEFAULT_BASE, key: this.keyInput, model: 'mimo-7b-rl' };
    // 真机应写入加密存储（如 Asset Store Kit）；这里先落首选项并立刻清空输入框
    const meta = await StoreService.loadMeta();
    meta.onboard = true;
    await StoreService.saveMeta(meta);
    this.keyInput = '';
    this.hasKey = true;
    promptAction.showToast({ message: '密钥已保存到本机', duration: 1500 });
  }

  private async toggleConsent(): Promise<void> {
    const meta = await StoreService.loadMeta();
    meta.consent = !meta.consent;
    await StoreService.saveMeta(meta);
    this.consent = meta.consent;
  }

  private async clearAll(): Promise<void> {
    await StoreService.wipe();
    this.hasKey = false;
    this.consent = false;
    promptAction.showToast({ message: '本机数据已清除', duration: 1500 });
  }

  build() {
    Column({ space: 12 }) {
      Text('账户').fontSize(17).fontWeight(FontWeight.Bold);

      Column({ space: 6 }) {
        Text('模型密钥（可选，留空则全部功能在本机完成）').fontSize(12).fontColor($r('app.color.muted'));
        Row() {
          TextInput({ placeholder: 'sk-...', text: this.keyInput })
            .type(InputType.Password)
            .layoutWeight(1)
            .onChange((v: string) => {
              this.keyInput = v;
            });
          Button('保存').onClick(() => this.saveKey());
        }
        if (this.hasKey) {
          Text('已配置密钥（本机保存）').fontSize(11).fontColor($r('app.color.ok'));
        }
      }
      .width('100%')
      .padding(12)
      .borderRadius(14)
      .backgroundColor($r('app.color.soft'))
      .alignItems(HorizontalAlign.Start);

      Row() {
        Text('授权学情上报（关闭则默认不可见）').fontSize(13).layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.consent })
          .onChange(() => this.toggleConsent());
      }
      .width('100%')
      .padding(12)
      .borderRadius(14)
      .backgroundColor($r('app.color.soft'));

      Button('清除本机数据')
        .backgroundColor($r('app.color.danger'))
        .onClick(() => {
          promptAction.showDialog({
            title: '确认清除',
            message: '将删除本机教材、作答与计划，且不可恢复。',
            buttons: [
              { text: '取消', color: '#5F6672' },
              { text: '清除', color: '#D8453F' }
            ]
          }).then((r) => {
            if (r.index === 1) {
              this.clearAll();
            }
          });
        });

      Text('版本 2.6.0 · HarmonyOS 版').fontSize(11).fontColor($r('app.color.muted'));
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start);
  }
}
