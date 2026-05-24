from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd


def plot_moment_fit(moment_table: pd.DataFrame, path: Path) -> None:
    if moment_table.empty:
        return
    mt = moment_table.copy().sort_values("moment")
    fig, ax = plt.subplots(figsize=(10, max(4, 0.35 * len(mt))))
    y = range(len(mt))
    ax.scatter(mt["data"], y, label="Data", color="#1f77b4")
    ax.scatter(mt["model"], y, label="Model", color="#d62728", marker="x")
    ax.set_yticks(list(y))
    ax.set_yticklabels(mt["moment"])
    ax.axvline(0, color="0.85", linewidth=1)
    ax.set_xlabel("Moment value")
    ax.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def plot_counterfactual_aggregate(aggregate: pd.DataFrame, path: Path) -> None:
    fig, ax = plt.subplots(figsize=(8, 4.5))
    for scenario, g in aggregate.groupby("scenario"):
        g = g.sort_values("year")
        ax.plot(g["year"], g["inv_mu_m"], marker="o", linewidth=1.8, label=scenario)
    ax.set_xlabel("Year")
    ax.set_ylabel("Manufacturing inverse markup")
    ax.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)


def plot_decomposition(decomp: pd.DataFrame, path: Path) -> None:
    if decomp.empty:
        return
    cols = ["within_inv_mu", "between_inv_mu", "entry_inv_mu", "exit_inv_mu"]
    agg = decomp.groupby("scenario")[cols].mean().reindex(columns=cols)
    fig, ax = plt.subplots(figsize=(8, 4.5))
    agg.plot(kind="bar", stacked=True, ax=ax, width=0.75)
    ax.axhline(0, color="0.2", linewidth=0.8)
    ax.set_ylabel("Average sector-year contribution")
    ax.set_xlabel("")
    ax.legend(frameon=False, fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=200)
    plt.close(fig)
