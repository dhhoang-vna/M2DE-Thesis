from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from .data import sector_panel
from .decomposition import decompose_inverse_markup, gross_absolute_component_shares
from .iv import iv_2sls, ols_fwl, result_to_moment


def _moment_row(
    name: str,
    value: float,
    kind: str,
    se: float = np.nan,
    nobs: int = 0,
    nclusters: int = 0,
    *,
    metadata: dict[str, Any] | None = None,
) -> dict:
    row = {
        "moment": name,
        "kind": kind,
        "value": float(value) if np.isfinite(value) else np.nan,
        "se": float(se) if np.isfinite(se) else np.nan,
        "nobs": int(nobs) if nobs else np.nan,
        "nclusters": int(nclusters) if nclusters else np.nan,
        "first_stage_f": np.nan,
    }
    if metadata:
        row.update(metadata)
    return row


def _controls(cfg: dict[str, Any], level: str, data: pd.DataFrame) -> list[str]:
    return [c for c in cfg["controls"][level] if c in data.columns]


def _fe(cfg: dict[str, Any], data: pd.DataFrame) -> list[str]:
    return [c for c in cfg["controls"]["fixed_effects"] if c in data.columns]


def _cluster(cfg: dict[str, Any], data: pd.DataFrame) -> str | None:
    c = cfg["controls"].get("cluster")
    return c if c in data.columns else None


