# Structural/SMM Module for Local-IV-Disciplined Counterfactuals

This folder is independent of `../struct`. It implements a first runnable Python pipeline for moving from the thesis local IV estimate to structural counterfactuals. The key restriction is conceptual: the IV estimate remains a LATE for exposed sector-year cells and observed incumbents. The counterfactuals are model-based extrapolations disciplined by local causal moments, not reduced-form ATEs.

## What the module does

- Loads `../Data/data_ready_mec.dta`.
- Reconstructs core firm and sector objects: markups, inverse markups, sales shares, HHI, CR4, CR10, lagged controls, sector inverse markups, and decomposition terms.
- Encodes the nested-CES Cournot inverse-markup equation from the thesis.
- Adds direct output-discipline terms to the markup-growth equation: an average output-shock response, an output-shock by lagged-markup-state response, and an output-shock by concentration response.
- Estimates a compact SMM parameter vector by matching data moments to model moments.
- Runs the same IV estimand inside simulated data.
- Performs an ACD-style residual validation: regress observed minus model-implied markup changes on import penetration instrumented by the output shift-share IV.
- Simulates observed, no-output-shock, and no-output-plus-input-shock economies.
- Exports CSV tables and diagnostic PNG figures.

## Run

From this folder:

```powershell
python run_estimation.py --config config.yaml
python run_validation.py --config config.yaml
python run_counterfactuals.py --config config.yaml
```

`config_causal_core.yaml` is the preferred current specification for the thesis
replication package. It targets output-competition IV moments and leaves input,
decomposition, and selection/exit objects as diagnostics.

For a faster plumbing check before a full SMM pass:

```powershell
python run_smoke_tests.py --config config_causal_core.yaml
```

For a bounded diagnostic SMM pass on a deterministic firm subsample:

```powershell
python run_estimation.py --config config_diagnostic.yaml
```

## Main outputs

- `outputs/estimated_parameters.csv`
- `outputs/data_moments.csv`
- `outputs/model_moments.csv`
- `outputs/moment_gaps.csv`
- `outputs/objective_value.csv`
- `outputs/residual_iv_validation.csv`
- `outputs/counterfactual_aggregate_results.csv`
- `outputs/counterfactual_sector_results.csv`
- `outputs/counterfactual_decomposition_tables.csv`
- `outputs/counterfactual_allocative_wedge.csv`
- `figures/data_vs_model_moments.png`
- `figures/counterfactual_manufacturing_inverse_markup.png`
- `figures/counterfactual_decomposition_components.png`

## Moment targets

The SMM objective stacks:

- Baseline firm-level IV coefficient for `dln_mu` on `change_IP`, instrumented by `output_IV`.
- Sector-level inverse-markup IV response.
- Grouped sector-year upper-tail IV coefficients for q80 and q90 of markup growth.
- Exit IV response when the exit variable is available.

Other moments remain implemented and can be restored by editing `moments.active` in `config.yaml`. The current active stack follows the synthesis note's recommendation to stabilize the baseline and upper-tail IV fit before reporting wider counterfactual claims.

## Model boundary

The code does not solve a full cross-sector GE model. Manufacturing aggregation uses the harmonic inverse-markup structure:

```text
mu_jt^{-1} = sum_i s_ijt mu_ijt^{-1}
mu_Mt^{-1} = sum_j S_jt mu_jt^{-1}
```

The counterfactual sector-sales layer is deliberately simple and configurable in `config.yaml`. Treat aggregate counterfactuals as extrapolations from the estimated oligopoly block, not as directly identified causal estimates.
