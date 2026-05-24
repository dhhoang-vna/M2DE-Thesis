from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd

from .model import Theta, logistic, nested_ces_inverse_markup


def _normalize_shares(df: pd.DataFrame, raw_col: str, out_col: str) -> pd.DataFrame:
    total = df.groupby(["isic4", "year"])[raw_col].transform("sum")
    df[out_col] = df[raw_col] / total.replace(0.0, np.nan)
    df[out_col] = df[out_col].fillna(df["share_sales"]).clip(lower=0.0)
    return df


def simulate_panel(
    panel: pd.DataFrame,
    theta: Theta,
    cfg: dict[str, Any],
    scenario: str = "observed",
) -> pd.DataFrame:
    e = cfg["elasticities"]
    out = panel.copy()

    obs_output = out["change_IP"].fillna(0.0).to_numpy(dtype=float)
    obs_input = out["Z_input"].fillna(0.0).to_numpy(dtype=float)
    if scenario == "observed":
        output_shock = obs_output
        input_shock = obs_input
    elif scenario == "no_output":
        output_shock = np.zeros_like(obs_output)
        input_shock = obs_input
    elif scenario == "no_output_input":
        output_shock = np.zeros_like(obs_output)
        input_shock = np.zeros_like(obs_input)
    else:
        raise ValueError(f"Unknown scenario: {scenario}")

    if "IP" in out.columns and out["IP"].notna().any():
        ip_t = out["IP"].fillna(out["IP"].median()).to_numpy(dtype=float)
        ip_lag = ip_t - obs_output
        lambda_lag = 1.0 - ip_lag
    else:
        lambda_lag = np.full(len(out), float(e["default_lambda"]))
    lambda_lag = np.clip(lambda_lag, float(e["lambda_min"]), float(e["lambda_max"]))
    lambda_current = np.clip(lambda_lag - theta.output_scale * output_shock, float(e["lambda_min"]), float(e["lambda_max"]))

    s_lag = out.get("l_share_sales", out["share_sales"]).fillna(out["share_sales"]).clip(lower=1.0e-10)
    ln_mu_lag = out.get("l_ln_mu", out["ln_mu"]).fillna(out["ln_mu"])
    out["_ln_mu_lag_used"] = ln_mu_lag
    out["_ln_mu_center"] = ln_mu_lag - out.groupby(["isic4", "year"])["_ln_mu_lag_used"].transform("mean")
    concentration = out.get("CR4_dom", pd.Series(np.nan, index=out.index)).fillna(
        out.get("HHI_dom", pd.Series(np.nan, index=out.index))
    )
    concentration = concentration.fillna(concentration.median()).fillna(0.0)
    out["_concentration_center"] = concentration - concentration.mean()
    out["_input_center"] = out["input_exposure_i"] - out.groupby(["isic4", "year"])["input_exposure_i"].transform("mean")
    out["_log_share_raw"] = (
        np.log(s_lag)
        + theta.share_output * output_shock * out["_ln_mu_center"].fillna(0.0).to_numpy(dtype=float)
        + theta.share_input * input_shock * out["_input_center"].fillna(0.0).to_numpy(dtype=float)
    )
    out["_share_raw"] = np.exp(np.clip(out["_log_share_raw"], -40.0, 20.0))
    out = _normalize_shares(out, "_share_raw", "share_model")

    s_total_lag = s_lag.to_numpy(dtype=float) * lambda_lag
    s_total_current = out["share_model"].to_numpy(dtype=float) * lambda_current
    inv_lag = nested_ces_inverse_markup(
        s_total_lag,
        lambda_lag,
        eta=float(e["eta"]),
        nu=float(e["nu"]),
        rho=float(e["rho"]),
    )
    inv_current_struct = nested_ces_inverse_markup(
        s_total_current,
        lambda_current,
        eta=float(e["eta"]),
        nu=float(e["nu"]),
        rho=float(e["rho"]),
    )
    dln_struct = np.log(1.0 / inv_current_struct) - np.log(1.0 / inv_lag)
    output_markup_effect = theta.output_markup * output_shock
    high_markup_output_effect = (
        theta.high_markup_output * output_shock * out["_ln_mu_center"].fillna(0.0).to_numpy(dtype=float)
    )
    concentration_output_effect = (
        theta.concentration_output * output_shock * out["_concentration_center"].fillna(0.0).to_numpy(dtype=float)
    )
    dln_model = (
        dln_struct
        + output_markup_effect
        + high_markup_output_effect
        + concentration_output_effect
        + theta.input_markup * input_shock
        + theta.mean_reversion * out["_ln_mu_center"].fillna(0.0).to_numpy(dtype=float)
        + theta.drift
    )
    ln_mu_min = np.log(1.0 / 0.98)
    ln_mu_base = np.clip(ln_mu_lag.fillna(out["ln_mu"].median()).to_numpy(dtype=float), ln_mu_min, 5.0)
    out["ln_mu_model"] = np.clip(ln_mu_base + dln_model, ln_mu_min, 5.0)
    out["dln_mu_model"] = out["ln_mu_model"] - ln_mu_base
    out["mu_model"] = np.exp(out["ln_mu_model"])
    out["inv_mu_model"] = 1.0 / out["mu_model"]
    out["lambda_lag_model"] = lambda_lag
    out["lambda_d_model"] = lambda_current
    out["output_shock_model"] = output_shock
    out["input_shock_model"] = input_shock
    out["output_markup_effect_model"] = output_markup_effect
    out["high_markup_output_effect_model"] = high_markup_output_effect
    out["concentration_output_effect_model"] = concentration_output_effect

    exit_index = (
        theta.exit_intercept
        + theta.exit_ip * output_shock
        + theta.exit_markup * out["_ln_mu_center"].fillna(0.0).to_numpy(dtype=float)
    )
    out["exit_prob_model"] = logistic(exit_index)
    out["survival_prob_model"] = 1.0 - out["exit_prob_model"]
    out["scenario"] = scenario
    return out