def add_concentration_interactions(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    conc = out["HHI_dom"] if "HHI_dom" in out.columns else out.get("CR4_dom", pd.Series(np.nan, index=out.index))
    out["conc_c"] = conc - conc.mean(skipna=True)
    out["changeIP_x_conc"] = out["change_IP"] * out["conc_c"]
    out["outputIV_x_conc"] = out["output_IV"] * out["conc_c"]
    return out


def _selection_corrected_output_iv(panel: pd.DataFrame, cfg: dict[str, Any]) -> pd.Series:
    """Reconstruct the residualized output competition instrument used in the thesis robustness checks."""
    if "output_IV_resid" in panel.columns:
        resid = pd.to_numeric(panel["output_IV_resid"], errors="coerce")
        if resid.notna().any():
            return resid
    if "output_IV" not in panel.columns or "Z_input" not in panel.columns:
        return pd.Series(np.nan, index=panel.index)

    work = panel.copy()
    if "year" in work.columns:
        y0 = int(cfg["sample"].get("year_min", work["year"].min()))
        y1 = int(cfg["sample"].get("year_max", work["year"].max()))
        work = work.loc[work["year"].between(y0, y1)].copy()

    y = pd.to_numeric(work["output_IV"], errors="coerce")
    x = pd.to_numeric(work["Z_input"], errors="coerce")
    valid = y.notna() & x.notna()
    resid = pd.Series(np.nan, index=panel.index)
    if int(valid.sum()) < 2:
        return resid

    x_valid = np.column_stack([np.ones(int(valid.sum())), x.loc[valid].to_numpy(dtype=float)])
    beta = np.linalg.lstsq(x_valid, y.loc[valid].to_numpy(dtype=float), rcond=None)[0]
    fitted = beta[0] + beta[1] * pd.to_numeric(panel["Z_input"], errors="coerce")
    resid.loc[y.index[valid]] = y.loc[valid] - (beta[0] + beta[1] * x.loc[valid])
    return resid


def _diagnostic(name: str, df: pd.DataFrame, cols: list[str], cfg: dict[str, Any]) -> None:
    if not cfg["moments"].get("print_diagnostics", True):
        return
    n0 = len(df)
    present = [c for c in cols if c in df.columns]
    n1 = len(df.replace([np.inf, -np.inf], np.nan).dropna(subset=present)) if present else n0
    sectors = df["isic4"].nunique() if "isic4" in df.columns else np.nan
    years = df["year"].nunique() if "year" in df.columns else np.nan
    print(f"[moment audit] {name}: n={n1:,} usable / {n0:,} rows; sectors={sectors}; years={years}; dropped={n0-n1:,}")


def _selection_controls(data: pd.DataFrame) -> list[str]:
    return [c for c in ["Z_input", "ls_pre_filled", "ls_pre_x_post2016"] if c in data.columns]


def _years_span(df: pd.DataFrame) -> str:
    if "year" not in df.columns or df.empty:
        return ""
    y = pd.to_numeric(df["year"], errors="coerce").dropna()
    if y.empty:
        return ""
    return f"{int(y.min())}-{int(y.max())}"


def _metadata(
    df: pd.DataFrame,
    *,
    outcome: str,
    treatment: str,
    instrument: str,
    controls: list[str],
    fe: list[str],
    cluster: str | None,
    timing: str,
    notes: str,
    n_obs: int | None = None,
    dropped_obs: int | None = None,
) -> dict[str, Any]:
    n_obs_val = n_obs if n_obs is not None else len(df)
    dropped_val = dropped_obs if dropped_obs is not None else np.nan
    return {
        "outcome": outcome,
        "treatment": treatment,
        "instrument": instrument,
        "controls": "|".join(controls),
        "fe": "|".join(fe),
        "cluster_level": cluster or "",
        "years": _years_span(df),
        "n_obs": int(n_obs_val) if np.isfinite(n_obs_val) else np.nan,
        "n_firms": int(df["firm_id"].nunique()) if "firm_id" in df.columns else np.nan,
        "n_sectors": int(df["isic4"].nunique()) if "isic4" in df.columns else np.nan,
        "dropped_observations": int(dropped_val) if pd.notna(dropped_val) else np.nan,
        "timing_convention": timing,
        "notes": notes,
    }


def _flatten_diagnostics(cfg: dict[str, Any]) -> dict[str, str]:
    diagnostics = cfg.get("moments", {}).get("diagnostics", {}) or {}
    mapping: dict[str, str] = {}
    group_roles = {
        "aggregation": "aggregation_diagnostic",
        "accounting": "accounting_diagnostic",
        "correlated_input": "correlated_input_diagnostic",
        "selection": "selection_diagnostic",
        "decomposition_iv": "accounting_diagnostic",
        "allocative_wedge": "allocative_wedge_diagnostic",
    }
    for group, names in diagnostics.items():
        role = group_roles.get(group, f"{group}_diagnostic")
        for name in names or []:
            mapping[str(name)] = role
    return mapping


def _moment_role(moment: str, cfg: dict[str, Any]) -> str:
    diagnostics = _flatten_diagnostics(cfg)
    if moment in diagnostics:
        return diagnostics[moment]
    if moment.startswith("decomp_"):
        return "accounting_diagnostic"
    if moment == "sector_inverse_markup_iv":
        return "aggregation_diagnostic"
    if moment.startswith("input_shock_"):
        return "correlated_input_diagnostic"
    if moment.startswith("exit_") or moment.startswith("selection_") or moment == "exit_iv":
        return "selection_diagnostic"
    if moment.startswith("allocative_wedge"):
        return "allocative_wedge_diagnostic"
    if moment in set(cfg.get("moments", {}).get("objective", []) or []):
        return "causal_core"
    return "other_diagnostic"


def _apply_moment_roles(out: pd.DataFrame, cfg: dict[str, Any]) -> pd.DataFrame:
    if out.empty:
        out["role"] = pd.Series(dtype=str)
        out["moment_group"] = pd.Series(dtype=str)
        return out
    out = out.copy()
    out["role"] = out["moment"].map(lambda m: _moment_role(str(m), cfg))
    out["moment_group"] = out["role"]
    input_note = (
        "Z_input coefficient from IV/FWL specification; treated as exogenous control/self-instrumented; "
        "mechanism diagnostic, not excluded-IV causal moment."
    )
    mask = out["moment"].eq("input_shock_between_reallocation")
    if mask.any():
        existing = out.loc[mask, "notes"].fillna("").astype(str)
        out.loc[mask, "notes"] = existing.where(existing.eq(""), existing + " ") + input_note
    return out


def _infer_exit_outcome(panel: pd.DataFrame, exit_col: str = "exit", force_forward_shifted: bool = False) -> tuple[pd.DataFrame, str, str]:
    """Infer exit outcome from panel data.
    
    If force_forward_shifted=True, always use the forward-shifted exit (F.exit) version WITHOUT inversion, 
    which matches the Stata convention for the exit IV moment: exit at t+1 on treatment at t.
    """
    work = panel.sort_values(["firm_id", "year"]).copy()
    work["next_year"] = work.groupby("firm_id")["year"].shift(-1)
    work["exit_from_presence_tplus1"] = np.where(
        work["next_year"].isna(),
        np.nan,
        (work["next_year"] != work["year"] + 1).astype(float),
    )
    max_year = int(work["year"].max()) if not work.empty else None
    if max_year is not None:
        work.loc[work["year"] >= max_year, "exit_from_presence_tplus1"] = np.nan

    if exit_col not in work.columns:
        return work, "exit_from_presence_tplus1", "Exit defined from observed disappearance at t+1; terminal year excluded."

    ex = pd.to_numeric(work[exit_col], errors="coerce")
    ex = ex.where(ex.isin([0.0, 1.0]))
    presence = work["exit_from_presence_tplus1"]
    valid = ex.notna() & presence.notna()
    if int(valid.sum()) < 500:
        return work, "exit_from_presence_tplus1", "Exit column weakly populated; used observed disappearance at t+1."

    # If force_forward_shifted=True (for exit IV moment), use F.exit (forward-shifted exit) without inversion.
    # This follows the Stata specification: ivreghdfe F.exit (change_IP = output_IV) ...
    if force_forward_shifted:
        ex_shift = ex.groupby(work["firm_id"]).shift(-1)
        next_year = work.groupby("firm_id")["year"].shift(-1)
        valid_shift = ex_shift.notna() & next_year.notna() & (next_year == work["year"] + 1)
        if int(valid_shift.sum()) > 100:  # Enough data
            work["exit_forward"] = ex_shift.where(valid_shift)
            return work, "exit_forward", "Using F.exit (forward-shifted exit at t+1) for forward-looking exit IV moment."
        # Fallback if not enough shifted data
        return work, "exit_from_presence_tplus1", "Fallback to observed disappearance at t+1; terminal year excluded."

    # Original auto-detection logic (for decomposition and other uses)
    corr_same = ex[valid].corr(presence[valid])
    ex_shift = ex.groupby(work["firm_id"]).shift(-1)
    valid_shift = ex_shift.notna() & presence.notna()
    corr_shift = ex_shift[valid_shift].corr(presence[valid_shift]) if int(valid_shift.sum()) > 0 else np.nan

    if pd.notna(corr_same) and (pd.isna(corr_shift) or abs(corr_same) >= abs(corr_shift)):
        if corr_same < 0:
            work["exit_inferred"] = 1.0 - ex
            return work, "exit_inferred", "Using exit column at t but inverted to match disappearance at t+1."
        work["exit_inferred"] = ex
        return work, "exit_inferred", "Using exit column at t as forward exit to t+1."

    if pd.notna(corr_shift):
        if corr_shift < 0:
            work["exit_inferred"] = 1.0 - ex_shift
            return work, "exit_inferred", "Using F.exit (inverted) to match disappearance at t+1."
        work["exit_inferred"] = ex_shift
        return work, "exit_inferred", "Using F.exit to match disappearance at t+1."

    return work, "exit_from_presence_tplus1", "Fallback to observed disappearance at t+1; terminal year excluded."


def compute_firm_level_iv_moment(panel: pd.DataFrame, cfg: dict[str, Any], y_col: str = "dln_mu") -> dict:
    """Baseline firm IV moment.

    Outcome: dln_mu, firm-level markup growth.
    Treatment: change_IP, sector-year Chinese import penetration growth.
    Instrument: output_IV, excluded output-competition shifter.
    Controls: firm controls from cfg, including Z_input and lagged firm controls when available.
    Fixed effects: isic4 and year. Clustering: isic4.
    Sample: cleaned panel rows with non-missing outcome, treatment, instrument, and cluster.
    Timing: outcome and shocks dated t for continuing reporters.
    """
    controls = _controls(cfg, "firm", panel)
    fe = _fe(cfg, panel)
    cluster = _cluster(cfg, panel)
    pre_n = len(panel)
    _diagnostic("baseline firm IV", panel, [y_col, "change_IP", "output_IV"] + controls + fe + ([cluster] if cluster else []), cfg)
    res = iv_2sls(panel, y_col, "change_IP", "output_IV", controls, fe, cluster, name="baseline")
    row = result_to_moment(res, "change_IP", "baseline_iv_dln_mu", "iv")
    row.update(
        _metadata(
            panel,
            outcome=y_col,
            treatment="change_IP",
            instrument="output_IV",
            controls=controls,
            fe=fe,
            cluster=cluster,
            timing="Outcome and shocks at t.",
            notes="Baseline firm-level IV retained as in thesis-aligned notebook definition.",
            n_obs=res.nobs,
            dropped_obs=pre_n - res.nobs,
        )
    )
    return row


def compute_exit_iv_moment(panel: pd.DataFrame, cfg: dict[str, Any], exit_col: str = "exit") -> dict:
    """Exit IV moment.

    Outcome: observed exit at t+1 for data; model exit probabilities are already forward-looking.
    Treatment: change_IP at t. Instrument: residualized output_IV from the selection-correction specification.
    Controls: Z_input and the ls_pre_filled x post2016 interaction, matching the thesis robustness exit regression.
    Fixed effects: isic4 and year. Clustering: isic4.
    Sample: rows with non-missing forward exit outcome, treatment, instrument, controls, and cluster.
    Timing: regress F.exit (forward-shifted exit) on current import-penetration growth and residualized output competition.
    Matches Stata specification: ivreghdfe F.exit (change_IP = output_IV_resid) Z_input c.ls_pre_filled##i.post2016 i.year ...
    """
    work, outcome, timing_note = _infer_exit_outcome(panel, exit_col=exit_col, force_forward_shifted=True)
    work = work.loc[work[outcome].notna()].copy()
    controls = _selection_controls(work)
    fe = _fe(cfg, work)
    cluster = _cluster(cfg, work)
    work = work.copy()
    work["output_IV_resid"] = _selection_corrected_output_iv(work, cfg)
    pre_n = len(work)
    _diagnostic("exit IV", work, [outcome, "change_IP", "output_IV_resid"] + controls + fe + ([cluster] if cluster else []), cfg)
    res = iv_2sls(work, outcome, "change_IP", "output_IV_resid", controls, fe, cluster, name="exit_iv")
    row = result_to_moment(res, "change_IP", "exit_iv", "iv")
    row.update(
        _metadata(
            work,
            outcome=outcome,
            treatment="change_IP",
            instrument="output_IV_resid",
            controls=controls,
            fe=fe,
            cluster=cluster,
            timing="Exit at t+1 (forward-shifted) on shocks at t; terminal year excluded.",
            notes=timing_note,
            n_obs=res.nobs,
            dropped_obs=pre_n - res.nobs,
        )
    )
    return row


def compute_selection_corrected_iv_moment(panel: pd.DataFrame, cfg: dict[str, Any], y_col: str = "dln_mu") -> dict:
    """Selection-corrected firm-level IV moment using residualized output competition."""
    work = panel.copy()
    if "year" in work.columns:
        y0 = int(cfg["sample"].get("year_min", work["year"].min()))
        y1 = int(cfg["sample"].get("year_max", work["year"].max()))
        work = work.loc[work["year"].between(y0, y1)].copy()
    work["output_IV_resid"] = _selection_corrected_output_iv(work, cfg)
    work = work.loc[work[y_col].notna()].copy()
    controls = _controls(cfg, "firm", work)
    fe = _fe(cfg, work)
    cluster = _cluster(cfg, work)
    pre_n = len(work)
    _diagnostic("selection-corrected firm IV", work, [y_col, "change_IP", "output_IV_resid"] + controls + fe + ([cluster] if cluster else []), cfg)
    res = iv_2sls(work, y_col, "change_IP", "output_IV_resid", controls, fe, cluster, name="selection_corrected")
    row = result_to_moment(res, "change_IP", "selection_corrected_iv_dln_mu", "iv")
    row.update(
        _metadata(
            work,
            outcome=y_col,
            treatment="change_IP",
            instrument="output_IV_resid",
            controls=controls,
            fe=fe,
            cluster=cluster,
            timing="Outcome and shocks at t; residualized output IV selection correction.",
            notes="Selection-corrected robustness specification with residualized output competition.",
            n_obs=res.nobs,
            dropped_obs=pre_n - res.nobs,
        )
    )
    return row


def compute_tail_iv_moments(
    sec: pd.DataFrame,
    cfg: dict[str, Any],
    y_col: str = "dln_mu",
    want=lambda name: True,
) -> list[dict]:
    """Grouped upper-tail IV moments.

    Outcome: sector-year quantiles of dln_mu.
    Treatment: change_IP. Instrument: output_IV.
    Controls: sector controls from cfg, including Z_input.
    Fixed effects: isic4 and year. Clustering: isic4.
    Sample: sector-years with enough firms after cleaning.
    Timing: sector-year shocks and grouped outcomes dated t.
    """
    rows = []
    controls = _controls(cfg, "sector", sec)
    fe = _fe(cfg, sec)
    cluster = _cluster(cfg, sec)
    for q in cfg["moments"].get("quantiles", [0.75, 0.80, 0.85, 0.90]):
        moment_name = f"grouped_iv_q{int(round(float(q) * 100))}"
        if not want(moment_name):
            continue
        qname = f"q{int(round(float(q) * 100))}_{y_col}"
        if qname not in sec.columns:
            rows.append(
                _moment_row(
                    moment_name,
                    np.nan,
                    "missing",
                    metadata=_metadata(
                        sec,
                        outcome=qname,
                        treatment="change_IP",
                        instrument="output_IV",
                        controls=controls,
                        fe=fe,
                        cluster=cluster,
                        timing="Sector-year grouped moments at t.",
                        notes="Quantile column not found in sector panel.",
                    ),
                )
            )
            continue
        pre_n = len(sec)
        _diagnostic(moment_name, sec, [qname, "change_IP", "output_IV"] + controls + fe + ([cluster] if cluster else []), cfg)
        res = iv_2sls(sec, qname, "change_IP", "output_IV", controls, fe, cluster, name=qname)
        row = result_to_moment(res, "change_IP", moment_name, "iv")
        row.update(
            _metadata(
                sec,
                outcome=qname,
                treatment="change_IP",
                instrument="output_IV",
                controls=controls,
                fe=fe,
                cluster=cluster,
                timing="Sector-year grouped moments at t.",
                notes="Tail grouped-IV moment preserved from current working definition.",
                n_obs=res.nobs,
                dropped_obs=pre_n - res.nobs,
            )
        )
        rows.append(row)
    return rows


def compute_tail_cr4_interaction_moments(
    sec: pd.DataFrame,
    cfg: dict[str, Any],
    y_col: str = "dln_mu",
    want=lambda name: True,
) -> list[dict]:
    """Grouped upper-tail concentration heterogeneity IV moments.

    For each configured quantile, estimate a sector-year IV system:

        q_tau(dln_mu)_jt on change_IP_jt and change_IP_jt x centered CR4_jt,
        instrumented by output_IV_jt and output_IV_jt x centered CR4_jt.

    The reported moment is the coefficient on the interaction. CR4 is reconstructed
    from firm sales shares when the raw Stata panel lacks CR4_dom.
    """
    rows: list[dict] = []
    if "CR4_dom" not in sec.columns:
        return rows

    work = sec.copy()
    work["CR4_c"] = pd.to_numeric(work["CR4_dom"], errors="coerce") - pd.to_numeric(work["CR4_dom"], errors="coerce").mean(skipna=True)
    work["changeIP_x_CR4"] = work["change_IP"] * work["CR4_c"]
    work["outputIV_x_CR4"] = work["output_IV"] * work["CR4_c"]
    controls = list(dict.fromkeys(_controls(cfg, "sector", work) + ["CR4_c"]))
    fe = _fe(cfg, work)
    cluster = _cluster(cfg, work)
    quantiles = cfg["moments"].get("cr4_interaction_quantiles", [0.90])

    for q in quantiles:
        q_int = int(round(float(q) * 100))
        moment_name = f"grouped_iv_q{q_int}_cr4_interaction"
        if not want(moment_name):
            continue
        qname = f"q{q_int}_{y_col}"
        if qname not in work.columns:
            rows.append(
                _moment_row(
                    moment_name,
                    np.nan,
                    "missing",
                    metadata=_metadata(
                        work,
                        outcome=qname,
                        treatment="change_IP x centered CR4_dom",
                        instrument="output_IV x centered CR4_dom",
                        controls=controls,
                        fe=fe,
                        cluster=cluster,
                        timing="Sector-year grouped tail moment at t.",
                        notes="Quantile column not found for CR4 interaction grouped-IV moment.",
                    ),
                )
            )
            continue
        pre_n = len(work)
        _diagnostic(
            moment_name,
            work,
            [qname, "change_IP", "changeIP_x_CR4", "output_IV", "outputIV_x_CR4"] + controls + fe + ([cluster] if cluster else []),
            cfg,
        )
        try:
            res = iv_2sls(
                work,
                qname,
                ["change_IP", "changeIP_x_CR4"],
                ["output_IV", "outputIV_x_CR4"],
                controls,
                fe,
                cluster,
                name=moment_name,
            )
            row = result_to_moment(res, "changeIP_x_CR4", moment_name, "iv")
            row.update(
                _metadata(
                    work,
                    outcome=qname,
                    treatment="change_IP x centered CR4_dom",
                    instrument="output_IV x centered CR4_dom",
                    controls=controls,
                    fe=fe,
                    cluster=cluster,
                    timing="Sector-year grouped tail moment at t.",
                    notes="Causal output-competition heterogeneity moment; CR4_dom reconstructed from firm sales shares when absent in data_ready_mec.dta.",
                    n_obs=res.nobs,
                    dropped_obs=pre_n - res.nobs,
                )
            )
            rows.append(row)
        except Exception as exc:
            rows.append(
                _moment_row(
                    moment_name,
                    np.nan,
                    f"failed: {exc}",
                    metadata=_metadata(
                        work,
                        outcome=qname,
                        treatment="change_IP x centered CR4_dom",
                        instrument="output_IV x centered CR4_dom",
                        controls=controls,
                        fe=fe,
                        cluster=cluster,
                        timing="Sector-year grouped tail moment at t.",
                        notes="CR4 interaction grouped-IV moment failed.",
                    ),
                )
            )
    return rows


def compute_decomposition_components(
    panel: pd.DataFrame,
    cfg: dict[str, Any],
    inv_col: str = "inv_mu",
    share_col: str = "share_sales",
    use_stata_sector_moments: bool = True,
) -> pd.DataFrame:
    """Build sector-year decomposition components.

    Priority order:
    1) Use Stata-exported sector decomposition moments when configured and available.
       This ensures exact alignment with the thesis decomposition pipeline.
    2) Fall back to Python decomposition on firm-level panel.
    """
    csv_path = cfg.get("paths", {}).get("stata_sector_moments", "") if use_stata_sector_moments else ""
    comp = pd.DataFrame()
    if csv_path:
        p = Path(csv_path)
        if not p.is_absolute():
            p = (Path.cwd() / p).resolve()
        if p.exists():
            try:
                raw = pd.read_csv(p)
                need = [
                    "isic4",
                    "year",
                    "within_inv_mu",
                    "between_inv_mu",
                    "entry_inv_mu",
                    "exit_inv_mu",
                    "change_IP",
                    "output_IV",
                    "Z_input",
                    "ls_pre_filled",
                    "dom_j",
                    "n_firms",
                ]
                cols = [c for c in need if c in raw.columns]
                comp = raw[cols].copy()
                for c in cols:
                    if c != "isic4":
                        comp[c] = pd.to_numeric(comp[c], errors="coerce")
                if "year" in comp.columns:
                    y0 = int(cfg["sample"]["year_min"])
                    y1 = int(cfg["sample"]["year_max"])
                    comp = comp.loc[comp["year"].between(y0, y1)].copy()
                if "ls_pre_filled" not in comp.columns:
                    comp["ls_pre_filled"] = 0.0
                comp["post2016"] = (comp["year"] >= 2016).astype(float) if "year" in comp.columns else 0.0
                comp["ls_pre_x_post2016"] = comp["ls_pre_filled"].fillna(0.0) * comp["post2016"].fillna(0.0)
                if "d_inv_mu_j_components" not in comp.columns:
                    comp["d_inv_mu_j_components"] = (
                        comp["within_inv_mu"].fillna(0.0)
                        + comp["between_inv_mu"].fillna(0.0)
                        + comp["entry_inv_mu"].fillna(0.0)
                        - comp["exit_inv_mu"].fillna(0.0)
                    )
            except Exception:
                comp = pd.DataFrame()

    if comp.empty:
        comp = decompose_inverse_markup(panel, inv_col=inv_col, share_col=share_col)
    _diagnostic("decomposition components", comp, ["within_inv_mu", "between_inv_mu", "Z_input"], cfg)
    return comp


def compute_decomposition_share_moments(comp: pd.DataFrame, cfg: dict[str, Any]) -> list[dict]:
    """Compute thesis-style gross absolute decomposition mass-share moments."""
    exclude_years = [int(y) for y in cfg.get("moments", {}).get("decomposition_exclude_years", [])]
    work = comp.copy()
    if "year" in work.columns:
        work = work.loc[~work["year"].isin(exclude_years)].copy()
    shares = gross_absolute_component_shares(
        work,
        exclude_first_year=False,
        exclude_years=None,
    )
    base_meta = _metadata(
        work,
        outcome="gross_absolute_component_share",
        treatment="n/a",
        instrument="n/a",
        controls=[],
        fe=[],
        cluster=None,
        timing="Component contributions from t-1 to t; years in decomposition_exclude_years dropped.",
        notes="Midpoint decomposition with absolute-mass normalization and sector domestic-sales weighting.",
        n_obs=len(work),
        dropped_obs=len(comp) - len(work),
    )
    rows = [
        _moment_row("within_decomp_abs_share", shares["within_inv_mu"], "decomp_share", metadata=base_meta),
        _moment_row("between_decomp_abs_share", shares["between_inv_mu"], "decomp_share", metadata=base_meta),
        _moment_row("entry_decomp_abs_share", shares["entry_inv_mu"], "decomp_share", metadata=base_meta),
        _moment_row("exit_decomp_abs_share", shares["exit_inv_mu"], "decomp_share", metadata=base_meta),
    ]
    return rows


def compute_decomposition_iv_moments(comp: pd.DataFrame, cfg: dict[str, Any]) -> list[dict]:
    """Compute decomposition IV moments used as diagnostic anchors in thesis tables."""
    rows: list[dict] = []
    # Stata c1-equivalent decomposition controls: Z_input enters directly in regression,
    # while ls_pre_filled and ls_pre_x_post2016 are partialled controls.
    controls = [c for c in ["ls_pre_filled", "ls_pre_x_post2016"] if c in comp.columns]
    fe = _fe(cfg, comp)
    cluster = _cluster(cfg, comp)
    exclude_years = [int(y) for y in cfg.get("moments", {}).get("decomposition_exclude_years", [])]
    work = comp.copy()
    if "year" in work.columns:
        work = work.loc[~work["year"].isin(exclude_years)].copy()

    specs = [
        ("d_inv_mu_j_components", "decomp_total_output_iv"),
        ("within_inv_mu", "decomp_within_output_iv"),
        ("between_inv_mu", "decomp_reallocation_output_iv"),
    ]
    for y_col, mname in specs:
        if y_col not in work.columns:
            continue
        pre_n = len(work)
        try:
            res = iv_2sls(work, y_col, "change_IP", "output_IV", controls, fe, cluster, name=mname)
            row = result_to_moment(res, "change_IP", mname, "iv")
            row.update(
                _metadata(
                    work,
                    outcome=y_col,
                    treatment="change_IP",
                    instrument="output_IV",
                    controls=controls,
                    fe=fe,
                    cluster=cluster,
                    timing="Decomposition component from t-1 to t on shocks at t.",
                    notes="Sector-level decomposition IV diagnostic.",
                    n_obs=res.nobs,
                    dropped_obs=pre_n - res.nobs,
                )
            )
            rows.append(row)
        except Exception as exc:
            rows.append(
                _moment_row(
                    mname,
                    np.nan,
                    f"failed: {exc}",
                    metadata=_metadata(
                        work,
                        outcome=y_col,
                        treatment="change_IP",
                        instrument="output_IV",
                        controls=controls,
                        fe=fe,
                        cluster=cluster,
                        timing="Decomposition component from t-1 to t on shocks at t.",
                        notes="IV failed.",
                    ),
                )
            )
    return rows


def compute_decomposition_moments(panel: pd.DataFrame, cfg: dict[str, Any], inv_col: str = "inv_mu", share_col: str = "share_sales", use_stata_sector_moments: bool = True) -> tuple[list[dict], pd.DataFrame]:
    """Backwards-compatible wrapper for decomposition share moments."""
    comp = compute_decomposition_components(panel, cfg, inv_col=inv_col, share_col=share_col, use_stata_sector_moments=use_stata_sector_moments)
    share_rows = compute_decomposition_share_moments(comp, cfg)
    return share_rows, comp


def compute_input_reallocation_moment(comp: pd.DataFrame, cfg: dict[str, Any]) -> dict:
    """Input-shock reallocation moment.

    Outcome: between_inv_mu, the market-share reallocation contribution to sector inverse-markup change.
    Treatment: Z_input, input-supply shifter.
    Instrument: none; reduced-form OLS/FWL diagnostic.
    Controls: sector controls except Z_input. Fixed effects: isic4 and year. Clustering: isic4.
    Sample: sector-years with non-missing decomposition and controls.
    Timing: Z_input dated t, decomposition from t-1 to t.
    """
    # Match Stata Panel A spec for the between component:
    # ivreghdfe between_inv_mu (change_IP = output_IV) Z_input c.ls_pre_filled##i.post2016 i.year, absorb(isic4)
    controls = [c for c in ["ls_pre_filled", "ls_pre_x_post2016"] if c in comp.columns]
    fe = _fe(cfg, comp)
    cluster = _cluster(cfg, comp)
    exclude_years = [int(y) for y in cfg.get("moments", {}).get("decomposition_exclude_years", [])]
    work = comp.copy()
    if "year" in work.columns:
        work = work.loc[~work["year"].isin(exclude_years)].copy()
    pre_n = len(work)
    _diagnostic(
        "input reallocation",
        work,
        ["between_inv_mu", "change_IP", "output_IV", "Z_input"] + controls + fe + ([cluster] if cluster else []),
        cfg,
    )

    # Include Z_input as an exogenous regressor in the IV system by instrumenting it with itself.
    # Endogenous list contains [change_IP, Z_input], instrument list [output_IV, Z_input].
    # Coefficient on Z_input then matches the second-stage control coefficient from the Stata spec.
    res = iv_2sls(
        work,
        "between_inv_mu",
        ["change_IP", "Z_input"],
        ["output_IV", "Z_input"],
        controls,
        fe,
        cluster,
        name="input_between_iv",
    )
    row = result_to_moment(res, "Z_input", "input_shock_between_reallocation", "iv")
    row.update(
        _metadata(
            work,
            outcome="between_inv_mu",
            treatment="Z_input",
            instrument="output_IV (for change_IP); Z_input self-instrumented as exogenous regressor",
            controls=controls,
            fe=fe,
            cluster=cluster,
            timing="Between/reallocation component from t-1 to t; excluded years dropped.",
            notes="Stata-aligned IV specification for decomposition Panel A control coefficient on Z_input.",
            n_obs=res.nobs,
            dropped_obs=pre_n - res.nobs,
        )
    )
    return row


def compute_moments(
    panel: pd.DataFrame,
    cfg: dict[str, Any],
    y_col: str = "dln_mu",
    inv_col: str = "inv_mu",
    share_col: str = "share_sales",
    exit_col: str = "exit",
    label: str = "data",
    use_stata_sector_moments: bool = True,
) -> pd.DataFrame:
    rows: list[dict] = []
    compute_all = bool(cfg.get("moments", {}).get("compute_all", False))
    active = set(cfg["moments"].get("active", []) or [])

    def want(name: str) -> bool:
        return compute_all or not active or name in active

    fe = _fe(cfg, panel)
    cluster = _cluster(cfg, panel)
    firm_controls = _controls(cfg, "firm", panel)

    if want("baseline_iv_dln_mu"):
        try:
            rows.append(compute_firm_level_iv_moment(panel, cfg, y_col=y_col))
        except Exception as exc:
            rows.append(_moment_row("baseline_iv_dln_mu", np.nan, f"failed: {exc}"))

    if want("selection_corrected_iv_dln_mu"):
        try:
            rows.append(compute_selection_corrected_iv_moment(panel, cfg, y_col=y_col))
        except Exception as exc:
            rows.append(_moment_row("selection_corrected_iv_dln_mu", np.nan, f"failed: {exc}"))

    if cfg["moments"].get("include_interaction", True) and want("concentration_interaction_iv"):
        try:
            w = add_concentration_interactions(panel)
            controls = firm_controls + ["conc_c"]
            res = iv_2sls(
                w,
                y_col,
                ["change_IP", "changeIP_x_conc"],
                ["output_IV", "outputIV_x_conc"],
                controls,
                fe,
                cluster,
                name="concentration_interaction",
            )
            rows.append(result_to_moment(res, "changeIP_x_conc", "concentration_interaction_iv", "iv"))
        except Exception as exc:
            rows.append(_moment_row("concentration_interaction_iv", np.nan, f"failed: {exc}"))

    if want("mean_dln_mu"):
        rows.append(_moment_row("mean_dln_mu", panel[y_col].mean(skipna=True), "mean", nobs=panel[y_col].notna().sum()))
    if want("var_dln_mu"):
        rows.append(_moment_row("var_dln_mu", panel[y_col].var(skipna=True), "variance", nobs=panel[y_col].notna().sum()))

    sec = sector_panel(panel, inv_col=inv_col, share_col=share_col, dln_col=y_col)
    sec_controls = _controls(cfg, "sector", sec)
    sec_fe = _fe(cfg, sec)
    sec_cluster = _cluster(cfg, sec)

    if want("sector_inverse_markup_iv"):
        try:
            pre_n = len(sec)
            res = iv_2sls(sec, "d_inv_mu_j", "change_IP", "output_IV", sec_controls, sec_fe, sec_cluster, name="sector_inverse")
            row = result_to_moment(res, "change_IP", "sector_inverse_markup_iv", "iv")
            row.update(
                _metadata(
                    sec,
                    outcome="d_inv_mu_j",
                    treatment="change_IP",
                    instrument="output_IV",
                    controls=sec_controls,
                    fe=sec_fe,
                    cluster=sec_cluster,
                    timing="Sector inverse markup change from t-1 to t on shocks at t.",
                    notes="Sector-level inverse-markup IV moment.",
                    n_obs=res.nobs,
                    dropped_obs=pre_n - res.nobs,
                )
            )
            rows.append(row)
        except Exception as exc:
            rows.append(_moment_row("sector_inverse_markup_iv", np.nan, f"failed: {exc}"))

    try:
        rows.extend(compute_tail_iv_moments(sec, cfg, y_col=y_col, want=want))
    except Exception as exc:
        for q in cfg["moments"].get("quantiles", [0.75, 0.80, 0.85, 0.90]):
            moment_name = f"grouped_iv_q{int(round(float(q) * 100))}"
            if want(moment_name):
                rows.append(_moment_row(moment_name, np.nan, f"failed: {exc}"))

    try:
        rows.extend(compute_tail_cr4_interaction_moments(sec, cfg, y_col=y_col, want=want))
    except Exception as exc:
        for q in cfg["moments"].get("cr4_interaction_quantiles", [0.90]):
            moment_name = f"grouped_iv_q{int(round(float(q) * 100))}_cr4_interaction"
            if want(moment_name):
                rows.append(_moment_row(moment_name, np.nan, f"failed: {exc}"))

    if (
        want("within_decomp_abs_share")
        or want("between_decomp_abs_share")
        or want("entry_decomp_abs_share")
        or want("exit_decomp_abs_share")
        or want("input_shock_between_reallocation")
    ):
        try:
            decomp_rows, comp = compute_decomposition_moments(panel, cfg, inv_col=inv_col, share_col=share_col, use_stata_sector_moments=use_stata_sector_moments)
            rows.extend([r for r in decomp_rows if want(r["moment"])])
            for row in compute_decomposition_iv_moments(comp, cfg):
                if want(row["moment"]):
                    rows.append(row)
            if want("input_shock_between_reallocation"):
                rows.append(compute_input_reallocation_moment(comp, cfg))
        except Exception as exc:
            if want("within_decomp_abs_share"):
                rows.append(_moment_row("within_decomp_abs_share", np.nan, f"failed: {exc}"))
            if want("between_decomp_abs_share"):
                rows.append(_moment_row("between_decomp_abs_share", np.nan, f"failed: {exc}"))
            if want("entry_decomp_abs_share"):
                rows.append(_moment_row("entry_decomp_abs_share", np.nan, f"failed: {exc}"))
            if want("exit_decomp_abs_share"):
                rows.append(_moment_row("exit_decomp_abs_share", np.nan, f"failed: {exc}"))
            if want("input_shock_between_reallocation"):
                rows.append(_moment_row("input_shock_between_reallocation", np.nan, f"failed: {exc}"))
            if want("decomp_total_output_iv"):
                rows.append(_moment_row("decomp_total_output_iv", np.nan, f"failed: {exc}"))
            if want("decomp_within_output_iv"):
                rows.append(_moment_row("decomp_within_output_iv", np.nan, f"failed: {exc}"))
            if want("decomp_reallocation_output_iv"):
                rows.append(_moment_row("decomp_reallocation_output_iv", np.nan, f"failed: {exc}"))

    if want("input_shock_within_dln_mu"):
        try:
            controls = [c for c in firm_controls if c != "Z_input"] + ["change_IP"]
            res = ols_fwl(panel, y_col, "Z_input", controls, fe, cluster, name="input_within")
            rows.append(result_to_moment(res, "Z_input", "input_shock_within_dln_mu", "ols"))
        except Exception as exc:
            rows.append(_moment_row("input_shock_within_dln_mu", np.nan, f"failed: {exc}"))

    if cfg["moments"].get("include_exit", True) and exit_col in panel.columns:
        if want("exit_rate"):
            rows.append(_moment_row("exit_rate", panel[exit_col].mean(skipna=True), "mean", nobs=panel[exit_col].notna().sum()))
        if want("exit_iv"):
            try:
                rows.append(compute_exit_iv_moment(panel, cfg, exit_col=exit_col))
            except Exception as exc:
                rows.append(_moment_row("exit_iv", np.nan, f"failed: {exc}"))

    out = pd.DataFrame(rows)
    out["source"] = label
    return _apply_moment_roles(out, cfg)


def compute_data_moments(panel: pd.DataFrame, cfg: dict[str, Any]) -> pd.DataFrame:
    return compute_moments(panel, cfg, label="data")
