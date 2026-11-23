# 下载/复制 OCR WASM 引擎离线资源到 deploy\monolith-web\ocr-engine\（后台运行）
# 资源落点就是脚本所在目录，tessdata 默认取仓库 tools\tessdata（可用 ASTRALPATH_TESSDATA 覆盖）
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$dir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$tessdata = if ($env:ASTRALPATH_TESSDATA) { $env:ASTRALPATH_TESSDATA } else { Join-Path $repoRoot 'tools\tessdata' }
New-Item -ItemType Directory -Force $dir | Out-Null
$log = Join-Path $dir 'download.log'
"start $(Get-Date -Format o)" | Set-Content -Path $log -Encoding UTF8
$files = @(
    @('tesseract.min.js', 'https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/tesseract.min.js'),
    @('worker.min.js', 'https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/worker.min.js'),
    @('tesseract-core-simd-lstm.wasm.js', 'https://cdn.jsdelivr.net/npm/tesseract.js-core@6.0.0/tesseract-core-simd-lstm.wasm.js'),
    @('tesseract-core-lstm.wasm.js', 'https://cdn.jsdelivr.net/npm/tesseract.js-core@6.0.0/tesseract-core-lstm.wasm.js'),
    @('pdf.min.js', 'https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/legacy/build/pdf.min.js'),
    @('pdf.worker.min.js', 'https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/legacy/build/pdf.worker.min.js')
)
foreach ($f in $files) {
    $out = Join-Path $dir $f[0]
    Invoke-WebRequest -Uri $f[1] -OutFile $out -UseBasicParsing
    "OK $($f[0]) $((New-Object IO.FileInfo($out)).Length) bytes" | Add-Content -Path $log -Encoding UTF8
}
Copy-Item (Join-Path $tessdata 'chi_sim.traineddata') (Join-Path $dir 'chi_sim.traineddata') -Force
Copy-Item (Join-Path $tessdata 'eng.traineddata') (Join-Path $dir 'eng.traineddata') -Force
"traineddata: chi_sim $((New-Object IO.FileInfo((Join-Path $dir 'chi_sim.traineddata'))).Length) / eng $((New-Object IO.FileInfo((Join-Path $dir 'eng.traineddata'))).Length) bytes" | Add-Content -Path $log -Encoding UTF8
"done $(Get-Date -Format o)" | Add-Content -Path $log -Encoding UTF8
