"""
Monte Carlo validation for grouped-IV quantile order-statistic bias.

This script adapts the logic of Backus (2020), Appendix A.4, to the thesis
setting: sector-year grouped quantile IV regressions of firm-level markup
growth on Chinese import penetration.

The simulation asks whether grouped quantiles suffer from order-statistic bias
when sector-year cells contain different numbers of firms, and whether adding a
polynomial control function in the number of firms restores inference.

Core design
-----------
1. Null DGP, independent cell size:
   The true coefficient of import penetration is zero at every quantile, and
   sector-year cell size is independent of the identifying variation. The count
   correction should be mostly harmless.

2. Null DGP, correlated cell size:
   The true coefficient is still zero, but cell size is correlated with the
   residualized instrument. Bias arises because finite-cell grouped quantiles are
   mechanically related to the number of firm draws. The correction is successful
   if mean beta is close to zero and 95 percent coverage is close to 0.95 across
   deciles.

3. Upper-tail effect DGP:
   Firms with a high latent markup-growth state have a stronger negative response
   to import competition. This is a power check: the corrected design should
   preserve the negative upper-tail pattern rather than explaining it away with
   cell-size controls.

Examples
--------
python calibration/monte_carlo_order_stat_bias.py --R 2000 --mode correlated --theta 0.4 --poly_degree 3 --error_dist student
python calibration/monte_carlo_order_stat_bias.py --R 10000 --mode independent
python calibration/monte_carlo_order_stat_bias.py --R 2000 --true_effect upper_tail
"""

from __future__ import annotations

import argparse
import math
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.stats import chi2, norm
import statsmodels.api as sm
from tqdm import tqdm

try:
    from linearmodels.iv import IV2SLS
except ImportError:  # pragma: no cover - exercised only when linearmodels is installed
    IV2SLS = None


DEFAULT_QUANTILES = tuple(range(10, 100, 10))


@dataclass(frozen=True)
class SimulationConfig:
    J: int = 70
    T: int = 9
    pi: float = 0.89
    lambda_input: float = 0.15
    input_corr: float = 0.15
    theta: float = 0.4
    mode: str = "correlated"
    true_effect: str = "null"
    beta_low: float = 0.0
    beta_high: float = -0.5
    state_loading: float = 0.35
    min_n: int = 10
    max_n: int = 250
    error_dist: str = "normal"
    error_scale: float = 0.20
    student_df: float = 5.0
    sector_fe_scale: float = 0.20
    year_fe_scale: float = 0.08
    shock_scale: float = 0.45
    first_stage_noise_scale: float = 0.35
    quantiles: tuple[int, ...] = DEFAULT_QUANTILES
    quantile_method: str = "order"
    empirical_residuals: np.ndarray | None = None


def standardize(x: np.ndarray) -> np.ndarray:
    """Return a centered, variance-one copy, with a fallback for constants."""
    x = np.asarray(x, dtype=float)
    sd = np.nanstd(x)
    if not np.isfinite(sd) or sd == 0:
        return x - np.nanmean(x)
    return (x - np.nanmean(x)) / sd


def residualize_twfe(df: pd.DataFrame, value_col: str, sector_col: str = "sector", year_col: str = "year") -> np.ndarray:
    """Residualize a balanced sector-year variable on sector and year fixed effects."""
    x = df[value_col].astype(float)
    sector_mean = x.groupby(df[sector_col]).transform("mean")
    year_mean = x.groupby(df[year_col]).transform("mean")
    return (x - sector_mean - year_mean + x.mean()).to_numpy()


def draw_errors(rng: np.random.Generator, n: int, cfg: SimulationConfig) -> np.ndarray:
    """Draw firm-level shocks for the selected distribution."""
    if cfg.error_dist == "normal":
        return rng.normal(0.0, cfg.error_scale, size=n)
    if cfg.error_dist == "student":
        raw = rng.standard_t(df=cfg.student_df, size=n)
        if cfg.student_df > 2:
            raw = raw / math.sqrt(cfg.student_df / (cfg.student_df - 2.0))
        return cfg.error_scale * raw
    if cfg.error_dist == "empirical":
        if cfg.empirical_residuals is None or len(cfg.empirical_residuals) == 0:
            raise ValueError("error_dist='empirical' requires a non-empty residual vector.")
        return rng.choice(cfg.empirical_residuals, size=n, replace=True)
    raise ValueError(f"Unsupported error_dist: {cfg.error_dist}")


