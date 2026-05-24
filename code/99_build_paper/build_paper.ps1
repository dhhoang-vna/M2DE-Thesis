$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$TexDir = Join-Path $Repo "tex"

Set-Location $TexDir

pdflatex -interaction=nonstopmode -halt-on-error "M2Thesis_ver24.tex"
biber "M2Thesis_ver24"
pdflatex -interaction=nonstopmode -halt-on-error "M2Thesis_ver24.tex"
pdflatex -interaction=nonstopmode -halt-on-error "M2Thesis_ver24.tex"
