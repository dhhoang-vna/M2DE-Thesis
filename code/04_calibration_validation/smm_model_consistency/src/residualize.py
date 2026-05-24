from __future__ import annotations

import numpy as np
import pandas as pd


def _as_numeric_frame(df: pd.DataFrame, cols: list[str]) -> pd.DataFrame:
    out = pd.DataFrame(index=df.index)
    for col in cols:
        if col in df.columns:
            out[col] = pd.to_numeric(df[col], errors="coerce")
    return out


def build_design(
    df: pd.DataFrame,
    controls: list[str] | None = None,
    fixed_effects: list[str] | None = None,
) -> np.ndarray:
    parts: list[pd.DataFrame] = []
    n = len(df)
    parts.append(pd.DataFrame({"const": np.ones(n, dtype=float)}, index=df.index))

    controls = controls or []
    numeric = _as_numeric_frame(df, [c for c in controls if c in df.columns])
    if not numeric.empty:
        numeric = numeric.replace([np.inf, -np.inf], np.nan)
        numeric = numeric.fillna(numeric.mean()).fillna(0.0)
        keep = [c for c in numeric.columns if numeric[c].std(ddof=0) > 1.0e-12]
        if keep:
            parts.append(numeric[keep])

    for fe in fixed_effects or []:
        if fe not in df.columns:
            continue
        s = df[fe].astype("string").fillna("__missing__")
        dummies = pd.get_dummies(s, prefix=fe, drop_first=True, dtype=float)
        if not dummies.empty:
            parts.append(dummies)

    X = pd.concat(parts, axis=1).to_numpy(dtype=float)
    keep_cols = np.isfinite(X).all(axis=0) & (np.nanstd(X, axis=0) > 1.0e-12)
    keep_cols[0] = True
    return X[:, keep_cols]


def residualize_matrix(
    values: np.ndarray,
    df: pd.DataFrame,
    controls: list[str] | None = None,
    fixed_effects: list[str] | None = None,
) -> np.ndarray:
    Y = np.asarray(values, dtype=float)
    if Y.ndim == 1:
        Y = Y.reshape(-1, 1)
    X = build_design(df, controls=controls, fixed_effects=fixed_effects)
    coef, *_ = np.linalg.lstsq(X, Y, rcond=None)
    return Y - X @ coef


def residualize_series(
    s: pd.Series,
    df: pd.DataFrame,
    controls: list[str] | None = None,
    fixed_effects: list[str] | None = None,
) -> pd.Series:
    resid = residualize_matrix(s.to_numpy(dtype=float), df, controls, fixed_effects).ravel()
    return pd.Series(resid, index=df.index, name=s.name)

