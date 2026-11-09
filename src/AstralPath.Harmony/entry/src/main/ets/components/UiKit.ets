/**
 * UI 组件库 —— 复刻 Web 版的 .panel / .btn / .badge / .status / .bar / .card / .stat。
 * struct + @BuilderParam 承载内容插槽（全局 @Builder 不支持 @Builder 参数）。
 */
import { Theme } from '../common/Theme';

/** 页面标题区（Web .page-h） */
@Component
export struct PageHeaderView {
  @Prop title: string = '';
  @Prop hint: string = '';

  build() {
    Column({ space: 8 }) {
      Text(this.title)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.INK)
        .width('100%')
      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(Theme.FS_HINT)
          .fontColor(Theme.MUTED)
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 14 })
  }
}

/** 面板（Web .panel） */
@Component
export struct PanelView {
  @Prop title: string = '';
  @Prop hint: string = '';
  @BuilderParam content: () => void = this.blank;

  @Builder
  blank() {
  }

  build() {
    Column({ space: 8 }) {
      if (this.title.length > 0) {
        Text(this.title)
          .fontSize(Theme.FS_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.INK)
          .width('100%')
      }
      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(Theme.FS_HINT)
          .fontColor(Theme.MUTED)
          .width('100%')
      }
      this.content()
    }
    .width('100%')
    .padding(Theme.PAD_PANEL)
    .borderRadius(Theme.R_G)
    .backgroundColor(Theme.SURFACE)
    .border({ width: 1, color: Theme.RULE })
    .margin({ bottom: Theme.GAP_PANEL })
    .alignItems(HorizontalAlign.Start)
  }
}

/** 卡片（Web .card） */
@Component
export struct CardView {
  @Prop selected: boolean = false;
  @BuilderParam content: () => void = this.blank;

  @Builder
  blank() {
  }

  build() {
    Column({ space: 6 }) {
      this.content()
    }
    .width('100%')
    .padding({ top: 16, bottom: 16, left: Theme.PAD_CARD, right: Theme.PAD_CARD })
    .borderRadius(Theme.R_G)
    .backgroundColor(Theme.SURFACE)
    .border({ width: this.selected ? 2 : 1, color: this.selected ? Theme.PRIMARY : Theme.RULE })
    .margin({ top: 5, bottom: 5 })
    .alignItems(HorizontalAlign.Start)
  }
}

/** 按钮（Web .btn / .primary / .danger / .quiet） */
@Component
export struct BtnView {
  @Prop label: string = '';
  @Prop kind: string = 'plain';
  click: () => void = () => {};

  build() {
    Button(this.label)
      .fontSize(Theme.FS_BTN)
      .fontColor(this.kind === 'primary' ? Color.White : (this.kind === 'danger' ? Theme.DANGER : Theme.INK))
      .backgroundColor(this.kind === 'primary' ? Theme.PRIMARY :
        (this.kind === 'quiet' ? Color.Transparent : Theme.SURFACE))
      .borderRadius(Theme.R_C)
      .border({
        width: this.kind === 'quiet' ? 0 : 1,
        color: this.kind === 'danger' ? Theme.DANGER : Theme.RULE
      })
      .height(44)
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.click();
      })
  }
}

/** 徽标（Web .badge / .err / .warn） */
@Component
export struct BadgeView {
  @Prop text: string = '';
  @Prop kind: string = 'ok';

  build() {
    Text(this.text)
      .fontSize(Theme.FS_BADGE)
      .fontColor(this.kind === 'err' ? Theme.ERR_INK : (this.kind === 'warn' ? Theme.WARN_INK : Theme.OK_INK))
      .backgroundColor(this.kind === 'err' ? Theme.ERR_BG : (this.kind === 'warn' ? Theme.WARN_BG : Theme.OK_BG))
      .borderRadius(Theme.R_PILL)
      .padding({ top: 2, bottom: 2, left: 8, right: 8 })
      .margin({ right: 8, bottom: 4 })
  }
}

/** 状态条（Web .status / .ok / .err / .warn） */
@Component
export struct StatusView {
  @Prop text: string = '';
  @Prop kind: string = 'plain';

  build() {
    Text(this.text)
      .fontSize(Theme.FS_HINT)
      .fontColor(this.kind === 'ok' ? Theme.OK_DEEP : (this.kind === 'err' ? Theme.ERR_TEXT :
        (this.kind === 'warn' ? Theme.WARN_INK : Theme.MUTED)))
      .backgroundColor(this.kind === 'warn' ? Theme.WARN_BG : Theme.SOFT)
      .borderRadius(4)
      .border({
        width: 3,
        color: this.kind === 'ok' ? Theme.OK : (this.kind === 'err' ? Theme.DANGER :
          (this.kind === 'warn' ? Theme.WARN : Theme.STRONG))
      })
      .padding(Theme.PAD_CARD)
      .width('100%')
      .margin({ top: 12 })
  }
}

/** 进度条（Web .bar > i 渐变） */
@Component
export struct BarView {
  @Prop ratio: number = 0;

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(10)
        .borderRadius(99)
        .backgroundColor(Theme.SOFT)
      Row()
        .width(`${Math.max(0, Math.min(1, this.ratio)) * 100}%`)
        .height(10)
        .borderRadius(99)
        .linearGradient({
          angle: 90,
          colors: [[Theme.PRIMARY, 0], [Theme.PRIMARY_SOFT, 1]]
        })
    }
    .width('100%')
    .height(10)
    .margin({ top: 8, bottom: 8 })
  }
}

/** 统计格（Web .stat：小标题 + 大数字） */
@Component
export struct StatView {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Column({ space: 2 }) {
      Text(this.label)
        .fontSize(Theme.FS_HINT)
        .fontColor(Theme.MUTED)
      Text(this.value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.INK)
    }
    .alignItems(HorizontalAlign.Start)
    .padding(Theme.PAD_CARD)
    .backgroundColor(Theme.SURFACE)
    .borderRadius(Theme.R_C)
    .border({ width: 1, color: Theme.RULE })
    .layoutWeight(1)
    .margin({ right: 8, bottom: 8 })
  }
}
