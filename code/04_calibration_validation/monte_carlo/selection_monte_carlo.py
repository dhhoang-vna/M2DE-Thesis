"""
Monte Carlo validation for the selection-correction term.

This script targets the semiparametric selection correction used in the selection-correction diagnostic.

Design goals
------------
1. Null DGP: true treatment effect is zero. The corrected specification should not create spurious effects.
2. Alternative DGP: true treatment effect is positive. The correction should reduce finite-sample bias and false rejections relative to the uncorrected specification.
3. Functional-form checks: compare polynomial control functions against cubic splines, with multiple degrees / degrees of freedom.
4. Finite-sample inference: optionally use a cluster bootstrap for coverage spot checks on a smaller run.
5. Theta sensitivity: vary the dependence between the latent state and the selection / size shock.

The code is intentionally lightweight enough to run in a VS Code notebook on a CPU runtime, while keeping the DGP and estimators explicit.
"""

from __future__ import annotations

import argparse
import math
import warnings
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass, replace
from itertools import repeat
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd
import statsmodels.api as sm
from scipy.special import expit
from scipy.stats import norm

try:
    from tqdm import tqdm
except ImportError:  # pragma: no cover - fallback for minimal environments
    def tqdm(iterable, total=None, desc=None, unit=None):
        return iterable

try:
    from patsy import dmatrix
except ImportError:  # pragma: no cover - patsy ships with statsmodels in normal setups
    dmatrix = None


DEFAULT_SPECS = ("uncorrected", "poly3", "poly5", "spline6")
DEFAULT_THETAS = (0.0, 0.25, 0.5, 0.75)


@dataclass(frozen=True)
class SelectionConfig:
    J: int = 48
    T: int = 8
    min_n: int = 12
    max_n: int = 90
    beta_true: float = 0.50
    theta: float = 0.50
    selection_state_loading: float = 0.90
    selection_shock_loading: float = 0.55
    outcome_state_loading: float = 0.65
    endogenous_state_loading: float = 0.25
    treatment_strength: float = 0.95
    treatment_noise_scale: float = 0.55
    outcome_noise_scale: float = 1.00
    selection_intercept: float = -0.05
    cell_shock_scale: float = 0.40
    sector_fe_scale: float = 0.35
    year_fe_scale: float = 0.20
    size_noise_scale: float = 0.30
    sample_floor: float = 0.28
    spline_df: int = 6
    poly_degree: int = 3


def standardize(x: np.ndarray) -> np.ndarray:
    x = np.asarray(x, dtype=float)
    sd = np.nanstd(x)
    if not np.isfinite(sd) or sd == 0:
        return x - np.nanmean(x)
    return (x - np.nanmean(x)) / sd


def build_control_basis(lag_state: pd.Series, spec: str, poly_degree: int, spline_df: int) -> pd.DataFrame:
    """Construct control-function bases for the selected sample."""
    lag_state = pd.Series(lag_state, copy=False).astype(float)

    if spec == "uncorrected":
        return pd.DataFrame(index=lag_state.index)

    if spec.startswith("poly"):
        degree = int(spec.replace("poly", "")) if spec != "poly" else poly_degree
        scaled = standardize(lag_state.to_numpy())
        return pd.DataFrame(
            {f"lag_poly_{power}": scaled**power for power in range(1, degree + 1)},
            index=lag_state.index,
        )

    if spec.startswith("spline"):
        if dmatrix is None:
            raise ImportError("patsy is required for spline specifications.")
        df = int(spec.replace("spline", "")) if spec != "spline" else spline_df
        design = dmatrix(
            f"bs(lag_state, df={df}, degree=3, include_intercept=False)",
            {"lag_state": lag_state.to_numpy()},
            return_type="dataframe",
        )
        design.index = lag_state.index
        return design

    raise ValueError(f"Unknown specification: {spec}")