def simulate_panel(cfg: SimulationConfig, seed: int) -> tuple[pd.DataFrame, pd.DataFrame]:
    """
    Simulate a firm-level panel and its sector-year treatment/instrument variables.

    Cell size is correlated with residualized identifying variation when
    cfg.mode == "correlated"; otherwise it is drawn independently.
    """
    rng = np.random.default_rng(seed)
    sectors = np.arange(cfg.J)
    years = np.arange(2011, 2011 + cfg.T)
    panel = pd.MultiIndex.from_product([sectors, years], names=["sector", "year"]).to_frame(index=False)

    sector_z_fe = rng.normal(0.0, 0.7, size=cfg.J)
    year_z_fe = rng.normal(0.0, 0.4, size=cfg.T)
    exposure = standardize(rng.lognormal(mean=0.0, sigma=0.7, size=cfg.J))
    common_shock = standardize(rng.normal(0.0, 1.0, size=cfg.T))

    s = panel["sector"].to_numpy()
    t_index = panel["year"].to_numpy() - years[0]
    shift_share_component = exposure[s] * common_shock[t_index]
    z_output_raw = (
        sector_z_fe[s]
        + year_z_fe[t_index]
        + cfg.shock_scale * shift_share_component
        + rng.normal(0.0, 0.35, size=len(panel))
    )
    panel["Z_output"] = standardize(z_output_raw)
    panel["Z_resid"] = standardize(residualize_twfe(panel, "Z_output"))

    input_sector_fe = rng.normal(0.0, 0.35, size=cfg.J)
    input_year_fe = rng.normal(0.0, 0.20, size=cfg.T)
    z_input_raw = (
        cfg.input_corr * panel["Z_output"].to_numpy()
        + input_sector_fe[s]
        + input_year_fe[t_index]
        + rng.normal(0.0, 0.75, size=len(panel))
    )
    panel["Z_input"] = standardize(z_input_raw)

    d_ip_raw = (
        cfg.pi * panel["Z_output"].to_numpy()
        + cfg.lambda_input * panel["Z_input"].to_numpy()
        + rng.normal(0.0, cfg.sector_fe_scale, size=cfg.J)[s]
        + rng.normal(0.0, cfg.year_fe_scale, size=cfg.T)[t_index]
        + rng.normal(0.0, cfg.first_stage_noise_scale, size=len(panel))
    )
    panel["dIP"] = standardize(d_ip_raw)

    size_sector_fe = rng.normal(0.0, 0.55, size=cfg.J)
    size_year_fe = rng.normal(0.0, 0.10, size=cfg.T)
    log_n = 3.10 + size_sector_fe[s] + size_year_fe[t_index] + rng.normal(0.0, 0.35, size=len(panel))
    if cfg.mode == "correlated":
        log_n = log_n + cfg.theta * panel["Z_resid"].to_numpy()
    elif cfg.mode != "independent":
        raise ValueError("mode must be either 'independent' or 'correlated'.")
    panel["n_jt"] = np.clip(np.rint(np.exp(log_n)), cfg.min_n, cfg.max_n).astype(int)

    outcome_sector_fe = rng.normal(0.0, cfg.sector_fe_scale, size=cfg.J)
    outcome_year_fe = rng.normal(0.0, cfg.year_fe_scale, size=cfg.T)

    firm_rows: list[pd.DataFrame] = []
    firm_counter = 0
    high_state_cutoff = norm.ppf(0.75)
    for row in panel.itertuples(index=False):
        n = int(row.n_jt)
        firm_id = np.arange(firm_counter, firm_counter + n)
        firm_counter += n
        eps = draw_errors(rng, n, cfg)
        base = outcome_sector_fe[int(row.sector)] + outcome_year_fe[int(row.year - years[0])]

        if cfg.true_effect == "null":
            dln_mu = base + eps
            beta_i = np.zeros(n)
        elif cfg.true_effect == "upper_tail":
            firm_state = rng.normal(0.0, 1.0, size=n)
            beta_i = cfg.beta_low + cfg.beta_high * (firm_state > high_state_cutoff)
            dln_mu = base + cfg.state_loading * firm_state + beta_i * float(row.dIP) + eps
        else:
            raise ValueError("true_effect must be either 'null' or 'upper_tail'.")

        firm_rows.append(
            pd.DataFrame(
                {
                    "firm_id": firm_id,
                    "sector": int(row.sector),
                    "year": int(row.year),
                    "dln_mu": dln_mu,
                    "beta_i": beta_i,
                    "dIP": float(row.dIP),
                    "Z_output": float(row.Z_output),
                    "Z_input": float(row.Z_input),
                    "n_jt": n,
                }
            )
        )

    firm_panel = pd.concat(firm_rows, ignore_index=True)
    return firm_panel, panel


def order_quantile(values: np.ndarray, q: int) -> float:
    """Backus-style empirical quantile: ceil(q * n) order statistic."""
    clean = np.sort(np.asarray(values, dtype=float))
    if clean.size == 0:
        return np.nan
    rank = int(math.ceil((q / 100.0) * clean.size)) - 1
    rank = min(max(rank, 0), clean.size - 1)
    return float(clean[rank])


