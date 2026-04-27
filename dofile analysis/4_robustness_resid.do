/***********************************************************************
ROBUSTNESS CHECK: RESIDUALIZED OUTPUT-COMPETITION SHOCK
- Orthogonalize output_IV with respect to Z_input at the sector-year level
- Re-run core markup specifications with the residualized IV
- Validate whether the main-text signs survive in the key outcome block
***********************************************************************/

clear mata
capture log close
clear all
set more off

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"
log using "$folder\Logs\4_robustness_resid.log", replace

foreach cmd in reghdfe ivreghdfe eststo esttab estadd {
    capture which `cmd'
    if _rc {
        di as error "`cmd' is not installed. Install it before running this do-file."
        exit 199
    }
}

capture which boottest
local has_boottest = (_rc == 0)

use "$folder\Data\data_ready_mec.dta", clear

drop if missing(firm_id) | missing(year) | missing(isic4)
xtset firm_id year
sort firm_id year

* Rebuild lagged controls defensively in case the working dataset changed.
capture confirm variable exporter
if _rc {
    gen byte exporter = export_revenue > 0 if !missing(export_revenue)
}

capture confirm variable l_exporter
if _rc {
    gen byte l_exporter = L.exporter
}

capture confirm variable llnsize
if _rc {
    gen double llnsize = L.lnSize
}

capture confirm variable lleverage
if _rc {
    gen double lleverage = L.leverage
}

capture confirm variable lliquidity
if _rc {
    gen double lliquidity = L.liquidity_ratio_x_
}

capture confirm variable l_age
if _rc {
    gen double l_age = L.age
}

capture confirm variable S
if _rc {
    gen byte S = !missing(dln_mu)
}

capture confirm variable dln_dom_sales
if _rc {
    capture drop ln_dom_sales
    gen double ln_dom_sales = ln(dom_sales) if dom_sales > 0 & !missing(dom_sales)
    gen double dln_dom_sales = D.ln_dom_sales
}

capture confirm variable dln_export
if _rc {
    capture drop ln_export
    gen double ln_export = ln(export_revenue) if export_revenue > 0 & !missing(export_revenue)
    gen double dln_export = D.ln_export
}

global X_lag "lleverage lliquidity llnsize l_age l_exporter"

*=========================================
* 1. Residualize output competition on Z_input
*=========================================
preserve
keep if inrange(year, 2011, 2019)
keep isic4 year output_IV Z_input
collapse (mean) output_IV Z_input, by(isic4 year)

reghdfe output_IV Z_input, absorb(isic4 year) resid
predict double output_IV_resid, resid

quietly corr output_IV Z_input
matrix C_raw = r(C)
scalar corr_raw = C_raw[1,2]

quietly corr output_IV_resid Z_input
matrix C_resid = r(C)
scalar corr_resid = C_resid[1,2]

tempfile iv_resid_map
keep isic4 year output_IV_resid
save `iv_resid_map'
restore

merge m:1 isic4 year using `iv_resid_map', keep(master match) nogen
label variable output_IV_resid "Residualized output-competition IV"

di as txt "Correlation(output_IV, Z_input) at sector-year level: " ///
    as result %9.4f corr_raw
di as txt "Correlation(output_IV_resid, Z_input) at sector-year level: " ///
    as result %9.4f corr_resid

*=========================================
* 2. First-stage comparison
*=========================================
eststo clear

reghdfe change_IP output_IV Z_input $X_lag c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4)
estadd local IVtype "Original output IV"
eststo fs_main

reghdfe change_IP output_IV_resid Z_input $X_lag c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4)
estadd local IVtype "Residualized output IV"
eststo fs_resid

esttab fs_main fs_resid using "$folder\Tables\rob_resid_firststage.tex", ///
    replace se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(output_IV output_IV_resid Z_input) ///
    order(output_IV output_IV_resid Z_input) ///
    stats(N r2 IVtype, fmt(0 3 %s) ///
          labels("Observations" "R-sq." "Instrument")) ///
    mtitles("Main IV" "Residualized IV") ///
    title("First-stage comparison: original vs residualized output IV")

*=========================================
* 3. Baseline markup comparison
*=========================================
eststo clear

scalar wild_p_main = .
ivreghdfe dln_mu (change_IP = output_IV) Z_input $X_lag ///
    c.ls_pre_filled##i.post2016 i.year ///
    if S == 1 & inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
capture estadd scalar kpF = e(widstat)
if `has_boottest' {
    capture noisily boottest change_IP, cluster(isic4) reps(999) seed(12345)
    capture confirm number r(p)
    if !_rc scalar wild_p_main = r(p)
}
estadd scalar wild_p = wild_p_main
estadd local IVtype "Original output IV"
eststo mu_main

scalar wild_p_resid = .
ivreghdfe dln_mu (change_IP = output_IV_resid) Z_input $X_lag ///
    c.ls_pre_filled##i.post2016 i.year ///
    if S == 1 & inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
capture estadd scalar kpF = e(widstat)
if `has_boottest' {
    capture noisily boottest change_IP, cluster(isic4) reps(999) seed(12345)
    capture confirm number r(p)
    if !_rc scalar wild_p_resid = r(p)
}
estadd scalar wild_p = wild_p_resid
estadd local IVtype "Residualized output IV"
eststo mu_resid

