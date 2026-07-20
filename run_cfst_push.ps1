$ErrorActionPreference = 'Stop'

$repo = 'C:\Users\timeline\WorkerVless2sub'
$bash = 'C:\Program Files\Git\bin\bash.exe'
$log = Join-Path $repo 'cfst_push.log'

if (-not (Test-Path -LiteralPath $bash)) {
    throw "Git Bash not found: $bash"
}

$env:CFST_WORKDIR = '/c/Users/timeline'
$env:HOME = '/c/Users/timeline'

$gh = 'C:\Program Files\GitHub CLI\gh.exe'
if (-not (Test-Path -LiteralPath $gh)) {
    $gh = (Get-Command gh.exe -ErrorAction SilentlyContinue).Source
}
if ([string]::IsNullOrWhiteSpace($gh)) {
    throw 'GitHub CLI not found.'
}
$token = (& $gh auth token 2>$null | Select-Object -First 1).Trim()
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'GitHub token unavailable from gh auth; refusing to run without push credentials.'
}
$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$token"))
$env:GIT_CONFIG_COUNT = '1'
$env:GIT_CONFIG_KEY_0 = 'http.https://github.com/.extraheader'
$env:GIT_CONFIG_VALUE_0 = "AUTHORIZATION: basic $basic"

Push-Location $repo
try {
    & $bash --noprofile --norc -lc 'exec /c/Users/timeline/WorkerVless2sub/cfst_push.sh' *>> $log
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}
exit $code
