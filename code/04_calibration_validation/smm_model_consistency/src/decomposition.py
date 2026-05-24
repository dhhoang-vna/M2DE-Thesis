from __future__ import annotations

import numpy as np
import pandas as pd


def _weighted_mean(x: pd.Series, w: pd.Series) -> float:
    xv = pd.to_numeric(x, errors="coerce")
    wv = pd.to_numeric(w, errors="coerce").fillna(0.0)
    ok = xv.notna() & wv.notna() & (wv > 0)
    if ok.sum() == 0:
        return np.nan
    return float(np.average(xv.loc[ok], weights=wv.loc[ok]))


def _normalize_sector_shares(df: pd.DataFrame, share_col: str = "s_t", sales_col: str = "dom_sales") -> pd.DataFrame:
    out = df.copy()
    out[share_col] = pd.to_numeric(out.get(share_col), errors="coerce")
    sales = pd.to_numeric(out.get(sales_col), errors="coerce") if sales_col in out.columns else pd.Series(np.nan, index=out.index)
    out["_s_raw"] = out[share_col].where(out[share_col] >= 0)
    fallback = sales.where(sales > 0)
    out["_s_for_norm"] = out["_s_raw"].fillna(fallback)
    denom = out.groupby(["isic4_t", "year"])["_s_for_norm"].transform("sum").replace(0.0, np.nan)
    out["s_t"] = out["_s_for_norm"] / denom
    out = out.drop(columns=["_s_raw", "_s_for_norm"])
    return out


def decompose_inverse_markup(
    df: pd.DataFrame,
    inv_col: str = "inv_mu",
    share_col: str = "share_sales",
    sales_col: str = "dom_sales",
) -> pd.DataFrame:
    """Decompose sector inverse-markup changes using the Stata recipe.

    This mirrors `dofile analysis/3 decomposition (2).do`:
    - continuer: observed in t-1 and t in the same sector,
    - entrant: observed in t but not as continuer (excluding first sample year),
    - exit: identified on row t-1 and shifted forward to year t.
    """
    cols = [
        "firm_id",
        "isic4",
        "year",
        share_col,
        inv_col,
        sales_col,
        "change_IP",
        "output_IV",
        "Z_input",
        "ls_pre_filled",
        "post2016",
    ]
    cols = [c for c in cols if c in df.columns]
    work = df[cols].copy().sort_values(["firm_id", "year"])
    work = work.rename(columns={share_col: "s_t", inv_col: "inv_t"})

    # Stata-style lags and leads.
    work["l_share"] = work.groupby("firm_id")["s_t"].shift(1)
    work["l_inv_mu"] = work.groupby("firm_id")["inv_t"].shift(1)
    work["l_year"] = work.groupby("firm_id")["year"].shift(1)
    work["l_isic4"] = work.groupby("firm_id")["isic4"].shift(1)
    work["f_year"] = work.groupby("firm_id")["year"].shift(-1)
    work["f_isic4"] = work.groupby("firm_id")["isic4"].shift(-1)

    min_year = int(work["year"].min())
    max_year = int(work["year"].max())

    work["continuer"] = (work["l_year"] == work["year"] - 1) & (work["l_isic4"] == work["isic4"])
    work["entrant"] = (work["year"] > min_year) & (~work["continuer"])
    valid_current = work[["year", "isic4", "s_t", "inv_t"]].notna().all(axis=1)
    work.loc[~valid_current, "entrant"] = False

    # Exit is defined on row t-1 and shifted to year t.
    missing_or_break = work["f_year"].isna() | (work["f_year"] != work["year"] + 1) | (work["f_isic4"] != work["isic4"])
    work["exiter_next"] = valid_current & missing_or_break
    work.loc[work["year"] == max_year, "exiter_next"] = False

    work["contrib_within"] = np.where(
        work["continuer"],
        0.5 * (work["s_t"] + work["l_share"]) * (work["inv_t"] - work["l_inv_mu"]),
        0.0,
    )
    work["contrib_between"] = np.where(
        work["continuer"],
        0.5 * (work["inv_t"] + work["l_inv_mu"]) * (work["s_t"] - work["l_share"]),
        0.0,
    )
    work["contrib_entry"] = np.where(work["entrant"], work["s_t"] * work["inv_t"], 0.0)

    exit_rows = work.loc[work["exiter_next"], ["isic4", "year", "s_t", "inv_t"]].copy()
    exit_rows["year"] = exit_rows["year"] + 1
    exit_rows["exit_inv_mu"] = exit_rows["s_t"] * exit_rows["inv_t"]
    exit_term = exit_rows.groupby(["isic4", "year"], as_index=False)["exit_inv_mu"].sum()

    comp = work.groupby(["isic4", "year"], as_index=False).agg(
        within_inv_mu=("contrib_within", "sum"),
        between_inv_mu=("contrib_between", "sum"),
        entry_inv_mu=("contrib_entry", "sum"),
    )
    comp = comp.merge(exit_term, on=["isic4", "year"], how="left")
    comp["exit_inv_mu"] = comp["exit_inv_mu"].fillna(0.0)
    comp["d_inv_mu_j_components"] = (
        comp["within_inv_mu"] + comp["between_inv_mu"] + comp["entry_inv_mu"] - comp["exit_inv_mu"]
    )
    grouped = df.groupby(["isic4", "year"], as_index=False)
    controls = grouped.agg(
        n_firms=("firm_id", "nunique"),
        dom_j=(sales_col, "sum") if sales_col in df.columns else ("firm_id", "size"),
        ls_pre_filled=("ls_pre_filled", "mean"),
        post2016=("post2016", "mean"),
    )
    weight_col = sales_col if sales_col in df.columns else None
    for col in ["change_IP", "output_IV", "Z_input"]:
        if col in df.columns:
            if weight_col is not None:
                weighted = (
                    df.groupby(["isic4", "year"])
                    .apply(lambda g: _weighted_mean(g[col], g[weight_col]), include_groups=False)
                    .reset_index(name=col)
                )
            else:
                weighted = grouped[col].mean().rename(columns={col: col})
            controls = controls.merge(weighted, on=["isic4", "year"], how="left")
    comp = comp.merge(controls, on=["isic4", "year"], how="left")
    comp["ls_pre_x_post2016"] = comp["ls_pre_filled"].fillna(0.0) * comp["post2016"].fillna(0.0)

    denom = (
        comp["within_inv_mu"].abs()
        + comp["between_inv_mu"].abs()
        + comp["entry_inv_mu"].abs()
        + comp["exit_inv_mu"].abs()
    ).replace(0.0, np.nan)
    for col in ["within_inv_mu", "between_inv_mu", "entry_inv_mu", "exit_inv_mu"]:
        comp[f"{col}_abs_share"] = comp[col].abs() / denom
    return comp