esttab mu_main mu_resid using "$folder\Tables\rob_resid_markup_main.tex", ///
    replace se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(change_IP Z_input) ///
    order(change_IP Z_input) ///
    stats(N kpF wild_p IVtype, fmt(0 2 3 %s) ///
          labels("Observations" "KP rk Wald F" "Wild-cluster p-value" "Instrument")) ///
    mtitles("Main IV" "Residualized IV") ///
    title("Markup response: original vs residualized output IV")

*=========================================
* 4. Control-set sensitivity with residualized IV
*=========================================
preserve
keep firm_id isic4 year dln_mu change_IP output_IV_resid Z_input ///
     llnsize lleverage lliquidity l_age l_exporter ///
     ls_pre_filled post2016

collapse (mean) dln_mu change_IP output_IV_resid Z_input ///
    llnsize lleverage lliquidity l_age l_exporter ///
    ls_pre_filled post2016, by(firm_id isic4 year)

xtset firm_id year
gen double change_IP_sq = change_IP^2
gen double output_IV_resid_sq = output_IV_resid^2

eststo clear

scalar wild_p_base = .
ivreghdfe dln_mu ///
    (change_IP = output_IV_resid) ///
    Z_input llnsize lleverage lliquidity l_age l_exporter ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
if `has_boottest' {
    capture noisily boottest change_IP, cluster(isic4) reps(999) seed(12345)
    capture confirm number r(p)
    if !_rc scalar wild_p_base = r(p)
}
estadd scalar wild_p = wild_p_base
estadd local spec "Baseline"
eststo rr12_base

ivreghdfe dln_mu ///
    (change_IP change_IP_sq = output_IV_resid output_IV_resid_sq) ///
    Z_input llnsize lleverage lliquidity l_age l_exporter ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar wild_p = .
estadd local spec "Quadratic"
eststo rr12_sq

ivreghdfe dln_mu ///
    (change_IP = output_IV_resid) ///
    Z_input llnsize lleverage lliquidity l_exporter ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar wild_p = .
estadd local spec "No age"
eststo rr12_ctr1

ivreghdfe dln_mu ///
    (change_IP = output_IV_resid) ///
    Z_input lleverage lliquidity l_exporter ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar wild_p = .
estadd local spec "No age, size"
eststo rr12_ctr2

ivreghdfe dln_mu ///
    (change_IP = output_IV_resid) ///
    Z_input lleverage lliquidity ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar wild_p = .
estadd local spec "No age, size, exporter"
eststo rr12_ctr3

ivreghdfe dln_mu ///
    (change_IP = output_IV_resid) ///
    Z_input lleverage ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar wild_p = .
estadd local spec "No age, size, exporter, liquidity"
eststo rr12_ctr4

ivreghdfe dln_mu ///
    (change_IP = output_IV_resid) ///
    Z_input lleverage i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar wild_p = .
estadd local spec "No age, size, exporter, liquidity, LSxPost"
eststo rr12_ctr5

ivreghdfe dln_mu ///
    (change_IP = output_IV_resid) ///
    lleverage i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar wild_p = .
estadd local spec "No input shock"
eststo rr12_ctr6

ivreghdfe dln_mu ///
    (change_IP = output_IV_resid) ///
    i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
estadd scalar wild_p = .
estadd local spec "No controls"
eststo rr12_ctr7

esttab rr12_base rr12_sq rr12_ctr1 rr12_ctr2 rr12_ctr3 ///
       rr12_ctr4 rr12_ctr5 rr12_ctr6 rr12_ctr7 ///
    using "$folder\Tables\rob_resid_fe.tex", ///
    replace se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(change_IP change_IP_sq Z_input) ///
    stats(N wild_p spec, fmt(0 3 %s) ///
          labels("Observations" "Wild-cluster p-value (baseline only)" "Specification")) ///
    title("Residualized output IV: functional-form and control sensitivity") ///
    mtitle("(1)" "(2)" "(3)" "(4)" "(5)" "(6)" "(7)" "(8)" "(9)")
restore

*=========================================
* 5. Validate main-text signs on key outcomes
*=========================================
eststo clear

tempname signpost
tempfile signcheck
postfile `signpost' str24 outcome double beta_main se_main ///
    beta_resid se_resid N_main N_resid same_sign using `signcheck', replace

* 5.1 Markup growth
ivreghdfe dln_mu (change_IP = output_IV) Z_input $X_lag ///
    c.ls_pre_filled##i.post2016 i.year ///
    if S == 1 & inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
scalar b_main = _b[change_IP]
scalar se_main = _se[change_IP]
scalar n_main = e(N)
capture estadd scalar kpF = e(widstat)
estadd local IVtype "Main IV"
eststo aux_mu_main

ivreghdfe dln_mu (change_IP = output_IV_resid) Z_input $X_lag ///
    c.ls_pre_filled##i.post2016 i.year ///
    if S == 1 & inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
scalar b_resid = _b[change_IP]
scalar se_resid = _se[change_IP]
scalar n_resid = e(N)
scalar sign_ok = (sign(b_main) == sign(b_resid))
post `signpost' ("Markup growth") (b_main) (se_main) (b_resid) (se_resid) (n_main) (n_resid) (sign_ok)
capture estadd scalar kpF = e(widstat)
estadd local IVtype "Residualized IV"
eststo aux_mu_resid

