# Verification Notes

Verification was updated on 2026-05-25 from the repository root:

```text
D:\1. M2 Development Economics\0. Thesis\Thesis\M2DE Thesis
```

## Passed

- `powershell -ExecutionPolicy Bypass -File code/run_all.ps1 -StataExe "D:\STATA19\StataMP-64.exe" -M2DEThesisResultsOnly -SkipSCM -SkipR -SkipPython -SkipPaper`
- SCM smoke mode with `REPLICATION_SCM_SMOKE=1` on `code/02_analysis/6_scm.do`
- `powershell -ExecutionPolicy Bypass -File code/99_build_paper/check_m2de_thesis_exhibits.ps1`
- `python -m compileall -q code\04_calibration_validation`
- `python code\04_calibration_validation\monte_carlo\monte_carlo_order_stat_bias.py --R 2 --J 6 --T 3 --min_n 5 --max_n 20 --mode independent --no_plots --no_progress --no_linearmodels --output_dir output\monte_carlo\order_stat_bias_smoke`
- `python code\04_calibration_validation\monte_carlo\selection_monte_carlo.py --smoke_test --no_progress --output_dir output\monte_carlo\selection_smoke`
- `python code\04_calibration_validation\smm_model_consistency\run_smoke_tests.py --config code\04_calibration_validation\smm_model_consistency\config.yaml`
- `python code\04_calibration_validation\smm_model_consistency\run_smoke_tests.py --config code\04_calibration_validation\smm_model_consistency\config_causal_core.yaml`
- `powershell -ExecutionPolicy Bypass -File code\99_build_paper\build_paper.ps1`

The Stata run completed with no `r(...)` errors in
`output/logs/run_m2de_thesis_results_batch.log`. SCM was skipped to avoid the slow
placebo loop; the submitted SCM figures are retained in `output/figures/`, and
`code/02_analysis/6_scm.do` remains callable by omitting `-SkipSCM`.
The SCM smoke run completed one treated nested SCM with target ISIC4 2790,
treatment year 2016, and 34 donors.

The LaTeX build produced `tex/m2de_thesis.pdf`. The rebuilt PDF has the same
letter page size as the submitted parent-folder PDF, but it is 78 pages versus
79 pages in the submitted PDF after regenerating outputs.

## Python Validation Scope

The Monte Carlo checks verified the executable control-function code paths:

- `monte_carlo_order_stat_bias.py` tests the grouped-IV quantile
  order-statistic/cell-size control function.
- `monte_carlo/selection_monte_carlo.py` tests polynomial and spline
  control-function corrections against an uncorrected selected-sample estimate.

The SMM smoke tests verified both `config.yaml` and the causal-core
`config_causal_core.yaml` against the local derived panel. The causal-core smoke
test computes the selection-corrected firm-IV moment, grouped-IV upper-tail
moments, decomposition diagnostics, input reallocation, and exit-IV diagnostic.
It does not run the full optimizer. A full SMM rerun is:

```powershell
python code\04_calibration_validation\smm_model_consistency\run_all.py --config code\04_calibration_validation\smm_model_consistency\config_causal_core.yaml
```

## Exhibit Comparison

`output/m2de_thesis_exhibit_hash_check.csv` compares the package outputs to the
submitted parent-folder copies for the external tables and figures referenced
by `tex/m2de_thesis.tex`.

- 24 of 24 checked exhibits are byte-identical.
- The checker is `code/99_build_paper/check_m2de_thesis_exhibits.ps1`.
- Historical manufacturing-wide AE figures/tables were removed because they are
  not called by `tex/m2de_thesis.tex`.
- Historical dispersion-extension figures/tables were removed for the same
  reason.

## Data-Gated Components

The public GitHub package should not include restricted ORBIS/AMADEUS extracts
or derived `.dta` files built from those extracts. Full independent replication
therefore requires licensed access or local placement of the restricted derived
files described in `data_availability.md`.

## Notes on Cleanup

The M2DE thesis pipeline was normalized to avoid writes outside the repository and to
keep Stata batch logs and temporary files out of the repository root. The
focused run intentionally omits old exploratory specifications that are not
called by the submitted M2DE thesis exhibits.