def compute_group_quantiles(firm_panel: pd.DataFrame, quantiles: Iterable[int] = DEFAULT_QUANTILES, method: str = "order") -> pd.DataFrame:
    """Collapse firm-level outcomes to sector-year grouped quantiles."""
    base_cols = ["sector", "year", "dIP", "Z_output", "Z_input", "n_jt"]
    sector_year = firm_panel[base_cols].drop_duplicates(["sector", "year"]).copy()

    grouped = firm_panel.groupby(["sector", "year"], sort=False)["dln_mu"]
    quantile_frames = []
    for q in quantiles:
        if method == "order":
            values = grouped.apply(lambda x, qq=q: order_quantile(x.to_numpy(), qq)).rename(f"q{q}")
        elif method == "linear":
            values = grouped.quantile(q / 100.0).rename(f"q{q}")
        else:
            raise ValueError("quantile_method must be 'order' or 'linear'.")
        quantile_frames.append(values)
    quantile_df = pd.concat(quantile_frames, axis=1).reset_index()
    return sector_year.merge(quantile_df, on=["sector", "year"], how="inner", validate="1:1")


def build_design_matrices(
    group_df: pd.DataFrame,
    quantile: int,
    corrected: bool,
    poly_degree: int,
) -> tuple[pd.Series, pd.DataFrame, pd.DataFrame, pd.DataFrame, list[str]]:
    """Build y, exogenous regressors, endogenous variable, and excluded instrument."""
    y = group_df[f"q{quantile}"].astype(float)
    exog, endog, instruments, poly_terms = build_design_components(group_df, corrected, poly_degree)
    return y, exog, endog, instruments, poly_terms


def build_design_components(
    group_df: pd.DataFrame,
    corrected: bool,
    poly_degree: int,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, list[str]]:
    """Build reusable IV design components for one specification."""
    exog = pd.DataFrame(
        {
            "const": 1.0,
            "Z_input": group_df["Z_input"].astype(float),
        },
        index=group_df.index,
    )

    if corrected:
        n_scaled = standardize(group_df["n_jt"].to_numpy())
        for degree in range(1, poly_degree + 1):
            exog[f"n_poly_{degree}"] = n_scaled**degree

    sector_dummies = pd.get_dummies(group_df["sector"].astype(int), prefix="sector", drop_first=True, dtype=float)
    year_dummies = pd.get_dummies(group_df["year"].astype(int), prefix="year", drop_first=True, dtype=float)
    exog = pd.concat([exog, sector_dummies, year_dummies], axis=1)

    endog = pd.DataFrame({"dIP": group_df["dIP"].astype(float)}, index=group_df.index)
    instruments = pd.DataFrame({"Z_output": group_df["Z_output"].astype(float)}, index=group_df.index)
    poly_terms = [f"n_poly_{degree}" for degree in range(1, poly_degree + 1)] if corrected else []
    return exog, endog, instruments, poly_terms


def first_stage_f_stat(endog: pd.DataFrame, exog: pd.DataFrame, instruments: pd.DataFrame) -> float:
    """Compute a non-robust excluded-instrument first-stage F statistic."""
    y = endog.iloc[:, 0].to_numpy()
    x_restricted = exog.to_numpy(dtype=float)
    x_unrestricted = pd.concat([exog, instruments], axis=1).to_numpy(dtype=float)

    restricted = sm.OLS(y, x_restricted).fit()
    unrestricted = sm.OLS(y, x_unrestricted).fit()
    q = instruments.shape[1]
    df_denom = max(x_unrestricted.shape[0] - x_unrestricted.shape[1], 1)
    numerator = max(restricted.ssr - unrestricted.ssr, 0.0) / q
    denominator = unrestricted.ssr / df_denom
    if denominator <= 0:
        return np.nan
    return float(numerator / denominator)


def manual_2sls_cluster(
    y: pd.Series,
    exog: pd.DataFrame,
    endog: pd.DataFrame,
    instruments: pd.DataFrame,
    clusters: pd.Series,
) -> tuple[pd.Series, pd.DataFrame]:
    """Two-stage least squares with sector-clustered sandwich covariance."""
    x_df = pd.concat([endog, exog], axis=1)
    z_df = pd.concat([instruments, exog], axis=1)
    x = x_df.to_numpy(dtype=float)
    z = z_df.to_numpy(dtype=float)
    y_arr = y.to_numpy(dtype=float).reshape(-1, 1)

    zz_inv = np.linalg.pinv(z.T @ z)
    x_pz_x = x.T @ z @ zz_inv @ z.T @ x
    x_pz_y = x.T @ z @ zz_inv @ z.T @ y_arr
    beta = np.linalg.pinv(x_pz_x) @ x_pz_y
    resid = y_arr - x @ beta

    meat = np.zeros((z.shape[1], z.shape[1]))
    cluster_values = pd.Series(clusters).to_numpy()
    for cluster in np.unique(cluster_values):
        idx = cluster_values == cluster
        score_g = z[idx, :].T @ resid[idx, :]
        meat += score_g @ score_g.T

    middle = x.T @ z @ zz_inv @ meat @ zz_inv @ z.T @ x
    cov = np.linalg.pinv(x_pz_x) @ middle @ np.linalg.pinv(x_pz_x)

    nobs, nparams = x.shape
    nclusters = len(np.unique(cluster_values))
    if nclusters > 1 and nobs > nparams:
        small_sample = (nclusters / (nclusters - 1.0)) * ((nobs - 1.0) / (nobs - nparams))
        cov *= small_sample

    params = pd.Series(beta.ravel(), index=x_df.columns)
    cov_df = pd.DataFrame(cov, index=x_df.columns, columns=x_df.columns)
    return params, cov_df