def simulate_panel(cfg: SelectionConfig, seed: int) -> pd.DataFrame:
    """Simulate a firm-level panel with non-ignorable selection."""
    rng = np.random.default_rng(seed)
    sectors = np.arange(cfg.J)
    years = np.arange(2011, 2011 + cfg.T)
    panel = pd.MultiIndex.from_product([sectors, years], names=["sector", "year"]).to_frame(index=False)

    sector_fe = rng.normal(0.0, cfg.sector_fe_scale, size=cfg.J)
    year_fe = rng.normal(0.0, cfg.year_fe_scale, size=cfg.T)
    cell_shock = rng.normal(0.0, cfg.cell_shock_scale, size=len(panel))

    s = panel["sector"].to_numpy()
    t = panel["year"].to_numpy() - years[0]

    log_n = (
        3.25
        + sector_fe[s]
        + year_fe[t]
        + cfg.theta * 0.45 * cell_shock
        + rng.normal(0.0, cfg.size_noise_scale, size=len(panel))
    )
    panel["n_jt"] = np.clip(np.rint(np.exp(log_n)), cfg.min_n, cfg.max_n).astype(int)

    rows: list[pd.DataFrame] = []
    firm_counter = 0
    for idx, row in enumerate(panel.itertuples(index=False)):
        n = int(row.n_jt)
        firm_id = np.arange(firm_counter, firm_counter + n)
        firm_counter += n
        cell_shock_value = float(cell_shock[idx])

        lag_state = rng.normal(
            loc=0.35 * sector_fe[int(row.sector)] + 0.20 * year_fe[int(row.year - years[0])] + 0.55 * cell_shock_value,
            scale=1.0,
            size=n,
        )
        lag_state = standardize(lag_state)

        z = rng.normal(0.0, 1.0, size=n)
        treatment_noise = rng.normal(0.0, cfg.treatment_noise_scale, size=n)
        x = (
            cfg.treatment_strength * z
            + cfg.endogenous_state_loading * lag_state
            + 0.10 * cell_shock_value
            + treatment_noise
        )

        outcome_noise = rng.normal(0.0, cfg.outcome_noise_scale, size=n)
        y = (
            cfg.beta_true * x
            + cfg.outcome_state_loading * lag_state
            + sector_fe[int(row.sector)]
            + year_fe[int(row.year - years[0])]
            + outcome_noise
        )

        selection_index = (
            cfg.selection_intercept
            + cfg.theta * cfg.selection_state_loading * lag_state
            + cfg.selection_shock_loading * outcome_noise
            + 0.25 * cell_shock_value
        )
        selected = rng.uniform(0.0, 1.0, size=n) < expit(selection_index)

        rows.append(
            pd.DataFrame(
                {
                    "firm_id": firm_id,
                    "sector": int(row.sector),
                    "year": int(row.year),
                    "cell_shock": cell_shock_value,
                    "lag_state": lag_state,
                    "z": z,
                    "x": x,
                    "y": y,
                    "selected": selected.astype(int),
                    "n_jt": n,
                }
            )
        )

    return pd.concat(rows, ignore_index=True)


def cluster_ols_beta(
    y: pd.Series,
    X: pd.DataFrame,
    groups: pd.Series,
    param_name: str,
) -> tuple[float, float, float]:
    """Return OLS coefficient, clustered SE, and normal-approximation p-value."""
    X_arr = X.to_numpy(dtype=float)
    y_arr = y.to_numpy(dtype=float)
    group_arr = groups.to_numpy()

    beta, _, rank, _ = np.linalg.lstsq(X_arr, y_arr, rcond=None)
    resid = y_arr - X_arr @ beta
    xtx_inv = np.linalg.pinv(X_arr.T @ X_arr)

    _, group_codes = np.unique(group_arr, return_inverse=True)
    n_groups = int(group_codes.max()) + 1
    scores = np.zeros((n_groups, X_arr.shape[1]), dtype=float)
    np.add.at(scores, group_codes, X_arr * resid[:, None])
    meat = scores.T @ scores

    nobs = X_arr.shape[0]
    denom = max(nobs - rank, 1)
    finite_sample = 1.0
    if n_groups > 1:
        finite_sample = (n_groups / (n_groups - 1.0)) * ((nobs - 1.0) / denom)

    cov = finite_sample * (xtx_inv @ meat @ xtx_inv)
    param_idx = X.columns.get_loc(param_name)
    coef = float(beta[param_idx])
    variance = float(cov[param_idx, param_idx])
    se = math.sqrt(max(variance, 0.0)) if np.isfinite(variance) else np.nan
    p_value = float(2.0 * norm.sf(abs(coef / se))) if np.isfinite(se) and se > 0 else np.nan
    return coef, se, p_value


