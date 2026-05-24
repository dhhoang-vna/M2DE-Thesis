# Verification Notes

Verification was run on 2026-05-23 from the repository root:

```text
D:\1. M2 Development Economics\0. Thesis\Thesis\M2DE Thesis
```

## Passed

- `powershell -ExecutionPolicy Bypass -File code/run_all.ps1 -StataExe "D:\STATA19\StataMP-64.exe" -Ver24ResultsOnly -SkipSCM -SkipR -SkipPython -SkipPaper`
- `python -m compileall -q code\04_calibration_validation`
- `python code\04_calibration_validation\monte_carlo\monte_carlo_order_stat_bias.py --R 2 --J 6 --T 3 --min_n 5 --max_n 20 --mode independent --no_plots --no_progress --no_linearmodels --output_dir output\monte_carlo\order_stat_bias_smoke`
- `python code\04_calibration_validation\monte_carlo\selection_monte_carlo.py --smoke_test --no_progress --output_dir output\monte_carlo\selection_smoke`
- `python code\04_calibration_validation\smm_model_consistency\run_smoke_tests.py --config code\04_calibration_validation\smm_model_consistency\config.yaml`
- `python code\04_calibration_validation\smm_model_consistency\run_smoke_tests.py --config code\04_calibration_validation\smm_model_consistency\config_causal_core.yaml`
- `powershell -ExecutionPolicy Bypass -File code\99_build_paper\build_paper.ps1`

The Stata run completed with no `r(...)` errors in
`output/logs/run_ver24_results_batch.log`. SCM was skipped by request to avoid
the slow placebo loop; the submitted SCM figures remain present in
`output/figures/`, and `code/02_analysis/6_scm.do` remains callable by omitting
`-SkipSCM`.

The LaTeX build produced `tex/M2Thesis_ver24.pdf`. The rebuilt PDF has the same
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

`output/ver24_exhibit_hash_check.csv` compares the package outputs to the
submitted parent-folder copies for the external tables and figures referenced
by `tex/M2Thesis_ver24.tex`.

- 15 of 24 checked exhibits are byte-identical.
- The 9 regenerated files whose hashes differ from the submitted copies are:
  - `output/figures/iv_quantile_journal.png`
  - `output/figures/iv_quantile_cr4_journal.png`
  - `output/figures/iv_quantile_cr10_journal.png`
  - `output/tables/iv_demand_controls.tex`
  - `output/tables/pretrend_balance_outputIV.tex`
  - `output/tables/rob_resid_firststage.tex`
  - `output/tables/rob_resid_aux.tex`
  - `output/tables/rob_chn_gran_mean.tex`
  - `output/tables/rob_chn_gran_givq_foreign.tex`

The three regenerated PNGs have the same dimensions as the submitted copies,
2400 by 1745 pixels.

## Data-Gated Components

The public GitHub package should not include restricted ORBIS/AMADEUS extracts
or derived `.dta` files built from those extracts. Full independent replication
therefore requires licensed access or local placement of the restricted derived
files described in `data_availability.md`.

## Notes on Cleanup

The ver24 pipeline was normalized to avoid writes outside the repository and to
keep Stata batch logs and temporary files out of the repository root. The
focused run intentionally omits old exploratory specifications that are not
called by the submitted ver24 thesis exhibits.