@dataclass(frozen=True)
class PreparedIV:
    x: np.ndarray
    z: np.ndarray
    x_columns: list[str]
    inv_x_pz_x: np.ndarray
    x_t_z_zz_inv: np.ndarray
    cluster_indices: list[np.ndarray]
    small_sample: float


def prepare_manual_2sls(
    exog: pd.DataFrame,
    endog: pd.DataFrame,
    instruments: pd.DataFrame,
    clusters: pd.Series,
) -> PreparedIV:
    """Precompute reusable matrices for a fixed 2SLS design."""
    x_df = pd.concat([endog, exog], axis=1)
    z_df = pd.concat([instruments, exog], axis=1)
    x = x_df.to_numpy(dtype=float)
    z = z_df.to_numpy(dtype=float)
    zz_inv = np.linalg.pinv(z.T @ z)
    x_t_z_zz_inv = x.T @ z @ zz_inv
    x_pz_x = x_t_z_zz_inv @ z.T @ x
    inv_x_pz_x = np.linalg.pinv(x_pz_x)

    cluster_values = pd.Series(clusters).to_numpy()
    cluster_indices = [np.flatnonzero(cluster_values == cluster) for cluster in np.unique(cluster_values)]

    nobs, nparams = x.shape
    nclusters = len(cluster_indices)
    small_sample = 1.0
    if nclusters > 1 and nobs > nparams:
        small_sample = (nclusters / (nclusters - 1.0)) * ((nobs - 1.0) / (nobs - nparams))

    return PreparedIV(
        x=x,
        z=z,
        x_columns=list(x_df.columns),
        inv_x_pz_x=inv_x_pz_x,
        x_t_z_zz_inv=x_t_z_zz_inv,
        cluster_indices=cluster_indices,
        small_sample=small_sample,
    )


def estimate_prepared_manual_2sls(y: pd.Series, prepared: PreparedIV) -> tuple[pd.Series, pd.DataFrame]:
    """Estimate one outcome using a precomputed manual 2SLS design."""
    y_arr = y.to_numpy(dtype=float).reshape(-1, 1)
    beta = prepared.inv_x_pz_x @ prepared.x_t_z_zz_inv @ prepared.z.T @ y_arr
    resid = y_arr - prepared.x @ beta

    meat = np.zeros((prepared.z.shape[1], prepared.z.shape[1]))
    for idx in prepared.cluster_indices:
        score_g = prepared.z[idx, :].T @ resid[idx, :]
        meat += score_g @ score_g.T

    middle = prepared.x_t_z_zz_inv @ meat @ prepared.x_t_z_zz_inv.T
    cov = prepared.inv_x_pz_x @ middle @ prepared.inv_x_pz_x
    cov *= prepared.small_sample

    params = pd.Series(beta.ravel(), index=prepared.x_columns)
    cov_df = pd.DataFrame(cov, index=prepared.x_columns, columns=prepared.x_columns)
    return params, cov_df


def run_grouped_iv_quantile(
    group_df: pd.DataFrame,
    quantile: int,
    corrected: bool,
    poly_degree: int = 3,
    prefer_linearmodels: bool = True,
) -> dict[str, float | int | str | bool]:
    """Estimate one grouped-IV quantile regression."""
    y, exog, endog, instruments, poly_terms = build_design_matrices(group_df, quantile, corrected, poly_degree)
    clusters = group_df["sector"].astype(int)

    backend = "manual"
    if prefer_linearmodels and IV2SLS is not None:
        try:
            model = IV2SLS(y, exog, endog, instruments)
            fit = model.fit(cov_type="clustered", clusters=clusters)
            params = fit.params
            cov = fit.cov
            backend = "linearmodels"
        except Exception as exc:  # pragma: no cover - defensive fallback
            warnings.warn(f"linearmodels failed; using manual 2SLS fallback. Reason: {exc}")
            params, cov = manual_2sls_cluster(y, exog, endog, instruments, clusters)
    else:
        params, cov = manual_2sls_cluster(y, exog, endog, instruments, clusters)

    beta = float(params["dIP"])
    se = float(math.sqrt(max(cov.loc["dIP", "dIP"], 0.0)))
    ci_low = beta - 1.96 * se
    ci_high = beta + 1.96 * se
    p_value = float(2.0 * (1.0 - norm.cdf(abs(beta / se)))) if se > 0 else np.nan

    poly_p = np.nan
    if corrected and poly_terms:
        try:
            b_poly = params.loc[poly_terms].to_numpy(dtype=float)
            v_poly = cov.loc[poly_terms, poly_terms].to_numpy(dtype=float)
            wald = float(b_poly.T @ np.linalg.pinv(v_poly) @ b_poly)
            poly_p = float(1.0 - chi2.cdf(wald, len(poly_terms)))
        except Exception:
            poly_p = np.nan

    return {
        "quantile": int(quantile),
        "specification": "corrected" if corrected else "uncorrected",
        "poly_degree": int(poly_degree) if corrected else 0,
        "beta_hat": beta,
        "se": se,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "ci_length": ci_high - ci_low,
        "covers_zero": bool(ci_low <= 0.0 <= ci_high),
        "reject_5pct": bool(np.isfinite(p_value) and p_value < 0.05),
        "p_value": p_value,
        "poly_p_value": poly_p,
        "first_stage_F": first_stage_f_stat(endog, exog, instruments),
        "n_sector_year": int(len(group_df)),
        "n_clusters": int(group_df["sector"].nunique()),
        "backend": backend,
    }


