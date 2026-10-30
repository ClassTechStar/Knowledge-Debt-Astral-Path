/**
 * 主壳 —— 对应单文件版的 header + nav.pills + main#p-* 结构：
 * 折叠态（SM/MD）：顶部标题栏 + 顶部胶囊导航 + 单栏内容
 * 展开态（LG，Mate X7 展开 / 平板）：左侧固定导航 + 右侧双栏内容（列表 + 详情）
 * 页面切换沿用 Web 版的「当前页 id + 方向动画」语义，这里用 ArkUI 转场代替 CSS 动画。
 */
import { LayoutSize, PAGE_ORDER, PAGE_LABEL } from '../common/Breakpoint';
import { HomePage } from './HomePage';
import { MaterialsPage } from './MaterialsPage';
import { GraphPage } from './GraphPage';
import { PapersPage } from './PapersPage';
import { DebtPage } from './DebtPage';
import { TodayPage } from './TodayPage';
import { AgentPage } from './AgentPage';
import { ProfilePage } from './ProfilePage';
import { TeacherPage } from './TeacherPage';
import { AccountPage } from './AccountPage';
import { HelpPanel } from '../components/HelpPanel';

@Entry
@Component
struct Index {
  @StorageLink('layoutSize') layoutSize: number = LayoutSize.SM;
  // 必须是 StorageLink：首页/藏书阁的跳转按钮是写 AppStorage('currentPage') 的，
  // 用 @State 收不到，点了没反应
  @StorageLink('currentPage') current: string = 'home';
  @State showHelp: boolean = false;
  @State userName: string = '王小明（有债）';

  aboutToAppear(): void {
    AppStorage.setOrCreate('currentPage', 'home');
  }

  @Builder
  navPills() {
    Row() {
      ForEach(PAGE_ORDER, (p: string) => {
        Text(PAGE_LABEL[p])
          .fontSize(13)
          .fontWeight(this.current === p ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.current === p ? $r('app.color.brand') : $r('app.color.muted'))
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(14)
          .backgroundColor(this.current === p ? $r('app.color.brand_soft') : Color.Transparent)
          .onClick(() => {
            this.current = p;
            AppStorage.setOrCreate('currentPage', p);
          });
      }, (p: string) => p);
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
  }

  @Builder
  navSide() {
    Column() {
      ForEach(PAGE_ORDER, (p: string) => {
        Row() {
          Text(PAGE_LABEL[p])
            .fontSize(14)
            .fontWeight(this.current === p ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.current === p ? $r('app.color.brand') : $r('app.color.ink'))
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius(12)
        .backgroundColor(this.current === p ? $r('app.color.brand_soft') : Color.Transparent)
        .onClick(() => {
          this.current = p;
          AppStorage.setOrCreate('currentPage', p);
        });
      }, (p: string) => p);
    }
    .width(140)
    .height('100%')
    .padding(6)
    .backgroundColor($r('app.color.soft'));
  }

  build() {
    Row() {
      if (this.layoutSize === LayoutSize.LG) {
        this.navSide();
      }
      Column() {
        // 顶部栏：标题 + 用户 + 模式标识（对应 Web 版 header 右侧）
        Row() {
          Text('知债：星穹学途')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.strong'));
          Blank();
          Button('？')
            .fontSize(12)
            .backgroundColor($r('app.color.soft'))
            .fontColor($r('app.color.ink'))
            .width(28)
            .height(24)
            .onClick(() => {
              this.showHelp = true;
            });
          Text(this.userName)
            .fontSize(12)
            .fontColor($r('app.color.muted'));
          Text($r('app.string.mode_local'))
            .fontSize(11)
            .fontColor($r('app.color.muted'))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor($r('app.color.soft'));
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 6 });

        if (this.layoutSize !== LayoutSize.LG) {
          this.navPills();
        }

        // 内容区：展开态限制最大宽度并居中，折叠态铺满
        Column() {
          if (this.showHelp) {
            HelpPanel({ onClose: () => {
              this.showHelp = false;
            } })
              .width('100%')
              .height('100%');
          } else if (this.current === 'home') {
            HomePage()
          } else if (this.current === 'materials') {
            MaterialsPage()
          } else if (this.current === 'graph') {
            GraphPage()
          } else if (this.current === 'papers') {
            PapersPage()
          } else if (this.current === 'debt') {
            DebtPage()
          } else if (this.current === 'today') {
            TodayPage()
          } else if (this.current === 'agent') {
            AgentPage()
          } else if (this.current === 'profile') {
            ProfilePage()
          } else if (this.current === 'teacher') {
            TeacherPage()
          } else {
            AccountPage()
          }
        }
        .width('100%')
        .layoutWeight(1)
        .constraintSize({
          maxWidth: this.layoutSize === LayoutSize.LG ? 960 : '100%'
        })
        .alignItems(HorizontalAlign.Start);
      }
      // 注意：有侧栏时不能写 width('100%')，那会把 140vp 的侧栏算进去导致右侧溢出；
      // 用 layoutWeight(1) 吃满剩余宽度。
      .layoutWeight(1)
      .height('100%');
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'));
  }
}