* 5.2 Revenue growth
ivreghdfe dln_rev (change_IP = output_IV) Z_input $X_lag ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
scalar b_main = _b[change_IP]
scalar se_main = _se[change_IP]
scalar n_main = e(N)
capture estadd scalar kpF = e(widstat)
estadd local IVtype "Main IV"
eststo aux_rev_main

ivreghdfe dln_rev (change_IP = output_IV_resid) Z_input $X_lag ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
scalar b_resid = _b[change_IP]
scalar se_resid = _se[change_IP]
scalar n_resid = e(N)
scalar sign_ok = (sign(b_main) == sign(b_resid))
post `signpost' ("Revenue growth") (b_main) (se_main) (b_resid) (se_resid) (n_main) (n_resid) (sign_ok)
capture estadd scalar kpF = e(widstat)
estadd local IVtype "Residualized IV"
eststo aux_rev_resid

* 5.3 Domestic sales growth
ivreghdfe dln_dom_sales (change_IP = output_IV) Z_input $X_lag ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019) & !missing(dln_dom_sales), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
scalar b_main = _b[change_IP]
scalar se_main = _se[change_IP]
scalar n_main = e(N)
capture estadd scalar kpF = e(widstat)
estadd local IVtype "Main IV"
eststo aux_dom_main

ivreghdfe dln_dom_sales (change_IP = output_IV_resid) Z_input $X_lag ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019) & !missing(dln_dom_sales), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
scalar b_resid = _b[change_IP]
scalar se_resid = _se[change_IP]
scalar n_resid = e(N)
scalar sign_ok = (sign(b_main) == sign(b_resid))
post `signpost' ("Domestic sales") (b_main) (se_main) (b_resid) (se_resid) (n_main) (n_resid) (sign_ok)
capture estadd scalar kpF = e(widstat)
estadd local IVtype "Residualized IV"
eststo aux_dom_resid

* 5.4 Export growth
ivreghdfe dln_export (change_IP = output_IV) Z_input ///
    lleverage lliquidity llnsize l_age ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019) & !missing(dln_export), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
scalar b_main = _b[change_IP]
scalar se_main = _se[change_IP]
scalar n_main = e(N)
capture estadd scalar kpF = e(widstat)
estadd local IVtype "Main IV"
eststo aux_exp_main

ivreghdfe dln_export (change_IP = output_IV_resid) Z_input ///
    lleverage lliquidity llnsize l_age ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019) & !missing(dln_export), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
scalar b_resid = _b[change_IP]
scalar se_resid = _se[change_IP]
scalar n_resid = e(N)
scalar sign_ok = (sign(b_main) == sign(b_resid))
post `signpost' ("Export growth") (b_main) (se_main) (b_resid) (se_resid) (n_main) (n_resid) (sign_ok)
capture estadd scalar kpF = e(widstat)
estadd local IVtype "Residualized IV"
eststo aux_exp_resid

postclose `signpost'

esttab aux_mu_main aux_mu_resid aux_rev_main aux_rev_resid ///
       aux_dom_main aux_dom_resid aux_exp_main aux_exp_resid ///
    using "$folder\Tables\rob_resid_aux.tex", ///
    replace se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(change_IP Z_input) ///
    order(change_IP Z_input) ///
    stats(N kpF IVtype, fmt(0 2 %s) ///
          labels("Observations" "KP rk Wald F" "Instrument")) ///
    mtitles("Markup: main" "Markup: resid" ///
            "Revenue: main" "Revenue: resid" ///
            "Domestic: main" "Domestic: resid" ///
            "Exports: main" "Exports: resid") ///
    title("Main-text outcome validation with residualized output IV")

preserve
use `signcheck', clear
format beta_main se_main beta_resid se_resid %9.3f
format N_main N_resid same_sign %9.0f
sort outcome
export delimited using "$folder\Tables\rob_resid_signcheck.csv", replace
save "$folder\Data\rob_resid_signcheck.dta", replace
list, noobs clean
restore

di as txt "Residualized-IV robustness check completed."
log close
