param(
    [string]$RemoteHost = "45.207.201.139",
    [string]$PushRemote = "zero199901",
    [string]$GitRemote = "origin",
    [string]$Branch = "",
    [string]$RemoteRepoDir = "/root/sub2api-deploy-src",
    [string]$RuntimeDir = "/www/wwwroot/sub2api-deploy"
)

$ErrorActionPreference = "Stop"

$DeployDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $DeployDir "..")
Set-Location $RepoRoot

if (-not $Branch) {
    $Branch = (git branch --show-current).Trim()
}

$Status = git status --porcelain
if ($LASTEXITCODE -ne 0) {
    throw "git status failed"
}
if ($Status) {
    throw "Working tree is not clean. Commit or stash changes before release."
}

Write-Host "== push =="
git push $PushRemote $Branch
if ($LASTEXITCODE -ne 0) {
    throw "git push failed"
}

$RemoteCommand = @"
cd '$RemoteRepoDir' && \
chmod +x ./deploy/release-from-git.sh ./deploy/runtime-sync.sh ./deploy/runtime-stack.sh ./deploy/build_image.sh && \
./deploy/release-from-git.sh --git-remote '$GitRemote' --branch '$Branch' --runtime-dir '$RuntimeDir'
"@

Write-Host "== remote release =="
ssh -T -o BatchMode=yes -o StrictHostKeyChecking=no $RemoteHost $RemoteCommand
if ($LASTEXITCODE -ne 0) {
    throw "remote release failed"
}