def make_result_row(
    params: pd.Series,
    cov: pd.DataFrame,
    quantile: int,
    corrected: bool,
    poly_degree: int,
    poly_terms: list[str],
    first_stage_F: float,
    group_df: pd.DataFrame,
    backend: str,
) -> dict[str, float | int | str | bool]:
    """Convert IV parameters and covariance into a standard result row."""
    beta = float(params["dIP"])
    se = float(math.sqrt(max(cov.loc["dIP", "dIP"], 0.0)))
    ci_low = beta - 1.96 * se
    ci_high = beta + 1.96 * se
    p_value = float(2.0 * (1.0 - norm.cdf(abs(beta / se)))) if se > 0 else np.nan

    poly_p = np.nan
    if corrected and poly_terms:
        try:
            b_poly = params.loc[poly_terms].to_numpy(dtype=float)
            v_poly = cov.loc[poly_terms, poly_terms].to_numpy(dtype=float)
            wald = float(b_poly.T @ np.linalg.pinv(v_poly) @ b_poly)
            poly_p = float(1.0 - chi2.cdf(wald, len(poly_terms)))
        except Exception:
            poly_p = np.nan

    return {
        "quantile": int(quantile),
        "specification": "corrected" if corrected else "uncorrected",
        "poly_degree": int(poly_degree) if corrected else 0,
        "beta_hat": beta,
        "se": se,
        "ci_low": ci_low,
        "ci_high": ci_high,
        "ci_length": ci_high - ci_low,
        "covers_zero": bool(ci_low <= 0.0 <= ci_high),
        "reject_5pct": bool(np.isfinite(p_value) and p_value < 0.05),
        "p_value": p_value,
        "poly_p_value": poly_p,
        "first_stage_F": first_stage_F,
        "n_sector_year": int(len(group_df)),
        "n_clusters": int(group_df["sector"].nunique()),
        "backend": backend,
    }


def run_grouped_iv_quantiles(
    group_df: pd.DataFrame,
    quantiles: Iterable[int],
    corrected: bool,
    poly_degree: int = 3,
    prefer_linearmodels: bool = True,
) -> list[dict[str, float | int | str | bool]]:
    """
    Estimate all grouped-IV quantile regressions for one specification.

    The manual backend precomputes the fixed IV design once, which makes large
    Monte Carlo runs much faster than rebuilding dummies and first stages for
    every decile.
    """
    exog, endog, instruments, poly_terms = build_design_components(group_df, corrected, poly_degree)
    clusters = group_df["sector"].astype(int)
    first_stage_F = first_stage_f_stat(endog, exog, instruments)

    rows: list[dict[str, float | int | str | bool]] = []
    if prefer_linearmodels and IV2SLS is not None:
        for q in quantiles:
            y = group_df[f"q{q}"].astype(float)
            try:
                model = IV2SLS(y, exog, endog, instruments)
                fit = model.fit(cov_type="clustered", clusters=clusters)
                rows.append(
                    make_result_row(
                        fit.params,
                        fit.cov,
                        quantile=q,
                        corrected=corrected,
                        poly_degree=poly_degree,
                        poly_terms=poly_terms,
                        first_stage_F=first_stage_F,
                        group_df=group_df,
                        backend="linearmodels",
                    )
                )
            except Exception as exc:  # pragma: no cover - defensive fallback
                warnings.warn(f"linearmodels failed; using manual 2SLS fallback. Reason: {exc}")
                prepared = prepare_manual_2sls(exog, endog, instruments, clusters)
                params, cov = estimate_prepared_manual_2sls(y, prepared)
                rows.append(
                    make_result_row(
                        params,
                        cov,
                        quantile=q,
                        corrected=corrected,
                        poly_degree=poly_degree,
                        poly_terms=poly_terms,
                        first_stage_F=first_stage_F,
                        group_df=group_df,
                        backend="manual",
                    )
                )
        return rows

    prepared = prepare_manual_2sls(exog, endog, instruments, clusters)
    for q in quantiles:
        y = group_df[f"q{q}"].astype(float)
        params, cov = estimate_prepared_manual_2sls(y, prepared)
        rows.append(
            make_result_row(
                params,
                cov,
                quantile=q,
                corrected=corrected,
                poly_degree=poly_degree,
                poly_terms=poly_terms,
                first_stage_F=first_stage_F,
                group_df=group_df,
                backend="manual",
            )
        )
    return rows


