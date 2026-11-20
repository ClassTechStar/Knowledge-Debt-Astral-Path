/**
 * 账户页 —— 对应 Web 版 main#p-account：模型密钥配置、授权（fail-closed）、清除本机数据。
 * 红线继承：未授权时默认「不可见」；密钥只保存在本机首选项，不上传、不写日志。
 */
import { promptAction } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { StoreService, AiCfg } from '../service/StoreService';
import { AiService, AiConfig } from '../service/AiService';
import { Theme } from '../common/Theme';
import { PageHeaderView, PanelView, BtnView, BadgeView, StatusView } from '../components/UiKit';

@Component
export struct AccountPage {
  @State keyInput: string = '';
  @State hasKey: boolean = false;
  @State consent: boolean = false;
  private cfg: AiCfg = { baseUrl: AiService.DEFAULT_BASE, key: '', model: 'mimo-7b-rl' };

  aboutToAppear(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    const meta = await StoreService.loadMeta();
    this.consent = meta.consent;
    this.cfg = await StoreService.loadAiCfg();
    if (!this.cfg.baseUrl) {
      this.cfg.baseUrl = AiService.DEFAULT_BASE;
    }
    this.hasKey = !!this.cfg.key;
  }

  private async saveKey(): Promise<void> {
    if (!this.keyInput) {
      return;
    }
    // 真机建议改用 Asset Store Kit 做加密存储；这里先落本机首选项，不上传、不进日志
    const next: AiCfg = {
      baseUrl: this.cfg.baseUrl || AiService.DEFAULT_BASE,
      key: this.keyInput,
      model: this.cfg.model || 'mimo-7b-rl'
    };
    await StoreService.saveAiCfg(next);
    this.cfg = next;
    this.keyInput = '';
    this.hasKey = true;
    promptAction.showToast({ message: '密钥已保存到本机', duration: 1500 });
  }

  private async clearKey(): Promise<void> {
    await StoreService.saveAiCfg({ baseUrl: AiService.DEFAULT_BASE, key: '', model: 'mimo-7b-rl' });
    this.cfg = { baseUrl: AiService.DEFAULT_BASE, key: '', model: 'mimo-7b-rl' };
    this.hasKey = false;
    promptAction.showToast({ message: '已移除密钥', duration: 1500 });
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
    Scroll() {
      Column({ space: 0 }) {
        PageHeaderView({
          title: '账户',
          hint: '模型密钥、学情授权与数据清理；密钥只保存在本机'
        })

        PanelView({
          title: '模型密钥',
          hint: '可选，留空则全部功能在本机完成；密钥只保存在本机首选项，不上传、不写日志'
        }) {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              TextInput({ placeholder: 'sk-...', text: this.keyInput })
                .type(InputType.Password)
                .layoutWeight(1)
                .height(44)
                .borderRadius(Theme.R_C)
                .backgroundColor(Theme.FIELD)
                .onChange((v: string) => {
                  this.keyInput = v;
                })
              BtnView({
                label: '保存',
                kind: 'primary',
                click: () => this.saveKey()
              })
            }
            .width('100%')

            if (this.hasKey) {
              Flex({ wrap: FlexWrap.Wrap }) {
                BadgeView({ text: '已配置密钥', kind: 'ok' })
                BadgeView({ text: '本机保存', kind: 'ok' })
                BtnView({
                  label: '移除',
                  kind: 'danger',
                  click: () => this.clearKey()
                })
              }
              .width('100%')
              .margin({ top: 4 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        PanelView({
          title: '学情授权',
          hint: '关闭则默认不可见（fail-closed），教师侧看不到聚合视图'
        }) {
          Row({ space: 8 }) {
            Text('授权学情上报')
              .fontSize(Theme.FS_BODY)
              .fontColor(Theme.INK)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.consent })
              .onChange(() => this.toggleConsent());
          }
          .width('100%')

          if (this.consent) {
            StatusView({ text: '已授权：教师侧可查看 k-匿名聚合视图，看不到个体明细。', kind: 'ok' })
          } else {
            StatusView({ text: '未授权：教师侧默认不可见，所有学情只留在本机。', kind: 'warn' })
          }
        }

        PanelView({
          title: '数据管理',
          hint: '清除后不可恢复'
        }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            BtnView({
              label: '清除本机数据',
              kind: 'danger',
              click: () => {
                promptAction.showDialog({
                  title: '确认清除',
                  message: '将删除本机教材、作答与计划，且不可恢复。',
                  buttons: [
                    { text: '取消', color: Theme.MUTED },
                    { text: '清除', color: Theme.DANGER }
                  ]
                }).then((r) => {
                  if (r.index === 1) {
                    this.clearAll();
                  }
                });
              }
            })
          }
          .width('100%')
        }

        StatusView({
          text: '版本 2.6.0，HarmonyOS 原生版。解析、构图、识网、今日任务与修复计划，全部在本机完成',
          kind: 'plain'
        })

        Blank().height(12)

        Column({ space: 8 }) {
          Text('更新').fontSize(Theme.FS_TITLE).fontWeight(FontWeight.Bold)
          Text('更新源：GitHub Releases。本端只检查并提示，安装包请到发布页下载。')
            .fontSize(Theme.FS_HINT)
            .fontColor(Theme.MUTED)
          BtnView({
            label: '检查更新',
            kind: 'plain',
            click: () => {
              const req = http.createHttp();
              req.request('https://api.github.com/repos/ClassTechStar/Knowledge-Debt-Astral-Path/releases/latest',
                { method: http.RequestMethod.GET, header: { Accept: 'application/vnd.github+json' },
                  expectDataType: http.HttpDataType.STRING, connectTimeout: 10000, readTimeout: 10000 },
                (err, data) => {
                  if (err || data.responseCode !== 200) {
                    promptAction.showToast({ message: '暂时连不上 GitHub（离线或网络受限）', duration: 2000 });
                    return;
                  }
                  try {
                    const j: Record<string, Object> = JSON.parse(data.result as string) as Record<string, Object>;
                    const tag: string = (j.tag_name as string ?? '').replace(/^v/i, '');
                    const url: string = (j.html_url as string ?? '') || 'https://github.com/ClassTechStar/Knowledge-Debt-Astral-Path/releases/latest';
                    promptAction.showDialog({
                      title: tag.length > 0 ? ('发现新版本 v' + tag) : '暂无法解析版本',
                      message: tag.length > 0
                        ? ('请到 GitHub Releases 页下载 HarmonyOS 包（当前 2.6.0）。\\n' + url)
                        : '请稍后再试。',
                      buttons: [{ text: '知道了', color: Theme.MUTED }]
                    }).catch(() => {});
                  } catch (e) {
                    promptAction.showToast({ message: '版本解析失败', duration: 2000 });
                  }
                });
            }
          })
        }
      }
      .width('100%')
      .padding(Theme.PAD_PANEL)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.CANVAS)
  }
}
