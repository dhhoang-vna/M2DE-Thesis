capture confirm global REPLICATION_ROOT
if _rc {
    do "code/00_setup/config.do"
}
else if "${REPLICATION_ROOT}" == "" {
    do "code/00_setup/config.do"
}
/***********************************************************************
KIROV ET AL. (2026) ROBUSTNESS CHECK
- Standalone implementation of the KMT markup estimator
- Makes the KMT sample mechanics explicit
- Saves grid-search results and sample flags for inspection
***********************************************************************/

clear mata
capture log close
clear all
set more off

log using "$LOGS\kirov.log", replace text

global folder "$REPLICATION_ROOT"
global X_lag "lleverage lliquidity llnsize l_age l_exporter"

use "$DATA_DERIVED\data_ready.dta", clear
isid firm_id year, sort
xtset firm_id year

capture confirm variable exporter
if _rc {
    gen byte exporter = export_revenue > 0 if !missing(export_revenue)
}

capture confirm variable l_exporter
if _rc {
    gen byte l_exporter = L.exporter
}

preserve
keep isic4 year HHI_dom
bys isic4 year: keep if _n == 1
xtset isic4 year
gen double l_hhi = L.HHI_dom
keep isic4 year l_hhi
tempfile sectorhhi
save `sectorhhi', replace
restore

merge m:1 isic4 year using `sectorhhi', nogen

sort firm_id year
by firm_id: gen byte has_prev_obs = year == year[_n-1] + 1
replace has_prev_obs = 0 if missing(has_prev_obs)
by firm_id: gen double l_share = share_sales[_n-1] if has_prev_obs

gen double share_x = lnM - lnR

