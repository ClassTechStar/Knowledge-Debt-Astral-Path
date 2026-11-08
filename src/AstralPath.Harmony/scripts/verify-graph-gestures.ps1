# ==============================================================
# verify-graph-gestures.ps1
# 识网（GraphCanvas）手势自动化验证：
#   拖拽平移 / 双击缩放 / 点按选中 / 详情联动 / 适应复位
#
# 断言来源：GraphCanvas 每次 draw() 打的 hilog 行
#   GRAPHCANVAS: canvas WxH scale=S off=X,Y selected=ID nodes=id@x,y ...
# 双指捏合与双击放大走同一 zoomAt() 代码路径，本脚本用 doubleClick
# 验证缩放数学；两指捏合本体需多指注入（uitest 不支持），脚本会
# 另做「代码路径存在」静态检查并如实标注。
#
# 用法：
#   powershell -File scripts/verify-graph-gestures.ps1 [-Boot] [-Hdc <path>] [-Hap <path>]
#   -Boot  : 模拟器未连接时自动拉起（软件渲染 + 无窗口配方）
# 返回码：0 全过 / 1 有失败
# ==============================================================
param(
    [switch]$Boot,
    [string]$Hdc = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [string]$Hap = '',
    [int]$Density = 3125   # X7 density=500 → vp=px/(500/160)=px/3.125；此处放大 1000 存整数
)

$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if (-not $Hap) { $Hap = Join-Path $repo 'src\AstralPath.Harmony\entry\build\default\outputs\default\entry-default-unsigned.hap' }
$d = $Density / 1000.0          # px → vp 除数
$results = @()

function Say([string]$m) { Write-Host $m }
function Add-Result([string]$name, [bool]$ok, [string]$detail) {
    $script:results += [pscustomobject]@{ Test = $name; Pass = $ok; Detail = $detail }
    $tag = 'FAIL'
    if ($ok) { $tag = 'PASS' }
    Say ("{0} {1} - {2}" -f $tag, $name, $detail)
}

function Invoke-Hdc([string[]]$argv) { & $Hdc @argv 2>&1 }

function Get-State {
    $line = (Invoke-Hdc @('shell', 'hilog -x -T GRAPHCANVAS') | Select-Object -Last 1) -join ''
    $st = @{ raw = $line; scale = $null; offx = 0; offy = 0; selected = ''; nodes = @{}; origin = @(0, 0) }
    if ($line -match 'origin=(-?\d+),(-?\d+)') {
        $st.origin = @([int]$Matches[1], [int]$Matches[2])
    }
    if ($line -match 'scale=([\d.]+) off=(-?\d+),(-?\d+) selected=([A-Za-z0-9]*)') {
        $st.scale = [double]$Matches[1]; $st.offx = [int]$Matches[2]; $st.offy = [int]$Matches[3]
        $st.selected = $Matches[4]
    }
    if ($line -match 'nodes=(.+)$') {
        foreach ($tok in $Matches[1].Split(' ')) {
            if ($tok -match '^([A-Za-z0-9]+)@(\d+),(\d+)$') {
                $st.nodes[$Matches[1]] = @([int]$Matches[2], [int]$Matches[3])
            }
        }
    }
    return $st
}

function Click-ByText([string]$label) {
    # 用 layout dump 的绝对 bounds 点击，避免画布位移导致坐标失效
    Invoke-Hdc @('shell', 'uitest dumpLayout -p /data/local/tmp/gl_btn.json') | Out-Null
    Invoke-Hdc @('file', 'recv', '/data/local/tmp/gl_btn.json', "$env:TEMP\gl_btn.json") | Out-Null
    $raw = Get-Content "$env:TEMP\gl_btn.json" -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($raw, '\{[^{}]*\}')) {
        $seg = $m.Value
        if ($seg -notmatch '"text":"' + [regex]::Escape($label) + '"') { continue }
        if ($seg -notmatch '"bounds":"\[(\d+),(\d+)\]\[(\d+),(\d+)\]"') { continue }
        $x = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
        $y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
        Invoke-Hdc @('shell', "uitest uiInput click $x $y") | Out-Null
        return $true
    }
    return $false
}

function Get-CanvasBox {
    # 每次点击前都要重取：点选节点后详情面板高度变化，画布原点会移动
    $st = Get-State
    $ox = [int]([double]$st.origin[0] * $d)
    $oy = [int]([double]$st.origin[1] * $d)
    $w = 484; $h = 378
    if ($st.raw -match 'canvas (\d+)x(\d+)') { $w = [int]$Matches[1]; $h = [int]$Matches[2] }
    return @($ox, $oy, [int]($w * $d), [int]($h * $d), $w, $h)
}

