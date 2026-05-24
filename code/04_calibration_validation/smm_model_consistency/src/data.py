from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd


def _available_stata_columns(path: Path) -> list[str]:
    with pd.read_stata(path, chunksize=1, convert_categoricals=False) as reader:
        first = next(reader)
        return list(first.columns)


def _read_stata_some(path: Path, wanted: list[str]) -> pd.DataFrame:
    available = _available_stata_columns(path)
    cols = [c for c in wanted if c in available]
    missing = sorted(set(wanted) - set(cols))
    if missing:
        print(f"Skipping unavailable columns in {path.name}: {missing}")
    return pd.read_stata(path, columns=cols, convert_categoricals=False)


def _safe_numeric(s: pd.Series) -> pd.Series:
    return pd.to_numeric(s, errors="coerce").replace([np.inf, -np.inf], np.nan)


def needed_columns(cfg: dict[str, Any]) -> list[str]:
    c = cfg["columns"]
    base = [
        c["firm_id"],
        c["sector"],
        c["year"],
        c["markup"],
        c["log_markup"],
        c["dlog_markup"],
        c["share"],
        c["sales"],
        c["import_penetration"],
        c["treatment"],
        c["instrument"],
        c["input_shock"],
        c["exit"],
        c["hhi"],
        c["cr10"],
        c["cr4"],
        "rank_sales",
        "age",
        "leverage",
        "lnSize",
        "liquidity_ratio_x_",
        "exporter",
        "export_revenue",
        "ls_pre_filled",
        "post2016",
        "H_china_dep",
        "material_costs",
        "costs_of_employees",
        "operating_revenue_turnover_",
    ]
    for col in ["l_age", "l_leverage", "l_lnSize", "l_liquidity_ratio_x_", "l_exporter"]:
        base.append(col)
    return list(dict.fromkeys([b for b in base if b]))


def load_panel(cfg: dict[str, Any]) -> pd.DataFrame:
    path = Path(cfg["paths"]["data"])
    if not path.exists():
        raise FileNotFoundError(f"Cannot find configured data file: {path}")
    df = _read_stata_some(path, needed_columns(cfg))
    df = standardize_panel(df, cfg)
    return df