def fit_specification(df: pd.DataFrame, spec: str, cfg: SelectionConfig) -> dict[str, float | int | str | bool]:
    """Fit one specification on the selected sample."""
    selected = df.loc[df["selected"] == 1].copy()
    if selected.empty:
        raise ValueError("Selected sample is empty.")

    controls = build_control_basis(selected["lag_state"], spec, cfg.poly_degree, cfg.spline_df)
    if "Intercept" in controls.columns:
        controls = controls.drop(columns=["Intercept"])
    sector_dummies = pd.get_dummies(selected["sector"].astype(int), prefix="sector", drop_first=True, dtype=float)
    year_dummies = pd.get_dummies(selected["year"].astype(int), prefix="year", drop_first=True, dtype=float)

    X = pd.concat(
        [
            pd.Series(1.0, index=selected.index, name="const"),
            selected[["x"]].astype(float),
            controls,
            sector_dummies,
            year_dummies,
        ],
        axis=1,
    )

    beta, se, p_value = cluster_ols_beta(selected["y"].astype(float), X, selected["sector"].astype(int), "x")
    ci_low = beta - 1.96 * se
    ci_high = beta + 1.96 * se

    return {
        "specification": spec,
        "beta_hat": beta,
        "se": se,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "covers_true": bool(ci_low <= cfg.beta_true <= ci_high),
        "covers_zero": bool(ci_low <= 0.0 <= ci_high),
        "reject_5pct": bool(p_value < 0.05),
        "p_value": p_value,
        "n_selected": int(len(selected)),
        "selection_rate": float(selected.shape[0] / len(df)),
        "n_clusters": int(selected["sector"].nunique()),
    }


def cluster_bootstrap_ci(
    df: pd.DataFrame,
    spec: str,
    cfg: SelectionConfig,
    draws: int = 99,
    seed: int = 1234,
) -> tuple[float, float]:
    """Cluster bootstrap percentile confidence interval at the sector level."""
    if draws < 5:
        raise ValueError("draws must be at least 5.")

    rng = np.random.default_rng(seed)
    sectors = np.asarray(sorted(df["sector"].unique()))
    beta_draws: list[float] = []

    for _ in range(draws):
        sampled = rng.choice(sectors, size=len(sectors), replace=True)
        boot = pd.concat(
            [df.loc[df["sector"] == s].copy().assign(sector=i) for i, s in enumerate(sampled)],
            ignore_index=True,
        )
        try:
            beta_draws.append(float(fit_specification(boot, spec, replace(cfg, J=len(sampled)))['beta_hat']))
        except Exception:
            continue

    if len(beta_draws) < 5:
        return (np.nan, np.nan)

    return tuple(np.quantile(beta_draws, [0.025, 0.975]).tolist())


def run_one_replication(replication: int, seed: int, cfg: SelectionConfig, specs: Iterable[str]) -> pd.DataFrame:
    df = simulate_panel(cfg, seed + replication)
    rows = []
    for spec in specs:
        try:
            result = fit_specification(df, spec, cfg)
        except Exception as exc:
            warnings.warn(f"Specification {spec} failed in replication {replication}: {exc}")
            result = {
                "specification": spec,
                "beta_hat": np.nan,
                "se": np.nan,
                "ci_low": np.nan,
                "ci_high": np.nan,
                "covers_true": False,
                "covers_zero": False,
                "reject_5pct": False,
                "p_value": np.nan,
                "n_selected": int(df["selected"].sum()),
                "selection_rate": float(df["selected"].mean()),
                "n_clusters": int(df.loc[df["selected"] == 1, "sector"].nunique()),
            }
        result["replication"] = replication
        result["theta"] = cfg.theta
        result["beta_true"] = cfg.beta_true
        rows.append(result)
    return pd.DataFrame(rows)