gen byte sample_share = 1
foreach v in firm_id isic4 year lnR lnM lnK share_x l_share l_exporter l_hhi {
    replace sample_share = 0 if missing(`v')
}

reghdfe share_x c.lnM c.lnK c.l_share i.l_exporter c.l_hhi if sample_share, ///
    absorb(firm_id year) vce(cluster isic4) resid
estimates store kirov_share

predict double epshat if e(sample), resid

gen double expeps = exp(epshat) if e(sample)
summ expeps, meanonly
scalar bhat = ln(r(mean))

gen double s_hat = share_x - bhat + epshat if e(sample)

tempfile work
save `work', replace

scalar best_ssr = .
scalar best_a = .

tempname gridhold
postfile `gridhold' double alphaM ssr N using "$DATA_DERIVED\kirov_grid_results.dta", replace

forvalues g = 5/95 {
    use `work', clear
    xtset firm_id year

    scalar a = `g'/100

    gen double fhat = a*lnM + (1-a)*lnK if !missing(lnM, lnK, s_hat)
    gen double vhat = lnM - fhat - s_hat - bhat if !missing(fhat, s_hat)

    by firm_id: gen double l_vhat = vhat[_n-1] if has_prev_obs
    gen double l_vhat2 = l_vhat^2
    gen double l_vhat3 = l_vhat^3

    gen double y2 = lnR - epshat if !missing(epshat)
    gen double ytilde = y2 - fhat if !missing(y2, fhat)

    reg ytilde c.l_vhat c.l_vhat2 c.l_vhat3 if !missing(ytilde, l_vhat), vce(cluster isic4)

    scalar ssr = e(rss)
    scalar N = e(N)
    post `gridhold' (a) (ssr) (N)

    if missing(best_ssr) | ssr < best_ssr {
        scalar best_ssr = ssr
        scalar best_a = a
    }
}

postclose `gridhold'

use `work', clear
xtset firm_id year

scalar a_hat = best_a

gen double alphaM_kmt = a_hat if !missing(s_hat)
gen double alphaK_kmt = 1 - a_hat if !missing(s_hat)
gen double fhat_kmt = alphaM_kmt*lnM + alphaK_kmt*lnK if !missing(alphaM_kmt, lnM, lnK)
gen double vhat_kmt = lnM - fhat_kmt - s_hat - bhat if !missing(fhat_kmt, s_hat)

by firm_id: gen double l_vhat_kmt = vhat_kmt[_n-1] if has_prev_obs
gen double l_vhat2_kmt = l_vhat_kmt^2
gen double l_vhat3_kmt = l_vhat_kmt^3

gen double y2_kmt = lnR - epshat if !missing(epshat)
gen double ytilde_kmt = y2_kmt - fhat_kmt if !missing(y2_kmt, fhat_kmt)

reg ytilde_kmt c.l_vhat_kmt c.l_vhat2_kmt c.l_vhat3_kmt if !missing(ytilde_kmt, l_vhat_kmt), ///
    vce(cluster isic4)
estimates store kirov_markov

predict double etahat_kmt if e(sample), resid

gen double ln_mu_kmt = ln(alphaM_kmt) + lnR - lnM + bhat - epshat if !missing(alphaM_kmt, lnR, lnM, epshat)
gen double mu_kmt = exp(ln_mu_kmt) if !missing(ln_mu_kmt)

by firm_id: gen double dln_mu_kmt = ln_mu_kmt - ln_mu_kmt[_n-1] if has_prev_obs & !missing(ln_mu_kmt, ln_mu_kmt[_n-1])
by firm_id: gen double dmu_kmt = mu_kmt - mu_kmt[_n-1] if has_prev_obs & !missing(mu_kmt, mu_kmt[_n-1])
by firm_id: gen byte prev_lnmu_kmt_available = has_prev_obs & !missing(ln_mu_kmt[_n-1])
replace prev_lnmu_kmt_available = 0 if missing(prev_lnmu_kmt_available)

gen byte sample_kirov_level = inrange(year, 2011, 2019)
foreach v in ln_mu_kmt change_IP output_IV Z_input lleverage lliquidity llnsize l_age l_exporter ls_pre_filled post2016 isic4 {
    replace sample_kirov_level = 0 if missing(`v')
}

gen byte sample_kirov_diff = inrange(year, 2011, 2019)
foreach v in dln_mu_kmt change_IP output_IV Z_input lleverage lliquidity llnsize l_age l_exporter ls_pre_filled post2016 isic4 {
    replace sample_kirov_diff = 0 if missing(`v')
}

gen byte lost_for_diff = sample_kirov_level & !sample_kirov_diff

count if sample_kirov_level
local N_level = r(N)
count if sample_kirov_diff
local N_diff = r(N)
count if lost_for_diff
local N_lost = r(N)
count if lost_for_diff & !has_prev_obs
local N_gap = r(N)
count if lost_for_diff & has_prev_obs & !prev_lnmu_kmt_available
local N_prev_kmt = r(N)

di as text " "
di as text "Kirov/KMT sample diagnostics"
di as text "Level-IV sample size (ln_mu_kmt): " as result `N_level'
di as text "Diff-IV sample size (dln_mu_kmt): " as result `N_diff'
di as text "Lost when moving from levels to differences: " as result `N_lost'
di as text "Lost because previous firm-year is missing (panel gap/entry): " as result `N_gap'
di as text "Lost because previous ln_mu_kmt is unavailable: " as result `N_prev_kmt'
di as text " "
di as text "Interpretation: dln_mu_kmt(t) needs ln_mu_kmt(t) and ln_mu_kmt(t-1),"
di as text "while ln_mu_kmt(t-1) already uses lagged markup shifters."
di as text "So the differenced KMT sample effectively requires three consecutive years."

preserve
contract year if sample_kirov_level
rename _freq N_level
di as text " "
di as text "KMT level-IV sample by year"
list year N_level, clean noobs
restore

preserve
contract year if sample_kirov_diff
rename _freq N_diff
di as text " "
di as text "KMT diff-IV sample by year"
list year N_diff, clean noobs
restore

preserve
keep firm_id isic4 year has_prev_obs sample_share prev_lnmu_kmt_available ///
    sample_kirov_level sample_kirov_diff lost_for_diff ///
    ln_mu_kmt dln_mu_kmt mu_kmt dmu_kmt
save "$DATA_DERIVED\kirov_sample_flags.dta", replace
restore

ivreghdfe dln_mu_kmt (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year ///
    if sample_kirov_diff, absorb(isic4) vce(cluster isic4) partial(i.year)
est store kirov_iv_diff

ivreghdfe ln_mu_kmt (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year ///
    if sample_kirov_level, absorb(isic4) vce(cluster isic4) partial(i.year)
est store kirov_iv_level

est restore kirov_iv_diff
estadd scalar alphaM = a_hat
estadd scalar alphaK = 1 - a_hat
estadd scalar b_hat = bhat

est restore kirov_iv_level
estadd scalar alphaM = a_hat
estadd scalar alphaK = 1 - a_hat
estadd scalar b_hat = bhat

esttab kirov_iv_diff kirov_iv_level using "$OUTPUT_TABLES\kirov_iv.tex", replace ///
    label se star(* 0.10 ** 0.05 *** 0.01) ///
    b(%9.3f) se(%9.3f) ///
    booktabs fragment ///
    mtitles("Dep. var.: dln_mu_kmt" "Dep. var.: ln_mu_kmt") ///
    keep(change_IP Z_input ls_pre_filled 1.post2016 1.post2016#c.ls_pre_filled) ///
    order(change_IP Z_input ls_pre_filled 1.post2016 1.post2016#c.ls_pre_filled) ///
    stats(N alphaM alphaK b_hat, fmt(0 3 3 3) labels("Observations" "\alpha_M" "\alpha_K" "b"))

log close