def standardize_panel(df: pd.DataFrame, cfg: dict[str, Any]) -> pd.DataFrame:
    c = cfg["columns"]
    rename = {
        c["firm_id"]: "firm_id",
        c["sector"]: "isic4",
        c["year"]: "year",
        c["markup"]: "mu",
        c["log_markup"]: "ln_mu",
        c["dlog_markup"]: "dln_mu",
        c["share"]: "share_sales",
        c["sales"]: "dom_sales",
        c["import_penetration"]: "IP",
        c["treatment"]: "change_IP",
        c["instrument"]: "output_IV",
        c["input_shock"]: "Z_input",
        c["exit"]: "exit",
        c["hhi"]: "HHI_dom",
        c["cr10"]: "CR10_dom",
        c["cr4"]: "CR4_dom",
    }
    rename = {k: v for k, v in rename.items() if k in df.columns and k != v}
    df = df.rename(columns=rename).copy()

    for col in df.columns:
        if col not in ["firm_id"]:
            df[col] = _safe_numeric(df[col])
    for col in ["firm_id", "isic4", "year"]:
        if col in df.columns:
            df[col] = _safe_numeric(df[col])
    df = df.dropna(subset=["firm_id", "isic4", "year"])
    df["firm_id"] = df["firm_id"].astype("int64")
    df["isic4"] = df["isic4"].astype("int64")
    df["year"] = df["year"].astype("int64")

    if "mu" in df.columns and "ln_mu" not in df.columns:
        df["ln_mu"] = np.log(df["mu"].where(df["mu"] > 0))
    if "ln_mu" in df.columns and "mu" not in df.columns:
        df["mu"] = np.exp(df["ln_mu"])
    if "inv_mu" not in df.columns and "mu" in df.columns:
        df["inv_mu"] = 1.0 / df["mu"].where(df["mu"] > 0)

    if "share_sales" not in df.columns and "dom_sales" in df.columns:
        total = df.groupby(["isic4", "year"])["dom_sales"].transform("sum")
        df["share_sales"] = df["dom_sales"] / total.replace(0.0, np.nan)
    if "share_sales" in df.columns:
        df["share_sales"] = df["share_sales"].clip(lower=0.0)
        share_sum = df.groupby(["isic4", "year"])["share_sales"].transform("sum")
        bad_norm = share_sum.isna() | (share_sum <= 0)
        if "dom_sales" in df.columns:
            dom_total = df.groupby(["isic4", "year"])["dom_sales"].transform("sum").replace(0.0, np.nan)
            dom_share = df["dom_sales"] / dom_total
            df.loc[bad_norm, "share_sales"] = dom_share.loc[bad_norm]
        share_sum = df.groupby(["isic4", "year"])["share_sales"].transform("sum").replace(0.0, np.nan)
        df["share_sales"] = df["share_sales"] / share_sum

    if "exporter" not in df.columns:
        if "export_revenue" in df.columns:
            df["exporter"] = (df["export_revenue"] > 0).astype(float)
        else:
            df["exporter"] = 0.0
    if "post2016" not in df.columns:
        df["post2016"] = (df["year"] >= 2016).astype(float)
    df["post2016"] = df["post2016"].fillna((df["year"] >= 2016).astype(float))
    if "ls_pre_filled" not in df.columns:
        df["ls_pre_filled"] = 0.0
    df["ls_pre_x_post2016"] = df["ls_pre_filled"].fillna(0.0) * df["post2016"].fillna(0.0)

    df = df.sort_values(["firm_id", "year"])
    lag_sources = ["age", "leverage", "lnSize", "liquidity_ratio_x_", "exporter", "ln_mu", "share_sales", "inv_mu"]
    for src in lag_sources:
        if src not in df.columns:
            continue
        lag_name = f"l_{src}"
        if lag_name not in df.columns:
            df[lag_name] = df.groupby("firm_id")[src].shift(1)

    if "dln_mu" not in df.columns and "ln_mu" in df.columns:
        df["dln_mu"] = df["ln_mu"] - df["l_ln_mu"]

    if "HHI_dom" not in df.columns:
        df["HHI_dom"] = df.groupby(["isic4", "year"])["share_sales"].transform(lambda s: np.nansum(np.square(s)))
    if "CR4_dom" not in df.columns:
        if "rank_sales" in df.columns:
            df["CR4_dom"] = df.assign(_top4=df["share_sales"].where(df["rank_sales"] <= 4, 0.0)).groupby(
                ["isic4", "year"]
            )["_top4"].transform("sum")
        else:
            rank = df.groupby(["isic4", "year"])["share_sales"].rank(method="first", ascending=False)
            df["CR4_dom"] = df.assign(_top4=df["share_sales"].where(rank <= 4, 0.0)).groupby(
                ["isic4", "year"]
            )["_top4"].transform("sum")
    if "CR10_dom" not in df.columns:
        if "rank_sales" in df.columns:
            df["CR10_dom"] = df.assign(_top10=df["share_sales"].where(df["rank_sales"] <= 10, 0.0)).groupby(
                ["isic4", "year"]
            )["_top10"].transform("sum")
        else:
            rank = df.groupby(["isic4", "year"])["share_sales"].rank(method="first", ascending=False)
            df["CR10_dom"] = df.assign(_top10=df["share_sales"].where(rank <= 10, 0.0)).groupby(
                ["isic4", "year"]
            )["_top10"].transform("sum")

    df["n_firms"] = df.groupby(["isic4", "year"])["firm_id"].transform("nunique")
    df["dom_sales_j"] = df.groupby(["isic4", "year"])["dom_sales"].transform("sum") if "dom_sales" in df.columns else np.nan
    df["firm_weight"] = df["dom_sales"].where(df.get("dom_sales", pd.Series(np.nan, index=df.index)) > 0, 1.0)

    if "H_china_dep" in df.columns:
        df["input_exposure_i"] = df["H_china_dep"]
    elif "material_costs" in df.columns and "operating_revenue_turnover_" in df.columns:
        df["input_exposure_i"] = df["material_costs"] / df["operating_revenue_turnover_"].replace(0.0, np.nan)
    else:
        df["input_exposure_i"] = df["share_sales"]
    df["input_exposure_i"] = df["input_exposure_i"].replace([np.inf, -np.inf], np.nan).fillna(0.0)

    for col in ["change_IP", "output_IV", "Z_input", "IP"]:
        if col not in df.columns:
            df[col] = 0.0

    y0 = int(cfg["sample"]["year_min"])
    y1 = int(cfg["sample"]["year_max"])
    df = df.loc[(df["year"] >= y0) & (df["year"] <= y1)].copy()
    min_firms = int(cfg["sample"].get("min_sector_year_firms", 1))
    if min_firms > 1:
        df = df.loc[df["n_firms"] >= min_firms].copy()

    max_firms = cfg["sample"].get("max_firms")
    if max_firms:
        firms = pd.Series(df["firm_id"].drop_duplicates())
        if len(firms) > int(max_firms):
            keep = firms.sample(n=int(max_firms), random_state=int(cfg["sample"].get("random_seed", 20260510)))
            df = df.loc[df["firm_id"].isin(keep)].copy()
            df["n_firms"] = df.groupby(["isic4", "year"])["firm_id"].transform("nunique")
            if min_firms > 1:
                df = df.loc[df["n_firms"] >= min_firms].copy()

    return df