function Get-CanvasOrigin {
    Invoke-Hdc @('shell', 'uitest dumpLayout -p /data/local/tmp/gv_layout.json') | Out-Null
    Invoke-Hdc @('file', 'recv', '/data/local/tmp/gv_layout.json', "$env:TEMP\gv_layout.json") | Out-Null
    $j = Get-Content "$env:TEMP\gv_layout.json" -Raw -Encoding UTF8 | ConvertFrom-Json
    $b = $null
    $walk = {
        param($n)
        if ($n.attributes -and $n.attributes.type -eq 'Canvas' -and $n.attributes.bounds) {
            $script:b = $n.attributes.bounds
        }
        if ($n.children) { foreach ($c in $n.children) { & $walk $c } }
    }
    & $walk $j
    if ($b -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
        return @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4])
    }
    return $null
}

# ---------- 0. 设备 ----------
$connected = ((Invoke-Hdc @('list', 'targets')) -join '') -match '5555'
if (-not $connected -and $Boot) {
    Say '模拟器未连接，按软件渲染 + 无窗口配方拉起…'
    taskkill /F /IM Emulator.exe 2>$null | Out-Null
    Start-Sleep -Seconds 2
    Start-Process -FilePath 'C:\Users\18948\Downloads\command-line-tools\bin\Emulator.bat' `
        -ArgumentList '-start', '"Mate X7"', '-noWindow' `
        -WorkingDirectory 'C:\Users\18948\Downloads\command-line-tools\bin' | Out-Null
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 8
        if (((Invoke-Hdc @('list', 'targets')) -join '') -match '5555') { $connected = $true; Say "已连接（第 $i 次）"; break }
    }
}
if (-not $connected) { Say '设备未连接，退出'; exit 1 }

# ---------- 1. 装包并进入识网 ----------
Invoke-Hdc @('install', '-r', $Hap) | Select-Object -Last 1
# 必须先强杀：装了新包但进程还在跑旧代码时，点新控件会落到画布上（踩过）
Invoke-Hdc @('shell', 'aa force-stop com.astralpath.harmony') | Out-Null
Start-Sleep -Seconds 1
Invoke-Hdc @('shell', 'aa start -a EntryAbility -b com.astralpath.harmony') | Out-Null
Start-Sleep -Seconds 6
Invoke-Hdc @('shell', 'uitest uiInput click 105 421') | Out-Null   # 顶部胶囊导航第 3 项（识网）
Start-Sleep -Seconds 3

$base = Get-State
if (-not $base.scale) { Add-Result '基线读取' $false '未读到 GRAPHCANVAS 状态行'; $base | Out-Null }
else { Add-Result '基线读取' $true ("scale={0} off={1},{2}" -f $base.scale, $base.offx, $base.offy) }

# 画布原点与尺寸直接取自 hilog（GraphCanvas 每次 draw 都会打印）
$cl = [int]($base.origin[0] * $d); $ct = [int]($base.origin[1] * $d)
$cw = [int](484 * $d); $ch = [int](378 * $d)   # 兜底；下面按实际宽高解析
if ($base.raw -match 'canvas (\d+)x(\d+)') { $cw = [int]([int]$Matches[1] * $d); $ch = [int]([int]$Matches[2] * $d) }
Add-Result '画布定位' ($cw -gt 100 -and $ch -gt 100) ("origin(vp)={0} 尺寸 {1}x{2}px" -f ($base.origin -join ','), $cw, $ch)

# 画布中心（设备 px）
$ccx = $cl + [int]($cw / 2); $ccy = $ct + [int]($ch / 2)

