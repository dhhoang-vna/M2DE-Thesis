param(
    [string]$ParentRoot = "",
    [string]$OutputCsv = "output/m2de_thesis_exhibit_hash_check.csv"
)

$ErrorActionPreference = "Stop"
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
if (-not $ParentRoot) {
    $ParentRoot = (Resolve-Path (Join-Path $Repo "..")).Path
} else {
    $ParentRoot = (Resolve-Path $ParentRoot).Path
}

$items = @(
    @("figure", "fig_china_ip_context_trimmed.png", "Figs/fig_china_ip_context_trimmed.png", "output/figures/fig_china_ip_context_trimmed.png"),
    @("figure", "lorenz_domestic_sales_2011.pdf", "Figs/lorenz_domestic_sales_2011.pdf", "output/figures/lorenz_domestic_sales_2011.pdf"),
    @("figure", "scatter_CR4_pre_china_exposure.png", "Figs/scatter_CR4_pre_china_exposure.png", "output/figures/scatter_CR4_pre_china_exposure.png"),
    @("figure", "fig_rotemberg_sector_size.pdf", "Figs/fig_rotemberg_sector_size.pdf", "output/figures/fig_rotemberg_sector_size.pdf"),
    @("figure", "iv_quantile_journal.png", "Figs/iv_quantile_journal.png", "output/figures/iv_quantile_journal.png"),
    @("figure", "iv_quantile_cr4_journal.png", "Figs/iv_quantile_cr4_journal.png", "output/figures/iv_quantile_cr4_journal.png"),
    @("figure", "iv_quantile_cr10_journal.png", "Figs/iv_quantile_cr10_journal.png", "output/figures/iv_quantile_cr10_journal.png"),
    @("figure", "sector_size_distribution.jpg", "Figs/sector_size_distribution.jpg", "output/figures/sector_size_distribution.jpg"),
    @("figure", "number_firms_over_time.jpg", "Figs/number_firms_over_time.jpg", "output/figures/number_firms_over_time.jpg"),
    @("figure", "rob41_decquin_notitle.png", "Figs/rob41_decquin_notitle.png", "output/figures/rob41_decquin_notitle.png"),
    @("figure", "rob43_thin_notitle.png", "Figs/rob43_thin_notitle.png", "output/figures/rob43_thin_notitle.png"),
    @("figure", "scm_path_spec2.png", "Figs/scm_path_spec2.png", "output/figures/scm_path_spec2.png"),
    @("figure", "scm_gap_spec1.png", "Figs/scm_gap_spec1.png", "output/figures/scm_gap_spec1.png"),
    @("figure", "scm_gap_spec2.png", "Figs/scm_gap_spec2.png", "output/figures/scm_gap_spec2.png"),
    @("table", "orbis_coverage_appendix.tex", "Tables/orbis_coverage_appendix.tex", "output/tables/orbis_coverage_appendix.tex"),
    @("table", "domestic_sales_export_audit.tex", "Tables/domestic_sales_export_audit.tex", "output/tables/domestic_sales_export_audit.tex"),
    @("table", "tab_top_rotemberg_sector_size.tex", "Tables/tab_top_rotemberg_sector_size.tex", "output/tables/tab_top_rotemberg_sector_size.tex"),
    @("table", "iv_demand_controls.tex", "Tables/iv_demand_controls.tex", "output/tables/iv_demand_controls.tex"),
    @("table", "pretrend_balance_outputIV.tex", "Tables/pretrend_balance_outputIV.tex", "output/tables/pretrend_balance_outputIV.tex"),
    @("table", "rob_resid_firststage.tex", "Tables/rob_resid_firststage.tex", "output/tables/rob_resid_firststage.tex"),
    @("table", "rob_resid_markup_main.tex", "Tables/rob_resid_markup_main.tex", "output/tables/rob_resid_markup_main.tex"),
    @("table", "rob_resid_aux.tex", "Tables/rob_resid_aux.tex", "output/tables/rob_resid_aux.tex"),
    @("table", "rob_chn_gran_mean.tex", "Tables/rob_chn_gran_mean.tex", "output/tables/rob_chn_gran_mean.tex"),
    @("table", "rob_chn_gran_givq_foreign.tex", "Tables/rob_chn_gran_givq_foreign.tex", "output/tables/rob_chn_gran_givq_foreign.tex")
)

function Get-HashOrBlank([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    }
    return ""
}

$rows = foreach ($item in $items) {
    $parentPath = Join-Path $ParentRoot $item[2]
    $packagePath = Join-Path $Repo $item[3]
    $parentExists = Test-Path -LiteralPath $parentPath
    $packageExists = Test-Path -LiteralPath $packagePath
    $parentHash = Get-HashOrBlank $parentPath
    $packageHash = Get-HashOrBlank $packagePath
    [PSCustomObject]@{
        type = $item[0]
        file = $item[1]
        parent_exists = $parentExists
        package_exists = $packageExists
        identical = ($parentExists -and $packageExists -and $parentHash -eq $packageHash)
        parent_sha256 = $parentHash
        package_sha256 = $packageHash
    }
}

$csvPath = Join-Path $Repo $OutputCsv
$csvDir = Split-Path -Parent $csvPath
if ($csvDir -and -not (Test-Path -LiteralPath $csvDir)) {
    New-Item -ItemType Directory -Force -Path $csvDir | Out-Null
}
$rows | Export-Csv -NoTypeInformation -Path $csvPath

$mismatches = @($rows | Where-Object { -not $_.identical })
Write-Host ("Checked {0} m2de_thesis external exhibits against {1}." -f $rows.Count, $ParentRoot)
Write-Host ("Identical: {0}; mismatched or missing: {1}" -f ($rows.Count - $mismatches.Count), $mismatches.Count)
if ($mismatches.Count -gt 0) {
    $mismatches | Select-Object type, file, parent_exists, package_exists | Format-Table -AutoSize
    exit 1
}
