$ErrorActionPreference = 'Stop'

$repo = 'C:\Users\timeline\WorkerVless2sub'
$bash = 'C:\Program Files\Git\bin\bash.exe'
$log = Join-Path $repo 'cfst_push.log'

if (-not (Test-Path -LiteralPath $bash)) {
    throw "Git Bash not found: $bash"
}

$env:CFST_WORKDIR = '/c/Users/timeline'
$env:HOME = '/c/Users/timeline'

Push-Location $repo
try {
    & $bash --noprofile --norc -lc 'exec /c/Users/timeline/WorkerVless2sub/cfst_push.sh' *>> $log
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