def sector_panel(
    df: pd.DataFrame,
    inv_col: str = "inv_mu",
    share_col: str = "share_sales",
    dln_col: str = "dln_mu",
) -> pd.DataFrame:
    work = df.copy()
    work[inv_col] = _safe_numeric(work[inv_col])
    work[share_col] = _safe_numeric(work[share_col])
    work["_weighted_inv"] = work[share_col] * work[inv_col]
    work["_weighted_lnmu"] = work[share_col] * np.log(1.0 / work[inv_col].where(work[inv_col] > 0))
    grouped = work.groupby(["isic4", "year"], as_index=False)
    sec = grouped.agg(
        inv_mu_j=("_weighted_inv", "sum"),
        ln_mu_j=("_weighted_lnmu", "sum"),
        HHI_dom=(share_col, lambda s: float(np.nansum(np.square(s)))),
        CR4_dom=(share_col, lambda s: float(np.nansum(np.sort(s.dropna().to_numpy())[-4:]))),
        CR10_dom=(share_col, lambda s: float(np.nansum(np.sort(s.dropna().to_numpy())[-10:]))),
        n_firms=("firm_id", "nunique"),
        dom_j=("dom_sales", "sum"),
        change_IP=("change_IP", "mean"),
        output_IV=("output_IV", "mean"),
        Z_input=("Z_input", "mean"),
        ls_pre_filled=("ls_pre_filled", "mean"),
        post2016=("post2016", "mean"),
    )
    sec["mu_j"] = 1.0 / sec["inv_mu_j"].replace(0.0, np.nan)
    sec["ln_mu_j"] = np.log(sec["mu_j"].where(sec["mu_j"] > 0))
    sec = sec.sort_values(["isic4", "year"])
    sec["d_inv_mu_j"] = sec["inv_mu_j"] - sec.groupby("isic4")["inv_mu_j"].shift(1)
    sec["d_ln_mu_j"] = sec["ln_mu_j"] - sec.groupby("isic4")["ln_mu_j"].shift(1)
    sec["ls_pre_x_post2016"] = sec["ls_pre_filled"].fillna(0.0) * sec["post2016"].fillna(0.0)
    sec["S_jt"] = sec["dom_j"] / sec.groupby("year")["dom_j"].transform("sum").replace(0.0, np.nan)
    if dln_col in work.columns:
        q = work.groupby(["isic4", "year"])[dln_col].quantile([0.75, 0.80, 0.85, 0.90]).unstack()
        q.columns = [f"q{int(round(float(c) * 100))}_{dln_col}" for c in q.columns]
        sec = sec.merge(q.reset_index(), on=["isic4", "year"], how="left")
    return sec


def manufacturing_panel(sec: pd.DataFrame) -> pd.DataFrame:
    work = sec.copy()
    work["_w_inv"] = work["S_jt"] * work["inv_mu_j"]
    out = work.groupby("year", as_index=False).agg(
        inv_mu_m=("_w_inv", "sum"),
        sectors=("isic4", "nunique"),
        total_dom_sales=("dom_j", "sum"),
    )
    out["mu_m"] = 1.0 / out["inv_mu_m"].replace(0.0, np.nan)
    return out