def run_monte_carlo(
    R: int,
    seed: int,
    cfg: SelectionConfig,
    specs: Iterable[str] = DEFAULT_SPECS,
    show_progress: bool = True,
    jobs: int = 1,
) -> pd.DataFrame:
    specs = tuple(specs)
    iterator = range(R)
    if jobs <= 1:
        if show_progress:
            iterator = tqdm(iterator, total=R, desc="Monte Carlo", unit="rep")
        results = [run_one_replication(replication=r, seed=seed, cfg=cfg, specs=specs) for r in iterator]
    else:
        chunksize = max(1, R // (jobs * 8))
        with ProcessPoolExecutor(max_workers=jobs) as executor:
            mapped = executor.map(
                run_one_replication,
                range(R),
                repeat(seed),
                repeat(cfg),
                repeat(specs),
                chunksize=chunksize,
            )
            if show_progress:
                mapped = tqdm(mapped, total=R, desc=f"Monte Carlo ({jobs} jobs)", unit="rep")
            results = list(mapped)
    return pd.concat(results, ignore_index=True)


def summarize_results(results: pd.DataFrame) -> pd.DataFrame:
    summary = (
        results.groupby(["beta_true", "theta", "specification"], as_index=False)
        .agg(
            mean_beta=("beta_hat", "mean"),
            sd_beta=("beta_hat", "std"),
            mean_se=("se", "mean"),
            coverage_true=("covers_true", "mean"),
            coverage_zero=("covers_zero", "mean"),
            rejection_rate=("reject_5pct", "mean"),
            mean_p_value=("p_value", "mean"),
            mean_selected=("n_selected", "mean"),
            mean_selection_rate=("selection_rate", "mean"),
            replications=("replication", "nunique"),
        )
        .sort_values(["beta_true", "theta", "specification"])
        .reset_index(drop=True)
    )
    summary["bias"] = summary["mean_beta"] - summary["beta_true"]
    return summary


def theta_sensitivity(
    seed: int,
    base_cfg: SelectionConfig,
    specs: Iterable[str],
    thetas: Iterable[float] = DEFAULT_THETAS,
    R: int = 50,
    show_progress: bool = False,
    jobs: int = 1,
) -> pd.DataFrame:
    rows = []
    for theta in thetas:
        cfg = replace(base_cfg, theta=float(theta))
        results = run_monte_carlo(R=R, seed=seed, cfg=cfg, specs=specs, show_progress=show_progress, jobs=jobs)
        summary = summarize_results(results)
        summary["theta"] = theta
        rows.append(summary)
    return pd.concat(rows, ignore_index=True)


def make_run_label(cfg: SelectionConfig, R: int) -> str:
    theta = f"{cfg.theta:.2f}".replace(".", "p").replace("-", "m")
    return f"selection_mc_theta{theta}_beta{cfg.beta_true:.2f}_R{R}".replace(".", "p")


def write_outputs(results: pd.DataFrame, summary: pd.DataFrame, output_dir: Path, label: str) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    raw_path = output_dir / f"{label}_raw.csv"
    summary_path = output_dir / f"{label}_summary.csv"
    tex_path = output_dir / f"{label}_summary.tex"
    results.to_csv(raw_path, index=False)
    summary.to_csv(summary_path, index=False)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        summary.to_latex(tex_path, index=False, float_format="%.4f")
    return [raw_path, summary_path, tex_path]


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Monte Carlo for the selection-correction term.")
    parser.add_argument("--R", type=int, default=100, help="Number of Monte Carlo replications.")
    parser.add_argument("--seed", type=int, default=20240504, help="Base random seed.")
    parser.add_argument("--theta", type=float, default=0.50, help="Strength of dependence in the selection DGP.")
    parser.add_argument("--beta_true", type=float, default=0.50, help="True treatment effect in the alternative DGP.")
    parser.add_argument("--J", type=int, default=48)
    parser.add_argument("--T", type=int, default=8)
    parser.add_argument("--poly_degree", type=int, default=3)
    parser.add_argument("--spline_df", type=int, default=6)
    parser.add_argument("--specs", type=str, default=",".join(DEFAULT_SPECS), help="Comma-separated specification list.")
    parser.add_argument("--output_dir", type=Path, default=Path("output") / "monte_carlo" / "selection")
    parser.add_argument("--jobs", type=int, default=1, help="Parallel worker processes.")
    parser.add_argument("--no_progress", action="store_true")
    parser.add_argument("--smoke_test", action="store_true", help="Run a small smoke-test configuration.")
    parser.add_argument("--bootstrap_draws", type=int, default=0, help="Optional cluster bootstrap draws for a spot check.")
    return parser


def parse_specs(value: str) -> tuple[str, ...]:
    specs = tuple(spec.strip() for spec in value.split(",") if spec.strip())
    if not specs:
        raise argparse.ArgumentTypeError("At least one specification is required.")
    return specs


def main() -> None:
    args = build_arg_parser().parse_args()
    specs = parse_specs(args.specs)

    cfg = SelectionConfig(
        J=args.J,
        T=args.T,
        theta=args.theta,
        beta_true=args.beta_true,
        poly_degree=args.poly_degree,
        spline_df=args.spline_df,
    )

    if args.smoke_test:
        cfg = replace(cfg, J=16, T=5, beta_true=0.50, theta=0.50)
        args.R = min(args.R, 20)
        print("Running smoke test configuration.")

    results = run_monte_carlo(R=args.R, seed=args.seed, cfg=cfg, specs=specs, show_progress=not args.no_progress, jobs=args.jobs)
    summary = summarize_results(results)
    label = make_run_label(cfg, args.R)
    saved = write_outputs(results, summary, args.output_dir, label)

    print("\nSummary")
    print(summary.to_string(index=False))

    if args.bootstrap_draws > 0:
        one_spec = specs[0]
        boot_df = simulate_panel(cfg, args.seed + 999)
        ci_low, ci_high = cluster_bootstrap_ci(boot_df, one_spec, cfg, draws=args.bootstrap_draws, seed=args.seed + 123)
        print(f"\nBootstrap spot check for {one_spec}: [{ci_low:.4f}, {ci_high:.4f}]")

    print("\nSaved outputs")
    for path in saved:
        print(path)


if __name__ == "__main__":
    main()