# ---------- 2. 拖拽平移：swipe 中心 → 中心偏 (+120px,+80px) ----------
$before = Get-State
Invoke-Hdc @('shell', "uitest uiInput swipe $ccx $ccy $($ccx + 120) $($ccy + 80) 300") | Out-Null
Start-Sleep -Seconds 1
$after = Get-State
$dx = $after.offx - $before.offx; $dy = $after.offy - $before.offy
# vp 变化量 ≈ px/d（swipe 120px → ~38vp）
$expectX = 120 / $d; $expectY = 80 / $d
$okPan = [math]::Abs($dx - $expectX) -le 8 -and [math]::Abs($dy - $expectY) -le 8 `
        -and [math]::Abs($after.scale - $before.scale) -lt 0.001
Add-Result '拖拽平移' $okPan ("off 变化 {0},{1}（期望 ≈{2:f0},{3:f0}），scale 保持 {4}" -f $dx, $dy, $expectX, $expectY, $after.scale)

# ---------- 3. 双击放大（走 zoomAt，与捏合同一路径）----------
$s1 = Get-State
Invoke-Hdc @('shell', "uitest uiInput doubleClick $ccx $ccy") | Out-Null
Start-Sleep -Seconds 1
$s2 = Get-State
$okZoom1 = $s2.scale -gt $s1.scale * 1.4 -and $s2.scale -lt $s1.scale * 1.8
Add-Result '双击放大 ×1.6' $okZoom1 ("scale {0} → {1}" -f $s1.scale, $s2.scale)

Invoke-Hdc @('shell', "uitest uiInput doubleClick $ccx $ccy") | Out-Null
Start-Sleep -Seconds 1
$s3 = Get-State
$okZoom2 = $s3.scale -gt $s2.scale * 1.4
Add-Result '连续双击再放大' $okZoom2 ("scale {0} → {1}" -f $s2.scale, $s3.scale)

# ---------- 4. 点按选中（取一个节点坐标换算设备 px）----------
$nodeId = $null; $nx = 0; $ny = 0
foreach ($k in $s3.nodes.Keys) { $nodeId = $k; $nx = $s3.nodes[$k][0]; $ny = $s3.nodes[$k][1]; break }
if ($nodeId) {
    # 日志节点坐标是画布局部 vp；设备 px = 画布原点px + vp×pxPerVp
    $tx = $cl + [int]($nx * $d); $ty = $ct + [int]($ny * $d)
    Invoke-Hdc @('shell', "uitest uiInput click $tx $ty") | Out-Null
    Start-Sleep -Seconds 1
    $sel = Get-State
    Add-Result '点按选中' ($sel.selected -ne '') ("点击 $nodeId @($tx,$ty) → selected=$($sel.selected)")
    # 详情联动
    Invoke-Hdc @('shell', 'uitest dumpLayout -p /data/local/tmp/gv_after.json') | Out-Null
    Invoke-Hdc @('file', 'recv', '/data/local/tmp/gv_after.json', "$env:TEMP\gv_after.json") | Out-Null
    $txt = (Select-String -Path "$env:TEMP\gv_after.json" -Pattern '先修|难度|后续' -AllMatches |
        ForEach-Object { $_.Matches.Value } | Select-Object -Unique) -join ','
    Add-Result '详情联动' ([bool]$txt) ("详情面板关键词：$txt")
} else {
    Add-Result '点按选中' $false '日志里没有节点坐标'
}

# ---------- 4.5 重置到 100%（新控件）----------
# 按文本定位点击（dump 出来的绝对 bounds，不受布局回流影响）
$hit100 = Click-ByText '100%'
Start-Sleep -Seconds 1
$s100 = Get-State
$ok100 = [math]::Abs($s100.scale - 1.0) -lt 0.001
$tag100 = '失败'
if ($hit100) { $tag100 = '成功' }
Add-Result '重置到 100%' ($ok100 -and $hit100) ("点击 100%（定位{0}）→ scale={1}（期望 1.0）" -f $tag100, $s100.scale)

# ---------- 5. 适应复位 ----------
# 「适应」同样按文本定位
$hitFit = Click-ByText '适应'
Start-Sleep -Seconds 1
$fit = Get-State
$okFit = [math]::Abs($fit.scale - $base.scale) -lt 0.02 -and
         [math]::Abs($fit.offx - $base.offx) -le 6 -and
         [math]::Abs($fit.offy - $base.offy) -le 6
Add-Result '适应复位' ($okFit -and $hitFit) ("scale/off 回到基线：{0} {1},{2}（基线 {3} {4},{5}）" -f `
    $fit.scale, $fit.offx, $fit.offy, $base.scale, $base.offx, $base.offy)

# ---------- 6. 双指捏合的静态检查（uitest 无多指注入）----------
$src = Get-Content (Join-Path $repo 'src\AstralPath.Harmony\entry\src\main\ets\components\GraphCanvas.ets') -Raw
$okPinch = ($src -match 'pinchBaseDist') -and ($src -match 'zoomAt\(mx, my, target / this\.viewScale\)')
Add-Result '捏合代码路径（静态）' $okPinch '双指分支存在且与双击共用 zoomAt()；手势本体需多指注入设备'

# ---------- 汇总 ----------
Say ''
Say '================ 结果汇总 ================'
$results | Format-Table -AutoSize | Out-String | Write-Host
$fail = @($results | Where-Object { -not $_.Pass }).Count
Say ("合计 {0} 项，失败 {1} 项" -f $results.Count, $fail)
exit $(if ($fail -gt 0) { 1 } else { 0 })
