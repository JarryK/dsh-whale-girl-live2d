# DSH 网页版 · 一键部署（Windows / PowerShell）
# ⚠️ 说明：作者手上没有 Windows 机器，这个脚本按通用 PowerShell + npm 行为写成，**尚未在真机验证**。
#    有问题请开 issue：https://github.com/Andersen216/dsh-whale-girl-live2d/issues
# 用法（下载整个仓库的固定版本，在仓库里的 PowerShell 运行）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\dsh-web-deploy.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\dsh-web-deploy.ps1 -WithPet
# 版本锁：DSH 版本和桌宠插件来源都写在同目录的 deploy.lock.json（说明见 dsh-web-deploy.sh 文件头）。
param([switch]$WithPet, [switch]$Doctor, [int]$Port = 0)

$ErrorActionPreference = 'Stop'
$Repo = 'Andersen216/dsh-whale-girl-live2d'
$IssueUrl = "https://github.com/$Repo/issues"
$State = Join-Path $env:USERPROFILE '.dsh\.web-deploy.json'

function Say($m) { Write-Host $m }

# ① 环境
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Say "❌ 没找到 Node.js。请到 https://nodejs.org 装 LTS（≥20）"; exit 10 }
$maj = [int](& node -p "process.versions.node.split('.')[0]")
if ($maj -lt 20) { Say "❌ Node 版本过低（当前 $(& node -v)）。需要 ≥20：https://nodejs.org"; exit 10 }
Say "  ✓ Node $(& node -v)"

# 版本锁：读不到 / 没锁死就不往下走
$lockFile = Join-Path "$PSScriptRoot" 'deploy.lock.json'
if (-not $PSScriptRoot -or -not (Test-Path $lockFile)) { Say "❌ 没找到版本锁 ${lockFile}。请下载整个仓库后在仓库里运行。"; exit 11 }
try { $lock = Get-Content -Raw -Encoding UTF8 $lockFile | ConvertFrom-Json } catch { $lock = $null }
$dshVersion = "$($lock.dsh)"
$petPlugin = "$($lock.plugin)"
if ($dshVersion -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$') { Say "❌ 版本锁里的 dsh 不是确切版本号：'${dshVersion}'"; exit 11 }
if ($petPlugin -cne 'local' -and $petPlugin -cnotmatch '#[0-9a-f]{40}$' -and
    $petPlugin -cnotmatch '^(@[a-z0-9._-]+/)?[a-z0-9._-]+@[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$') {
  Say "❌ 版本锁里的 plugin 没锁到具体版本：'${petPlugin}'（用 local、git 地址#完整 40 位 commit、或 包名@确切版本）"; exit 11
}
Say "  ✓ 版本锁：dsh ${dshVersion} · 插件 ${petPlugin}"

# ② 复用已装的 dsh，否则用 npm exec 免安装运行
#    注意：Windows 全局 bin 在 %APPDATA%\npm，新装的可能还不在当前 PATH 里
$dshCmd = (Get-Command dsh -ErrorAction SilentlyContinue)
$globalDsh = Join-Path $env:APPDATA 'npm\dsh.cmd'
if ($dshCmd) { $run = @('dsh'); Say "  ✓ 已有 dsh（复用）" }
elseif (Test-Path $globalDsh) { $run = @($globalDsh); Say "  ✓ 找到全局 dsh（%APPDATA%\npm）" }
else { $run = @('npm', 'exec', '--yes', '--registry=https://registry.npmmirror.com', "--package=@deepseek-ai/dsh@${dshVersion}", '--', 'dsh'); Say "  ℹ️  未装 dsh —— 将用 npm exec 免安装运行 dsh@${dshVersion}（首次约 60MB）" }
if ($run[0] -ne 'npm') {
  $haveDsh = '?'
  try { $haveDsh = "$(& $run[0] -V 2>$null)".Trim() } catch {}
  if ($haveDsh -ne $dshVersion) { Say "  ⚠️  已装 dsh ${haveDsh} 和版本锁（${dshVersion}）不一致 —— 复用的是你已装的版本" }
}

if ($Doctor) {
  Say "`n体检完毕：环境没问题。"
  if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) { Say "  ℹ️  没装 pnpm —— 只有装插件（-WithPet）才需要：npm i -g pnpm" }
  exit 0
}

# ③ 启动（--port 0 = 让系统挑空闲端口，官方支持）
$log = Join-Path $env:TEMP ("dsh-web-" + [guid]::NewGuid().ToString('N') + ".log")
Say "  正在启动 DSH 网页版（端口：$(if ($Port -eq 0) {'自动选择'} else {$Port})）…"
$args = @('web', '--port', "$Port", '--no-open')
$p = Start-Process -FilePath $run[0] -ArgumentList ($run[1..($run.Count-1)] + $args) -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow

$url = $null
for ($i = 0; $i -lt 90; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Path $log) {
    $m = Select-String -Path $log -Pattern 'http://[0-9.]+:[0-9]+/\?token=[A-Za-z0-9_-]+' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m) { $url = $m.Matches[0].Value; break }
  }
  if ($p.HasExited) {
    Say "❌ 启动失败（退出码 $($p.ExitCode)）。日志："
    if (Test-Path $log)   { Get-Content $log -Tail 20 | ForEach-Object { Say "     $_" } }
    if (Test-Path "$log.err") { Get-Content "$log.err" -Tail 10 | ForEach-Object { Say "     $_" } }
    Say "   把上面这段发到 $IssueUrl"
    exit 20
  }
}
if (-not $url) {
  Say "❌ 90 秒内没起来。日志："
  if (Test-Path $log) { Get-Content $log -Tail 20 | ForEach-Object { Say "     $_" } }
  exit 21
}

$realPort = ([regex]::Match($url, ':(\d+)/')).Groups[1].Value
New-Item -ItemType Directory -Force -Path (Split-Path $State) | Out-Null
@{ pid = $p.Id; port = $realPort; started_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } |
  ConvertTo-Json -Compress | Set-Content -Encoding UTF8 $State

# ④ 可选：装桌宠插件
if ($WithPet) {
  if (Get-Command pnpm -ErrorAction SilentlyContinue) {
    Say "  正在安装桌宠插件…"
    $spec = $petPlugin
    if ($petPlugin -ceq 'local') {
      # 打成 tgz 放进 DSH_HOME 再装：是一份快照，之后改仓库不会影响已装的插件
      $dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
      New-Item -ItemType Directory -Force -Path $dshHome | Out-Null
      $tgz = & npm pack (Join-Path "$PSScriptRoot" '..') --pack-destination $dshHome --silent 2>$null | Select-Object -Last 1
      $spec = if ($tgz) { Join-Path $dshHome $tgz } else { '' }
    }
    if ($spec) { & $run[0] @($run[1..($run.Count-1)]) plugin --profile web add $spec 2>&1 | ForEach-Object { Say "     $_" } }
    else { Say "  ⚠️  插件打包失败，没装上（npm pack）" }
  } else {
    Say "  ⚠️  没装 pnpm，跳过插件。装好 pnpm 后重新运行本脚本并加 -WithPet"
  }
}

Say ""
Say "✅ DSH 网页版已启动"
Say "   端口：$realPort"
Say "   完整链接（含登录 token，请勿外发）：$url"
Say "   状态文件：$State（不含 token）"
Say "   停止：Stop-Process -Id $($p.Id)"
Start-Process $url