def run_one_replication(
    replication: int,
    seed: int,
    cfg: SimulationConfig,
    poly_degree: int = 3,
    prefer_linearmodels: bool = True,
) -> pd.DataFrame:
    """Run one full simulation replication across quantiles and specifications."""
    firm_panel, _sector_panel = simulate_panel(cfg, seed + replication)
    group_df = compute_group_quantiles(firm_panel, cfg.quantiles, cfg.quantile_method)

    rows: list[dict[str, float | int | str | bool]] = []
    for corrected in (False, True):
        rows.extend(
            run_grouped_iv_quantiles(
                group_df,
                quantiles=cfg.quantiles,
                corrected=corrected,
                poly_degree=poly_degree,
                prefer_linearmodels=prefer_linearmodels,
            )
        )
    for result in rows:
        result["replication"] = replication
        result["mode"] = cfg.mode
        result["theta"] = cfg.theta
        result["true_effect"] = cfg.true_effect
        result["error_dist"] = cfg.error_dist
    return pd.DataFrame(rows)


def run_monte_carlo(
    R: int,
    seed: int,
    cfg: SimulationConfig,
    poly_degree: int = 3,
    prefer_linearmodels: bool = True,
    show_progress: bool = True,
) -> pd.DataFrame:
    """Run R Monte Carlo replications."""
    iterator = range(R)
    if show_progress:
        iterator = tqdm(iterator, total=R, desc="Monte Carlo", unit="rep")

    results = [
        run_one_replication(
            replication=r,
            seed=seed,
            cfg=cfg,
            poly_degree=poly_degree,
            prefer_linearmodels=prefer_linearmodels,
        )
        for r in iterator
    ]
    return pd.concat(results, ignore_index=True)


def summarize_results(results: pd.DataFrame) -> pd.DataFrame:
    """Create a Backus-style summary table."""
    summary = (
        results.groupby(["true_effect", "mode", "error_dist", "quantile", "specification"], as_index=False)
        .agg(
            mean_beta=("beta_hat", "mean"),
            sd_beta=("beta_hat", "std"),
            mean_se=("se", "mean"),
            mean_ci_length=("ci_length", "mean"),
            coverage_rate=("covers_zero", "mean"),
            rejection_rate_5pct=("reject_5pct", "mean"),
            mean_poly_p_value=("poly_p_value", "mean"),
            mean_first_stage_F=("first_stage_F", "mean"),
            replications=("replication", "nunique"),
        )
        .sort_values(["quantile", "specification"])
        .reset_index(drop=True)
    )
    return summary


def plot_results(summary: pd.DataFrame, output_dir: Path, label: str) -> list[Path]:
    """Save beta, coverage, and rejection-rate plots."""
    output_dir.mkdir(parents=True, exist_ok=True)
    saved: list[Path] = []

    ordered_specs = ["uncorrected", "corrected"]
    colors = {"uncorrected": "#7B4F9D", "corrected": "#1B7F79"}

    fig, ax = plt.subplots(figsize=(8.0, 4.8))
    for spec in ordered_specs:
        tmp = summary[summary["specification"] == spec].sort_values("quantile")
        ax.plot(tmp["quantile"], tmp["mean_beta"], marker="o", label=spec.title(), color=colors[spec])
        ax.fill_between(
            tmp["quantile"].to_numpy(dtype=float),
            (tmp["mean_beta"] - tmp["sd_beta"]).to_numpy(dtype=float),
            (tmp["mean_beta"] + tmp["sd_beta"]).to_numpy(dtype=float),
            alpha=0.18,
            color=colors[spec],
            linewidth=0,
        )
    ax.axhline(0.0, color="black", linewidth=0.8)
    ax.set_xlabel("Within-sector-year quantile")
    ax.set_ylabel("Monte Carlo mean beta")
    ax.set_title("Grouped-IV Quantile Estimates")
    ax.legend(frameon=False)
    fig.tight_layout()
    beta_path = output_dir / f"{label}_beta_by_quantile.png"
    fig.savefig(beta_path, dpi=200)
    plt.close(fig)
    saved.append(beta_path)

    fig, ax = plt.subplots(figsize=(8.0, 4.8))
    for spec in ordered_specs:
        tmp = summary[summary["specification"] == spec].sort_values("quantile")
        ax.plot(tmp["quantile"], tmp["coverage_rate"], marker="o", label=spec.title(), color=colors[spec])
    ax.axhline(0.95, color="black", linewidth=0.8, linestyle="--")
    ax.set_ylim(0.0, 1.02)
    ax.set_xlabel("Within-sector-year quantile")
    ax.set_ylabel("Share of 95 percent CIs containing zero")
    ax.set_title("Coverage Under the Zero Benchmark")
    ax.legend(frameon=False)
    fig.tight_layout()
    coverage_path = output_dir / f"{label}_coverage_by_quantile.png"
    fig.savefig(coverage_path, dpi=200)
    plt.close(fig)
    saved.append(coverage_path)

    fig, ax = plt.subplots(figsize=(8.0, 4.8))
    for spec in ordered_specs:
        tmp = summary[summary["specification"] == spec].sort_values("quantile")
        ax.plot(tmp["quantile"], tmp["rejection_rate_5pct"], marker="o", label=spec.title(), color=colors[spec])
    ax.axhline(0.05, color="black", linewidth=0.8, linestyle="--")
    ax.set_ylim(0.0, max(0.20, min(1.0, summary["rejection_rate_5pct"].max() * 1.2 + 0.02)))
    ax.set_xlabel("Within-sector-year quantile")
    ax.set_ylabel("5 percent rejection rate")
    ax.set_title("False Rejection or Power Against Zero")
    ax.legend(frameon=False)
    fig.tight_layout()
    rejection_path = output_dir / f"{label}_rejection_by_quantile.png"
    fig.savefig(rejection_path, dpi=200)
    plt.close(fig)
    saved.append(rejection_path)

    return saved


