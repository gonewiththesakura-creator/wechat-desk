$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if ($root -ne 'D:\WeChatDesk') {
    throw '请在 D:\WeChatDesk 克隆本项目后运行安装。'
}
$wsl = Join-Path $env:SystemRoot 'System32\wsl.exe'
& $wsl --version
if ($LASTEXITCODE) { throw '请先安装或更新 WSL 2。参见 README。' }
$packages = Join-Path $root 'packages'
$disk = Join-Path $root 'debian'
$null = New-Item -ItemType Directory -Force -Path $packages

function Get-VerifiedPackage([string]$Name, [string]$Url, [string]$Sha256) {
    $target = Join-Path $packages $Name
    if (Test-Path -LiteralPath $target) {
        if ((Get-FileHash -LiteralPath $target).Hash -ne $Sha256) {
            throw "已有文件校验失败，请核对版本和来源。文件 $target"
        }
        return $target
    }
    $temp = Join-Path $packages ([IO.Path]::GetRandomFileName())
    try {
        & curl.exe --fail --location --retry 2 --proto '=https' --proto-redir '=https' --output $temp $Url
        if ($LASTEXITCODE) { throw "下载失败。$Url" }
        if ((Get-FileHash -LiteralPath $temp).Hash -ne $Sha256) {
            throw "下载文件与已验证版本的 SHA-256 不匹配。$Name"
        }
        [IO.File]::Move($temp, $target)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp }
    }
    return $target
}

$registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
$instance = if (Test-Path $registry) {
    Get-ChildItem $registry | Get-ItemProperty | Where-Object DistributionName -eq 'WeChatDesk'
}
if ($instance) {
    $base = ($instance.BasePath -replace '^\\\\\?\\','').TrimEnd('\')
    if ($instance.Version -ne 2 -or $base -ne $disk) {
        throw '同名 WSL 环境已存在，路径或版本不符。'
    }
}
$null = Get-VerifiedPackage 'wechat.deb' 'https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.deb' 'D5B21C6E21186A58B2C2FD41712A4EF90F9452735931A6B8500E85C5B0913B0B'
if (!$instance) {
    $image = Get-VerifiedPackage 'debian.wsl' 'https://salsa.debian.org/debian/WSL/-/jobs/9606244/artifacts/raw/Debian_WSL_AMD64_v1.26.0.0.wsl' '5EC7DC68216E75D1D4D4761474E99D8461A98D316537110314B137122A879E0F'
    & $wsl --import WeChatDesk $disk $image --version 2
    if ($LASTEXITCODE) { throw 'WSL 导入失败。请检查虚拟化支持和磁盘空间。' }
}
& $wsl -d WeChatDesk -u root --exec /bin/bash /mnt/d/WeChatDesk/setup/install-linux.sh
if ($LASTEXITCODE) { throw 'Debian 依赖安装失败。处理上方错误后可重新运行此脚本。' }
Set-Content -LiteralPath (Join-Path $root 'desktop-installed.txt') (Get-Date -Format o)
& "$PSScriptRoot\open.ps1"
