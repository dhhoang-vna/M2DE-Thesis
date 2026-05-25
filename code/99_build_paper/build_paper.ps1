$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$TexDir = Join-Path $Repo "tex"

Set-Location $TexDir

pdflatex -interaction=nonstopmode -halt-on-error "m2de_thesis.tex"
biber "m2de_thesis"
pdflatex -interaction=nonstopmode -halt-on-error "m2de_thesis.tex"
pdflatex -interaction=nonstopmode -halt-on-error "m2de_thesis.tex"