def write_outputs(results: pd.DataFrame, summary: pd.DataFrame, output_dir: Path, label: str, make_plots: bool) -> list[Path]:
    """Write raw results, summary files, and plots."""
    output_dir.mkdir(parents=True, exist_ok=True)
    raw_path = output_dir / f"{label}_raw_results.csv"
    summary_path = output_dir / f"{label}_summary.csv"
    tex_path = output_dir / f"{label}_summary.tex"

    results.to_csv(raw_path, index=False)
    summary.to_csv(summary_path, index=False)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        summary.to_latex(tex_path, index=False, float_format="%.4f")

    saved = [raw_path, summary_path, tex_path]
    if make_plots:
        saved.extend(plot_results(summary, output_dir, label))
    return saved


def print_interpretation(summary: pd.DataFrame, cfg: SimulationConfig) -> None:
    """Print a short console interpretation."""
    uncorrected = summary[summary["specification"] == "uncorrected"]
    corrected = summary[summary["specification"] == "corrected"]
    tail_quantiles = summary["quantile"].isin([80, 90])

    unc_tail_abs_bias = uncorrected.loc[uncorrected["quantile"].isin([80, 90]), "mean_beta"].abs().mean()
    cor_tail_abs_bias = corrected.loc[corrected["quantile"].isin([80, 90]), "mean_beta"].abs().mean()
    unc_tail_reject = uncorrected.loc[uncorrected["quantile"].isin([80, 90]), "rejection_rate_5pct"].mean()
    cor_tail_reject = corrected.loc[corrected["quantile"].isin([80, 90]), "rejection_rate_5pct"].mean()

    print("\nInterpretation")
    print("--------------")
    if cfg.true_effect == "null":
        print("Null DGP: the true import-penetration coefficient is zero at every decile.")
        if cfg.mode == "correlated":
            print("Cell size is correlated with residualized IV variation, so the uncorrected tail estimates are the stress test.")
        else:
            print("Cell size is independent of IV variation, so the correction should be mostly harmless.")
        print(f"Mean absolute beta in Q80/Q90, uncorrected: {unc_tail_abs_bias:.4f}")
        print(f"Mean absolute beta in Q80/Q90, corrected:   {cor_tail_abs_bias:.4f}")
        print(f"Mean 5pct rejection in Q80/Q90, uncorrected: {unc_tail_reject:.3f}")
        print(f"Mean 5pct rejection in Q80/Q90, corrected:   {cor_tail_reject:.3f}")
    else:
        upper = summary[tail_quantiles & (summary["specification"] == "corrected")]["mean_beta"].mean()
        middle = summary[summary["quantile"].isin([40, 50, 60]) & (summary["specification"] == "corrected")][
            "mean_beta"
        ].mean()
        print("Upper-tail DGP: high latent-state firms have a stronger negative treatment effect.")
        print(f"Corrected mean beta in middle quantiles: {middle:.4f}")
        print(f"Corrected mean beta in Q80/Q90:          {upper:.4f}")
        print("Coverage of zero is not the target in this power design; rejection rates are power against a zero-effect null.")


def parse_quantiles(value: str) -> tuple[int, ...]:
    """Parse comma-separated quantiles."""
    quantiles = tuple(int(v.strip()) for v in value.split(",") if v.strip())
    if not quantiles:
        raise argparse.ArgumentTypeError("At least one quantile is required.")
    if any(q <= 0 or q >= 100 for q in quantiles):
        raise argparse.ArgumentTypeError("Quantiles must be between 1 and 99.")
    return quantiles


