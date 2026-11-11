# 鸿蒙端子树约定（src/AstralPath.Harmony/）

根 `AGENTS.md` 的规则在此全部适用；本文件只补本子树的增量。改动结构、构建方式、
图谱/设计系统、设备验证脚本后，**同提交**更新本文件。

## 构建与安装

```powershell
# 构建（一次性）
$env:OHOS_SDK_HOME = 'C:\Users\18948\AppData\Local\OpenHarmony\Sdk\26.0.0'
$env:HOS_SDK_HOME  = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$env:PATH += ';C:\Program Files\Huawei\DevEco Studio\tools\node'
C:\Users\18948\Downloads\command-line-tools\bin\hvigorw.bat assembleHap --mode module -p product=default --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`。

## 一键手势回归（识网缩放 / 拖拽 / 点选）

```powershell
powershell -File scripts/verify-graph-gestures.ps1 [-Boot]
```
10 项断言，断言源是 `GraphCanvas` 每次 `draw()` 打的 hilog 状态行
（`canvas/origin/scale/off/selected/nodes`）。改图谱交互后必须跑；无设备时 `-Boot` 会按
「软件渲染 + 无窗口」配方自动拉起模拟器。

## 设计系统（改视觉必读）

- `common/Theme.ets` 是视觉真源：色板 / 圆角 / 字号 / 间距逐项对应 Web 版 CSS 变量。
  **不要在页面里硬编码色值**。
- `components/UiKit.ets` 是结构化组件库（`PageHeaderView` / `PanelView` / `CardView` /
  `BtnView` / `BadgeView` / `StatusView` / `BarView` / `StatView`）。页面只组合积木，
  保证三端视觉一致。
- `components/GraphCanvas.ets` 自持变换（`screen = world*viewScale + offset`）与命中判定；
  视图控件（100% / 适应）在页面上渲染并通过 `GraphCtrl` 调用，**不压在画布上**——
  压在画布上会吞掉节点点击（实测踩过）。

## ArkUI 实测踩过的坑（别再踩）

| 现象 | 原因 | 正确做法 |
|---|---|---|
| 属性 `scale` 报与基类冲突 | `CustomComponent` 已有同名成员 | 改名 `viewScale` / `voffX` / `voffY` |
| 全局 `@Builder` 不接受 `@Builder` 参数 | 该语法只在 struct 的 `@BuilderParam` 上成立 | 用 `@Component struct` + `@BuilderParam` |
| `Row.flexWrap` 不存在 | `flexWrap` 是 `Flex` 的 | `Flex({ wrap: FlexWrap.Wrap })` |
| `Flex.space({x,y})` 报类型错 | 间距写在构造参数，键名是 `main`/`cross` | `Flex({ wrap, space: { main: 8, cross: 8 } })` |
| `linearGradient` 的 colors 类型错 | 它要 `[颜色, 偏移]` 对，不是两个颜色 | `[[色1, 0], [色2, 1]]` |
| `globalPosition.x` 赋给 number 报错 | 它是 `Length`（number \| string） | 包一层 `Number(...)` |
| 双击缩放没反应 | 阈值 280ms 短于系统双击间隔（约 300ms） | 450ms |

## 模拟器验证配方（今天普遍崩溃，照做才稳）

1. `config.ini` 追加 `hw.gpu.enabled=no` + `hw.gpu.mode=swiftshader`（消除 EGL 崩溃）
2. 启动带 `-noWindow`
3. **只用一份 hdc**：SDK 与 DevEco 各自带 `hdc.exe`，两份守护进程互抢会报
   `need connect-key`。本子树的脚本统一用 DevEco 那份。
4. 装新包后必须 `aa force-stop` 再启动——否则进程跑旧代码，新控件的点击会落到画布上。
5. 布局回流会移动画布原点（点选节点后详情面板变高），脚本里按文本定位按钮、不要硬算坐标。