def gross_absolute_component_shares(
    comp: pd.DataFrame,
    *,
    weight_col: str = "dom_j",
    exclude_first_year: bool = True,
    exclude_years: list[int] | None = None,
) -> dict[str, float]:
    """Return pooled size-weighted gross-absolute shares (Stata-equivalent)."""
    work = comp.copy()
    if exclude_first_year and "year" in work.columns and work["year"].notna().any():
        work = work.loc[work["year"] > work["year"].min()].copy()
    if exclude_years and "year" in work.columns:
        work = work.loc[~work["year"].isin([int(y) for y in exclude_years])].copy()

    cols = ["within_inv_mu", "between_inv_mu", "entry_inv_mu", "exit_inv_mu"]
    abs_cols = [f"abs_{c}" for c in cols]
    for c, a in zip(cols, abs_cols):
        work[a] = pd.to_numeric(work[c], errors="coerce").abs()
    work["gross_decomp_total"] = work[abs_cols].sum(axis=1)

    # Match Stata: keep positive gross mass rows with valid year and dom_j.
    work = work.loc[(work["gross_decomp_total"] > 0) & work["year"].notna()].copy()
    if weight_col in work.columns:
        weight = pd.to_numeric(work[weight_col], errors="coerce")
        work = work.loc[weight.notna()].copy()
        weight = pd.to_numeric(work[weight_col], errors="coerce").fillna(0.0).clip(lower=0.0)
    else:
        weight = pd.Series(1.0, index=work.index)

    cols = ["within_inv_mu", "between_inv_mu", "entry_inv_mu", "exit_inv_mu"]

    masses = {col: float((work[f"abs_{col}"] * weight).sum()) for col in cols}
    total = sum(masses.values())
    if total <= 0.0:
        return {col: np.nan for col in cols}
    return {col: value / total for col, value in masses.items()}


def manufacturing_decomposition(sec: pd.DataFrame) -> pd.DataFrame:
    work = sec.sort_values(["isic4", "year"]).copy()
    work["S_lag"] = work.groupby("isic4")["S_jt"].shift(1)
    work["inv_lag"] = work.groupby("isic4")["inv_mu_j"].shift(1)
    cont = work["S_lag"].notna() & work["inv_lag"].notna()
    work["within_sector"] = np.where(cont, 0.5 * (work["S_jt"] + work["S_lag"]) * (work["inv_mu_j"] - work["inv_lag"]), 0.0)
    work["between_sector"] = np.where(cont, 0.5 * (work["inv_mu_j"] + work["inv_lag"]) * (work["S_jt"] - work["S_lag"]), 0.0)
    out = work.groupby("year", as_index=False)[["within_sector", "between_sector"]].sum()
    out["d_inv_mu_m"] = out["within_sector"] + out["between_sector"]
    return out
