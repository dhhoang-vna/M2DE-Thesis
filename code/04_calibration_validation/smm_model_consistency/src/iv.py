from __future__ import annotations

from dataclasses import dataclass
from math import erf, sqrt

import numpy as np
import pandas as pd

from .residualize import residualize_matrix


@dataclass
class RegressionResult:
    name: str
    coefficients: dict[str, float]
    standard_errors: dict[str, float]
    tstats: dict[str, float]
    pvalues: dict[str, float]
    nobs: int
    nclusters: int
    first_stage_f: float | None = None

    def coef(self, key: str) -> float:
        return self.coefficients.get(key, np.nan)

    def se(self, key: str) -> float:
        return self.standard_errors.get(key, np.nan)


def _normal_pvalue(t: float) -> float:
    if not np.isfinite(t):
        return np.nan
    cdf = 0.5 * (1.0 + erf(abs(t) / sqrt(2.0)))
    return max(0.0, min(1.0, 2.0 * (1.0 - cdf)))


def _prepare(
    df: pd.DataFrame,
    y: str,
    endog: list[str],
    instruments: list[str],
    controls: list[str] | None,
    fixed_effects: list[str] | None,
    cluster: str | None,
) -> tuple[pd.DataFrame, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    cols = [y] + endog + instruments
    if controls:
        cols += [c for c in controls if c in df.columns]
    if fixed_effects:
        cols += [c for c in fixed_effects if c in df.columns]
    if cluster and cluster in df.columns:
        cols.append(cluster)
    cols = list(dict.fromkeys(cols))
    work = df.loc[:, [c for c in cols if c in df.columns]].copy()
    for col in [y] + endog + instruments + [c for c in (controls or []) if c in work.columns]:
        work[col] = pd.to_numeric(work[col], errors="coerce")
    need = [y] + endog + instruments
    if cluster and cluster in work.columns:
        need.append(cluster)
    work = work.replace([np.inf, -np.inf], np.nan).dropna(subset=need)
    if len(work) == 0:
        raise ValueError("No usable observations after dropping missing data.")

    YXZ = work[[y] + endog + instruments].to_numpy(dtype=float)
    R = residualize_matrix(YXZ, work, controls=controls or [], fixed_effects=fixed_effects or [])
    y_r = R[:, [0]]
    x_r = R[:, 1 : 1 + len(endog)]
    z_r = R[:, 1 + len(endog) :]
    if cluster and cluster in work.columns:
        clusters = work[cluster].astype("string").to_numpy()
    else:
        clusters = np.arange(len(work)).astype(str)
    return work, y_r, x_r, z_r, clusters


def iv_2sls(
    df: pd.DataFrame,
    y: str,
    endog: str | list[str],
    instruments: str | list[str],
    controls: list[str] | None = None,
    fixed_effects: list[str] | None = None,
    cluster: str | None = None,
    name: str = "iv",
) -> RegressionResult:
    endog_cols = [endog] if isinstance(endog, str) else list(endog)
    inst_cols = [instruments] if isinstance(instruments, str) else list(instruments)
    if len(inst_cols) < len(endog_cols):
        raise ValueError("Need at least as many excluded instruments as endogenous variables.")
    work, y_r, x_r, z_r, clusters = _prepare(df, y, endog_cols, inst_cols, controls, fixed_effects, cluster)

    ztz_inv = np.linalg.pinv(z_r.T @ z_r)
    a = x_r.T @ z_r @ ztz_inv @ z_r.T @ x_r
    b = x_r.T @ z_r @ ztz_inv @ z_r.T @ y_r
    beta = np.linalg.pinv(a) @ b
    resid = y_r - x_r @ beta

    unique_clusters = pd.unique(clusters)
    s = np.zeros((z_r.shape[1], z_r.shape[1]), dtype=float)
    for g in unique_clusters:
        idx = clusters == g
        zg = z_r[idx, :]
        ug = resid[idx, :]
        moment = zg.T @ ug
        s += moment @ moment.T

    middle = x_r.T @ z_r @ ztz_inv @ s @ ztz_inv @ z_r.T @ x_r
    bread = np.linalg.pinv(a)
    vcov = bread @ middle @ bread
    if len(unique_clusters) > 1:
        n = len(work)
        k = x_r.shape[1] + (len(controls or []) + len(fixed_effects or []))
        vcov *= (len(unique_clusters) / (len(unique_clusters) - 1.0)) * ((n - 1.0) / max(n - k, 1.0))

    se = np.sqrt(np.maximum(np.diag(vcov), 0.0))
    coefs = {col: float(beta[i, 0]) for i, col in enumerate(endog_cols)}
    ses = {col: float(se[i]) for i, col in enumerate(endog_cols)}
    tstats = {col: coefs[col] / ses[col] if ses[col] > 0 else np.nan for col in endog_cols}
    pvals = {col: _normal_pvalue(tstats[col]) for col in endog_cols}

    fs_f = None
    if len(endog_cols) >= 1 and len(inst_cols) >= 1:
        fs_f = first_stage_f_stat(work, endog_cols[0], inst_cols[0], controls, fixed_effects, cluster)

    return RegressionResult(name, coefs, ses, tstats, pvals, len(work), len(unique_clusters), fs_f)


def first_stage_f_stat(
    df: pd.DataFrame,
    x: str,
    z: str,
    controls: list[str] | None = None,
    fixed_effects: list[str] | None = None,
    cluster: str | None = None,
) -> float:
    work, y_r, x_r, _z_unused, clusters = _prepare(
        df,
        y=x,
        endog=[z],
        instruments=[z],
        controls=controls,
        fixed_effects=fixed_effects,
        cluster=cluster,
    )
    xr = y_r
    zr = x_r
    denom = float((zr.T @ zr).item())
    if abs(denom) < 1.0e-14:
        return np.nan
    alpha = float(((zr.T @ xr) / denom).item())
    resid = xr - alpha * zr
    unique_clusters = pd.unique(clusters)
    meat = 0.0
    for g in unique_clusters:
        idx = clusters == g
        moment = float((zr[idx].T @ resid[idx]).item())
        meat += moment * moment
    var = meat / (denom * denom)
    if len(unique_clusters) > 1:
        n = len(work)
        var *= (len(unique_clusters) / (len(unique_clusters) - 1.0)) * ((n - 1.0) / max(n - 2.0, 1.0))
    if var <= 0:
        return np.nan
    return float((alpha / np.sqrt(var)) ** 2)


def ols_fwl(
    df: pd.DataFrame,
    y: str,
    x: str,
    controls: list[str] | None = None,
    fixed_effects: list[str] | None = None,
    cluster: str | None = None,
    name: str = "ols",
) -> RegressionResult:
    work, y_r, x_r, _z, clusters = _prepare(
        df,
        y=y,
        endog=[x],
        instruments=[x],
        controls=controls,
        fixed_effects=fixed_effects,
        cluster=cluster,
    )
    denom = float((x_r.T @ x_r).item())
    if abs(denom) < 1.0e-14:
        raise ValueError("Residualized regressor has near-zero variance.")
    beta = float(((x_r.T @ y_r) / denom).item())
    resid = y_r - beta * x_r
    unique_clusters = pd.unique(clusters)
    meat = 0.0
    for g in unique_clusters:
        idx = clusters == g
        moment = float((x_r[idx].T @ resid[idx]).item())
        meat += moment * moment
    var = meat / (denom * denom)
    if len(unique_clusters) > 1:
        n = len(work)
        var *= (len(unique_clusters) / (len(unique_clusters) - 1.0)) * ((n - 1.0) / max(n - 2.0, 1.0))
    se = float(np.sqrt(max(var, 0.0)))
    t = beta / se if se > 0 else np.nan
    return RegressionResult(
        name=name,
        coefficients={x: beta},
        standard_errors={x: se},
        tstats={x: t},
        pvalues={x: _normal_pvalue(t)},
        nobs=len(work),
        nclusters=len(unique_clusters),
    )


def result_to_moment(result: RegressionResult, key: str, name: str, kind: str) -> dict[str, float | str]:
    return {
        "moment": name,
        "kind": kind,
        "value": result.coef(key),
        "se": result.se(key),
        "nobs": result.nobs,
        "nclusters": result.nclusters,
        "first_stage_f": result.first_stage_f if result.first_stage_f is not None else np.nan,
    }
