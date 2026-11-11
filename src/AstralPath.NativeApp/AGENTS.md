# 原生安卓端子树约定（src/AstralPath.NativeApp/）

根 `AGENTS.md` 的规则在此全部适用；本文件只补本子树的增量。改动 UI 层、图谱交互、
测试探针、Gradle 配置后，**同提交**更新本文件。

## 工程形态（先认清，别按直觉改）

- UI 是**经典 View 体系程序化构建**（`LinearLayout` / `TextView` / 自绘 `View`），
  **不是 Jetpack Compose**。依赖只有 `core-ktx` + `appcompat`，`settings.gradle.kts`
  注释也写明「View 体系 + 自绘图谱」。要 Compose 化请另立任务，别在顺手改 UI 时混进来。
- `service/`、`data/` 是业务逻辑与数据结构（`KgService` / `FormulaService` / `StoreService` …），
  与鸿蒙端同构。**UI 改动不碰业务层**；业务层确有 bug 时单独立项并跑单测。
- 版本号**不在 `build.gradle.kts` 写死**——由根 `Directory.Build.props` 的 `<Version>` 统一供给，
  `scripts/verify_release_version.py` 会校验 `versionName` 与基线一致。

## 构建与测试

```powershell
$env:JAVA_HOME = 'C:\Program Files\Huawei\DevEco Studio\jbr'
C:\Gradle\bin\gradle.bat :app:assembleDebug                # 应用包
C:\Gradle\bin\gradle.bat :app:assembleDebugAndroidTest     # 仪器化测试包
C:\Gradle\bin\gradle.bat test                              # 单元测试（CoreLogicTest）
C:\Gradle\bin\gradle.bat :app:connectedDebugAndroidTest `
  "-Pandroid.testInstrumentationRunnerArguments.class=com.astralpath.nativeapp.GraphGestureTest"
```

**注意：本工程没有 `gradlew` wrapper**，用本机 `C:\Gradle\bin\gradle.bat`（9.7.1）直跑。
补 wrapper 是可选改进，不是本次范围。

## 图谱交互与测试探针（ui/GraphView.kt）

- 变换模型与鸿蒙/Web 一致：`screen = world*scale + offset`；命中半径 `20/scale`；
  双击放大 ×1.6（阈值 450ms，见鸿蒙子树同样条目）；双指捏合以手势中心为定点。
- **视图控件（100% / 适应）在 `PagesCore.kt` 画布上方渲染**，不压在画布上——
  压在画布上会吞掉节点点击（与鸿蒙端同一类问题）。
- `GraphView` 暴露 `internal` 测试探针（`debugScale` / `debugOffX` / `debugOffY` /
  `debugSelected` / `debugNodeCount` / `debugNodeScreenPos` / `debugFirstNodeId` /
  `resetZoom` / `fitView`）与 `contentDescription = "astralpath-graph"`，供 `androidTest` 同模块访问。
  这些是**测试用接缝**，不进公开 API，别在业务代码里调它们。

## 仪器化测试（app/src/androidTest/.../GraphGestureTest.kt）

与鸿蒙 `scripts/verify-graph-gestures.ps1` 等价，5+1 个用例（拖拽 / 双击 / **双指捏合** /
点选 / 100% 重置 / 适应复位）。这里能注入双指事件（`UiAutomation.injectInputEvent`），
是鸿蒙 uitest 做不到的覆盖。断言直接读 View 探针，不做截图比对；无图谱数据时用
`Assume.assumeTrue` 跳过（skipped 不算失败）。

## UI 层职责划分

| 文件 | 职责 |
|---|---|
| `ui/Ui.kt` | 设计 token + 组件库（`panel` / `card` / `btn` / `badge` / `status` / `bar` / `stat`） |
| `ui/GraphView.kt` | 自绘图谱：布局 + 变换 + 命中 + 渲染 |
| `ui/PagesCore.kt` / `PagesAgent.kt` / `PagesDebt.kt` / `PagesMore.kt` | 各页面组装 |
| `MainActivity.kt` | 导航壳（Web 胶囊导航样式） |

改视觉先改 `Ui.kt` 的 token，不要在页面里散写色值。