def load_empirical_residuals(path: str | None, col: str | None) -> np.ndarray | None:
    """Load empirical residual draws from CSV when requested."""
    if path is None:
        return None
    residual_df = pd.read_csv(path)
    if col is None:
        if residual_df.shape[1] != 1:
            raise ValueError("Specify --empirical_residual_col when the CSV has more than one column.")
        col = residual_df.columns[0]
    residuals = residual_df[col].dropna().to_numpy(dtype=float)
    if residuals.size == 0:
        raise ValueError("The empirical residual vector is empty after dropping missing values.")
    return residuals


def make_run_label(args: argparse.Namespace) -> str:
    """Create a filesystem-safe run label."""
    theta = f"{args.theta:.2f}".replace(".", "p").replace("-", "m")
    return (
        f"mc_{args.true_effect}_{args.mode}_theta{theta}_"
        f"p{args.poly_degree}_{args.error_dist}_R{args.R}"
    )


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Monte Carlo for grouped-IV quantile order-statistic bias.")
    parser.add_argument("--R", type=int, default=2000, help="Number of Monte Carlo replications.")
    parser.add_argument("--J", type=int, default=70, help="Number of sectors.")
    parser.add_argument("--T", type=int, default=9, help="Number of years.")
    parser.add_argument("--seed", type=int, default=90210, help="Base random seed.")
    parser.add_argument("--mode", choices=["independent", "correlated"], default="correlated", help="Cell-size DGP.")
    parser.add_argument("--theta", type=float, default=0.4, help="Correlation of log cell size with residualized Z.")
    parser.add_argument("--poly_degree", type=int, default=3, help="Polynomial degree for n_jt control function.")
    parser.add_argument("--pi", type=float, default=0.89, help="First-stage coefficient on Z_output.")
    parser.add_argument("--lambda_input", type=float, default=0.15, help="First-stage coefficient on Z_input.")
    parser.add_argument("--error_dist", choices=["normal", "student", "empirical"], default="normal")
    parser.add_argument("--error_scale", type=float, default=0.20)
    parser.add_argument("--student_df", type=float, default=5.0)
    parser.add_argument("--empirical_residual_csv", type=str, default=None)
    parser.add_argument("--empirical_residual_col", type=str, default=None)
    parser.add_argument("--true_effect", choices=["null", "upper_tail"], default="null")
    parser.add_argument("--beta_low", type=float, default=0.0)
    parser.add_argument("--beta_high", type=float, default=-0.5)
    parser.add_argument("--state_loading", type=float, default=0.35)
    parser.add_argument("--min_n", type=int, default=10)
    parser.add_argument("--max_n", type=int, default=250)
    parser.add_argument("--quantiles", type=parse_quantiles, default=DEFAULT_QUANTILES)
    parser.add_argument("--quantile_method", choices=["order", "linear"], default="order")
    parser.add_argument(
        "--output_dir",
        type=Path,
        default=Path("output") / "monte_carlo" / "order_stat_bias",
        help="Directory for CSV, LaTeX, and PNG outputs.",
    )
    parser.add_argument("--no_plots", action="store_true", help="Skip PNG figure creation.")
    parser.add_argument("--no_progress", action="store_true", help="Disable tqdm progress bar.")
    parser.add_argument(
        "--no_linearmodels",
        action="store_true",
        help="Use the built-in manual 2SLS estimator even if linearmodels is installed.",
    )
    return parser


def main() -> None:
    args = build_arg_parser().parse_args()

    if args.poly_degree < 1:
        raise ValueError("--poly_degree must be at least 1.")
    if args.R < 1:
        raise ValueError("--R must be positive.")

    empirical_residuals = load_empirical_residuals(args.empirical_residual_csv, args.empirical_residual_col)
    cfg = SimulationConfig(
        J=args.J,
        T=args.T,
        pi=args.pi,
        lambda_input=args.lambda_input,
        theta=args.theta,
        mode=args.mode,
        true_effect=args.true_effect,
        beta_low=args.beta_low,
        beta_high=args.beta_high,
        state_loading=args.state_loading,
        min_n=args.min_n,
        max_n=args.max_n,
        error_dist=args.error_dist,
        error_scale=args.error_scale,
        student_df=args.student_df,
        quantiles=args.quantiles,
        quantile_method=args.quantile_method,
        empirical_residuals=empirical_residuals,
    )

    prefer_linearmodels = not args.no_linearmodels
    if prefer_linearmodels and IV2SLS is None:
        print("linearmodels is not installed; using built-in manual 2SLS with clustered standard errors.")

    results = run_monte_carlo(
        R=args.R,
        seed=args.seed,
        cfg=cfg,
        poly_degree=args.poly_degree,
        prefer_linearmodels=prefer_linearmodels,
        show_progress=not args.no_progress,
    )
    summary = summarize_results(results)
    label = make_run_label(args)
    saved = write_outputs(results, summary, args.output_dir, label, make_plots=not args.no_plots)

    print_interpretation(summary, cfg)
    print("\nSaved outputs")
    print("-------------")
    for path in saved:
        print(path)


if __name__ == "__main__":
    main()
