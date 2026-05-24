param(
    [string]$StataExe = "stata-mp",
    [string]$DataRaw = "",
    [string]$DataDerived = "",
    [string]$DataPublic = "",
    [switch]$Ver24ResultsOnly,
    [switch]$SkipR,
    [switch]$SkipStata,
    [switch]$SkipSCM,
    [switch]$SkipPython,
    [switch]$SkipPaper
)

$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$env:REPLICATION_ROOT = $Repo
if ($DataRaw) { $env:REPLICATION_DATA_RAW = (Resolve-Path $DataRaw).Path }
if ($DataDerived) { $env:REPLICATION_DATA_DERIVED = (Resolve-Path $DataDerived).Path }
if ($DataPublic) { $env:REPLICATION_DATA_PUBLIC = (Resolve-Path $DataPublic).Path }
if ($SkipSCM) { $env:REPLICATION_SKIP_SCM = "1" } else { Remove-Item Env:\REPLICATION_SKIP_SCM -ErrorAction SilentlyContinue }

function Test-Command($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Set-Location $Repo
New-Item -ItemType Directory -Force -Path "output/logs" | Out-Null

if (-not $SkipR) {
    if (-not (Test-Command "Rscript")) {
        Write-Warning "Rscript was not found. Install R or rerun with -SkipR."
    } else {
        Get-ChildItem "code/01_construct" -Filter "*.R" | Sort-Object Name | ForEach-Object {
            Write-Host "Running R script $($_.Name)"
            & Rscript $_.FullName
        }
    }
}

if (-not $SkipStata) {
    if (-not (Test-Command $StataExe)) {
        Write-Warning "$StataExe was not found. Install Stata or pass -StataExe <path>, or rerun with -SkipStata."
    } else {
        $DoFile = if ($Ver24ResultsOnly) { "code/run_ver24_results.do" } else { "code/run_all.do" }
        if ($IsWindows -or $env:OS -eq "Windows_NT") {
            $DoPath = Join-Path $Repo $DoFile
            Start-Process -FilePath $StataExe -ArgumentList @("/e", "do", "`"$DoPath`"") -Wait -WindowStyle Hidden
        } else {
            & $StataExe -b do $DoFile
        }

        $BatchBase = [IO.Path]::GetFileNameWithoutExtension($DoFile)
        $BatchLog = Join-Path $Repo "$BatchBase.log"
        if (Test-Path -LiteralPath $BatchLog) {
            $MovedBatchLog = Join-Path $Repo "output/logs/${BatchBase}_batch.log"
            Move-Item -LiteralPath $BatchLog -Destination $MovedBatchLog -Force
            if (Select-String -LiteralPath $MovedBatchLog -Pattern '^r\([0-9]+\);' -Quiet) {
                throw "Stata reported an error. See $MovedBatchLog."
            }
        }
        Get-ChildItem -LiteralPath $Repo -Filter "__*.dta" -File | Remove-Item -Force
    }
}

if (-not $SkipPython) {
    & python -m compileall -q "code/04_calibration_validation"
    Push-Location "code/04_calibration_validation/smm_model_consistency"
    try {
        & python "run_smoke_tests.py"
    } finally {
        Pop-Location
    }
}

if (-not $SkipPaper) {
    & powershell -ExecutionPolicy Bypass -File "code/99_build_paper/build_paper.ps1"
}
