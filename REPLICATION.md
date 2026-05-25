# Replication Instructions

This package is anchored to `tex/m2de_thesis.tex`. The code is organized
around the tables, figures, robustness checks, mechanism exercises, synthetic
control figures, and validation material used by the submitted thesis.

## 1. Data Setup

The empirical analysis uses licensed ORBIS/AMADEUS firm-level data and bulky
trade, industry, and input-output files. These inputs are not redistributed.

Expected private-data placement:

```text
data/restricted_placeholder/raw/Orbis/
data/restricted_placeholder/raw/CEPII BACI HS96/
data/restricted_placeholder/raw/UNIDO/
data/restricted_placeholder/raw/TURKSTAT/
data/restricted_placeholder/raw/WIOD/
data/restricted_placeholder/derived/
data/restricted_placeholder/derived/BACI/
data/restricted_placeholder/derived/IV/
data/restricted_placeholder/derived/UNIDO/
```

The focused M2DE thesis replication run starts from derived analysis files such as
`data_ready.dta`, `data_ready_mec.dta`, `data_ready_robust.dta`,
`data_ready_H.dta`, and the BACI/IV/UNIDO derived inputs listed in
`data_availability.md`.

If your private data live elsewhere, pass explicit paths:

```powershell
powershell -ExecutionPolicy Bypass -File code/run_all.ps1 `
  -StataExe "D:\STATA19\StataMP-64.exe" `
  -DataRaw "D:\path\to\raw" `
  -DataDerived "D:\path\to\derived" `
  -M2DEThesisResultsOnly -SkipR -SkipPython -SkipPaper
```

## 2. Software Requirements

- Stata 17 or later; verified with Stata 19 MP.
- R with packages in `R-packages.txt` for concordance construction.
- Python 3.10+ with packages in `requirements.txt` for validation scripts.
- TeX Live or MiKTeX with `pdflatex` and `biber`.

Run the Stata package installer once from Stata if needed:

```stata
do code/00_setup/install_stata_packages.do
```

## 3. Main M2DE Thesis Results Pipeline

The preferred one-command audit run is:

```powershell
powershell -ExecutionPolicy Bypass -File code/run_all.ps1 -StataExe "D:\STATA19\StataMP-64.exe" -M2DEThesisResultsOnly -SkipSCM -SkipR -SkipPython -SkipPaper
```

This calls `code/run_m2de_thesis_results.do`, which runs:

```text
code/03_figures_tables/figures.do
code/02_analysis/2 selection_correction.do
code/02_analysis/3 decomposition (2).do
code/02_analysis/4_robustness.do
code/02_analysis/4_robustness_id.do
code/02_analysis/4_robustness_id_pretrend.do
code/02_analysis/4_robustness_resid.do
code/02_analysis/4_robustness_chn_gran.do
code/02_analysis/5_mechanism.do
code/02_analysis/6_scm.do              optional; skipped by -SkipSCM
code/02_analysis/kirov.do
```

Outputs are written to `output/tables/`, `output/figures/`, and
`output/logs/`.

To run SCM as part of the focused pipeline, omit `-SkipSCM`. The full SCM script
is slow because it runs placebo synthetic controls. For a smoke test that builds
the SCM panel and runs one treated nested synthetic-control optimization without
overwriting thesis SCM figures/tables, set:

```powershell
$env:REPLICATION_SCM_SMOKE = "1"
& "D:\STATA19\StataMP-64.exe" /e do "code\02_analysis\6_scm.do"
Remove-Item Env:\REPLICATION_SCM_SMOKE
```

The focused M2DE thesis runner intentionally excludes historical manufacturing-wide
AE and dispersion-extension scripts/figures because the submitted
`tex/m2de_thesis.tex` does not input those exhibits.

## 4. Full Construction Pipeline

`code/run_all.do` preserves the broader construction sequence for replicators
with all licensed and raw public inputs. It rebuilds the analysis panels from
raw firm, trade, industry, concordance, and input-output files before running
analysis scripts. This path is slower and more data-gated than the focused
M2DE thesis audit run.

## 5. Paper Build

The package copy of the TeX file is path-normalized to read from
`output/tables/`, `output/figures/`, and `tex/M2DEThesis.bib`.

Build with:

```powershell
powershell -ExecutionPolicy Bypass -File code/99_build_paper/build_paper.ps1
```

The build produces `tex/m2de_thesis.pdf`.

## 6. Python Monte Carlo and SMM Validation

### Control-Function Monte Carlo

The package contains two Python Monte Carlo checks.

Grouped-IV quantile/order-statistic control:

```powershell
python code\04_calibration_validation\monte_carlo\monte_carlo_order_stat_bias.py --R 2000 --mode correlated --output_dir output\monte_carlo\order_stat_bias
```

Fast smoke version:

```powershell
python code\04_calibration_validation\monte_carlo\monte_carlo_order_stat_bias.py --R 2 --J 6 --T 3 --min_n 5 --max_n 20 --mode independent --no_plots --no_progress --no_linearmodels --output_dir output\monte_carlo\order_stat_bias_smoke
```

Selection/control-function correction:

```powershell
python code\04_calibration_validation\monte_carlo\selection_monte_carlo.py --R 1000 --theta 0.5 --output_dir output\monte_carlo\selection
```

Fast smoke version:

```powershell
python code\04_calibration_validation\monte_carlo\selection_monte_carlo.py --smoke_test --no_progress --output_dir output\monte_carlo\selection_smoke
```

### Structural/SMM Module

The SMM code is in `code/04_calibration_validation/smm_model_consistency/`. The preferred
current specification is the causal-core config:

```powershell
python code\04_calibration_validation\smm_model_consistency\run_all.py --config code\04_calibration_validation\smm_model_consistency\config_causal_core.yaml
```

This full command re-estimates the SMM objective and rewrites the structural 
outputs. It can be slow. For a quick reproducibility check of the data,
moments, and starting-vector model plumbing:

```powershell
python code\04_calibration_validation\smm_model_consistency\run_smoke_tests.py --config code\04_calibration_validation\smm_model_consistency\config_causal_core.yaml
```

The SMM exercise should be interpreted narrowly: the causal objective
targets output-competition IV moments. Input, decomposition, and selection/exit
objects are exported as diagnostics, not as causal target moments.

## 7. Comparing to Submitted Exhibits

After running the focused pipeline, compare each external figure/table used by
`tex/m2de_thesis.tex` against the submitted parent-folder copies:

```powershell
powershell -ExecutionPolicy Bypass -File code/99_build_paper/check_m2de_thesis_exhibits.ps1
```

The command writes `output/m2de_thesis_exhibit_hash_check.csv`. This is a byte-level
check; all 24 thesis external exhibits match in the current package.
