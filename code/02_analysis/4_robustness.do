capture confirm global REPLICATION_ROOT
if _rc {
    do "code/00_setup/config.do"
}
else if "${REPLICATION_ROOT}" == "" {
    do "code/00_setup/config.do"
}
/***********************************************************************
ROBUSTNESS CHECKS
- Identification robustness and inference
- Alternative markup measures (Cobb-Douglas / Translog / KMT)
- Selection and composition robustness
- Distributional design checks
***********************************************************************/

clear mata
capture log close
clear

log using "$LOGS\4 robustness", replace

global folder "$REPLICATION_ROOT"

use "$DATA_DERIVED\data_ready.dta", clear

drop if missing(firm_id) | missing(year) | missing(isic4)
xtset firm_id year

capture confirm variable post2016
if _rc gen byte post2016 = year >= 2016 if !missing(year)
capture confirm variable llnsize
if _rc gen llnsize = L.lnSize
capture confirm variable lleverage
if _rc gen lleverage = L.leverage
capture confirm variable lliquidity
if _rc gen lliquidity = L.liquidity_ratio_x_
capture confirm variable l_age
if _rc gen l_age = L.age
capture confirm variable exporter
if _rc gen byte exporter = (export_revenue>0) if !missing(export_revenue)
capture confirm variable l_exporter
if _rc gen l_exporter = L.exporter

global X_lag "lleverage lliquidity llnsize l_age l_exporter"

save "$DATA_DERIVED\data_ready.dta", replace


*====================================
* 1. IDENTIFICATION AND INFERENCE
*====================================

*----------------------------------------------------------------
* 1.1 Lead-placebo / pretrend test using future output shocks
*----------------------------------------------------------------
preserve
collapse (mean) output_IV Z_input change_IP, by(isic4 year)
xtset isic4 year
gen Z_f1 = F1.output_IV
gen Z_f2 = F2.output_IV
gen Z_f3 = F3.output_IV
keep isic4 year Z_f1 Z_f2 Z_f3
tempfile futureZ
save `futureZ'
restore

merge m:1 isic4 year using `futureZ', nogen

preserve
collapse (mean) dln_mu Z_f1 Z_f2 Z_f3 Z_input age leverage lnSize ls_pre_filled post2016 $X_lag, by(firm_id isic4 year)
xtset firm_id year

reghdfe dln_mu Z_f1 Z_input L.Z_input $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(isic4 year) vce(cluster isic4)
est store ROB_PRETREND_1

reghdfe dln_mu Z_f2 Z_input L.Z_input $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(isic4 year) vce(cluster isic4)
est store ROB_PRETREND_2

reghdfe dln_mu Z_f3 Z_input L.Z_input $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(isic4 year) vce(cluster isic4)
est store ROB_PRETREND_3

reghdfe dln_mu Z_f1 Z_f2 Z_f3 Z_input L.Z_input $X_lag c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(isic4 year) vce(cluster isic4)
test Z_f1 Z_f2 Z_f3
di "Joint placebo p-value: " r(p)
restore

*-----------------------------------------
* 1.2. FE and functional-form variants
*-----------------------------------------
preserve

* Keep only variables needed
keep firm_id isic4 year dln_mu change_IP output_IV Z_input ///
     llnsize lleverage lliquidity l_age l_exporter ///
     ls_pre_filled post2016

* If duplicate firm-year observations truly exist, aggregate them
collapse (mean) dln_mu change_IP output_IV Z_input ///
    llnsize lleverage lliquidity l_age l_exporter ///
    ls_pre_filled post2016, by(firm_id isic4 year)

xtset firm_id year

* Nonlinear terms
gen change_IP_sq = change_IP^2
gen output_IV_sq = output_IV^2

*-------------------------------*
* (1) Baseline
*-------------------------------*
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    Z_input llnsize lleverage lliquidity l_age l_exporter ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
eststo rob12_base

* Wild-cluster bootstrap for baseline ONLY
capture noisily boottest change_IP, cluster(isic4) reps(999) seed(12345)
scalar wild_p_base = .
capture confirm number r(p)
if !_rc scalar wild_p_base = r(p)
estadd scalar wild_p = wild_p_base
estadd local spec "Baseline"

*-------------------------------*
* (2) Quadratic endogenous effect
*-------------------------------*
ivreghdfe dln_mu ///
    (change_IP change_IP_sq = output_IV output_IV_sq) ///
    Z_input llnsize lleverage lliquidity l_age l_exporter ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
eststo rob12_sq
estadd scalar wild_p = .
estadd local spec "Quadratic"

*-------------------------------*
* (3) No age
*-------------------------------*
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    Z_input llnsize lleverage lliquidity l_exporter ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
eststo rob12_ctr1
estadd scalar wild_p = .
estadd local spec "No age"

*-------------------------------*
* (4) No age, no size
*-------------------------------*
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    Z_input lleverage lliquidity l_exporter ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
eststo rob12_ctr2
estadd scalar wild_p = .
estadd local spec "No age, size"

*-------------------------------*
* (5) No age, size, exporter
*-------------------------------*
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    Z_input lleverage lliquidity ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
eststo rob12_ctr3
estadd scalar wild_p = .
estadd local spec "No age, size, exporter"

*-------------------------------*
* (6) No age, size, exporter, liquidity
*-------------------------------*
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    Z_input lleverage ///
    c.ls_pre_filled##i.post2016 i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
eststo rob12_ctr4
estadd scalar wild_p = .
estadd local spec "No age, size, exporter, liquidity"

*-------------------------------*
* (7) No age, size, exporter, liquidity, labor-share interaction
*-------------------------------*
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    Z_input lleverage i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
eststo rob12_ctr5
estadd scalar wild_p = .
estadd local spec "No age, size, exporter, liquidity, LSxPost"

*-------------------------------*
* (8) No input shock
*-------------------------------*
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    lleverage i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
eststo rob12_ctr6
estadd scalar wild_p = .
estadd local spec "No input shock"

*-------------------------------*
* (9) No controls
*-------------------------------*
ivreghdfe dln_mu ///
    (change_IP = output_IV) ///
    i.year ///
    if inrange(year, 2011, 2019), ///
    absorb(isic4) vce(cluster isic4) partial(i.year)
eststo rob12_ctr7
estadd scalar wild_p = .
estadd local spec "No controls"

restore

*-------------------------------*
* Export table
*-------------------------------*
esttab rob12_base rob12_sq rob12_ctr1 rob12_ctr2 rob12_ctr3 ///
       rob12_ctr4 rob12_ctr5 rob12_ctr6 rob12_ctr7 ///
    using "$OUTPUT_TABLES\rob12_fe.tex", ///
    replace se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(change_IP change_IP_sq Z_input) ///
    stats(N wild_p spec, ///
          fmt(0 3 %s) ///
          labels("Observations" "Wild-cluster p-value (baseline only)" "Specification")) ///
    title("Functional-form and control sensitivity") ///
    mtitle("(1)" "(2)" "(3)" "(4)" "(5)" "(6)" "(7)" "(8)" "(9)")

*--------------------------------------------
* 1.3 Instrument influence diagnostic (drop top 10% influential sectors)
*--------------------------------------------

*** (1) Compute Rotemberg sector weights

preserve
collapse (mean) dln_mu change_IP output_IV Z_input $X_lag ls_pre_filled post2016, by(firm_id isic4 year)

keep if inrange(year, 2011, 2019)

//resid the endogenous regressor
reghdfe change_IP Z_input c.ls_pre_filled##i.post2016 i.year, absorb(isic4) resid
predict double x_tilde, resid

//resid the full Bartik instrument
reghdfe output_IV Z_input c.ls_pre_filled##i.post2016 i.year, absorb(isic4) resid
predict double z_tilde, resid

gen double xz = x_tilde * z_tilde
sum xz, meanonly
scalar denom = r(sum)

//build sector-specific Bartik components & compute weights
tempname memhold
tempname rotemberg
postfile `memhold' str20 isic4_str double alpha abs_alpha using `rotemberg', replace

levelsof isic4, local(sectors)

foreach s of local sectors {
    gen double z_comp = cond(isic4 == `s', output_IV, 0)

    reghdfe z_comp Z_input c.ls_pre_filled##i.post2016 i.year, absorb(isic4) resid
    predict double zc_tilde, resid

    gen double xzc = x_tilde * zc_tilde
    sum xzc, meanonly
    scalar a = r(sum) / denom

    post `memhold' ("`s'") (a) (abs(a))

    drop z_comp zc_tilde xzc
}

postclose `memhold'

use `rotemberg', clear
gsort -abs_alpha
gen rank_abs = _n

* 5) Concentration diagnostics
egen sum_abs = total(abs_alpha)
gen abs_share = abs_alpha / sum_abs
gen abs_share_sq = abs_share^2
egen HHI_abs = total(abs_share_sq)

gen top1_abs  = abs_share if rank_abs == 1
gen top5_abs  = abs_share if rank_abs <= 5
gen top10_abs = abs_share if rank_abs <= 10

egen top1_sum  = total(top1_abs)
egen top5_sum  = total(top5_abs)
egen top10_sum = total(top10_abs)

list isic4_str alpha abs_alpha abs_share rank_abs in 1/15, noobs sep(0)

display "HHI of normalized absolute Rotemberg weights = " HHI_abs[1]
display "Top 1 absolute weight share = " top1_sum[1]
display "Top 5 absolute weight share = " top5_sum[1]
display "Top 10 absolute weight share = " top10_sum[1]

tempfile rotemberg_weights
save `rotemberg_weights', replace

restore

**** (2) Create exclusion lists for the most influential sectors

use `rotemberg_weights', clear
gsort -abs_alpha
gen drop_top5 = rank_abs <= 5
gen drop_top10 = rank_abs <= 10

count
scalar Nsec = r(N)
gen drop_top10pct = rank_abs <= ceil(0.10 * Nsec)

keep isic4_str alpha abs_alpha rank_abs drop_top5 drop_top10 drop_top10pct

rename isic4_str isic4
destring isic4, replace

save "$DATA_DERIVED\rotemberg_drop_lists.dta", replace

**** (3) Merge drop lists back to main data
use "$DATA_DERIVED\data_ready.dta", clear

merge m:1 isic4 using "$DATA_DERIVED\rotemberg_drop_lists.dta", nogen

replace drop_top5 = 0 if missing(drop_top5)
replace drop_top10 = 0 if missing(drop_top10)
replace drop_top10pct = 0 if missing(drop_top10pct)

* Baseline
ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age l_exporter c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year) first savefirst savefprefix(fs_)
est store est13_base
estadd scalar kpF = e(widstat)

* Drop top 5 weighted sectors
ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age l_exporter c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & drop_top5 == 0, absorb(isic4) vce(cluster isic4) partial(i.year) first savefirst savefprefix(fs5_)
est store est13_top5
estadd scalar kpF = e(widstat)

* Drop top 10 weighted sectors
ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age l_exporter c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & drop_top10 == 0, absorb(isic4) vce(cluster isic4) partial(i.year) first savefirst savefprefix(fs10_)
est store est13_top10
estadd scalar kpF = e(widstat)

* Drop top 10% weighted sectors
ivreghdfe dln_mu (change_IP = output_IV) Z_input llnsize lleverage lliquidity l_age l_exporter c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & drop_top10pct == 0, absorb(isic4) vce(cluster isic4) partial(i.year) first savefirst savefprefix(fs10pc_)
est store est13_top10pc
estadd scalar kpF = e(widstat)

* Output table
*----------------------------
* Panel A: second stage
*----------------------------
esttab est13_base est13_top5 est13_top10 est13_top10pc using "$OUTPUT_TABLES\rob13_rotemberg.tex", ///
    replace se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(change_IP Z_input) ///
    stats(N kpF, labels("Observations" "KP rk Wald F")) ///
    title("Robustness to excluding sectors with largest Rotemberg weights") ///
    posthead("\hline \multicolumn{5}{l}{\textbf{Panel A. Second stage}}\\") ///
    nonotes

*----------------------------
* Panel B: first stage
*----------------------------
esttab fs_change_IP fs5_change_IP fs10_change_IP fs10pc_change_IP using "$OUTPUT_TABLES\rob13_rotemberg.tex", ///
    append se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(output_IV Z_input) ///
    stats(N, labels("Observations")) ///
    posthead("\hline \multicolumn{5}{l}{\textbf{Panel B. First stage}}\\") ///
    nomtitles nonumbers nonotes

* Optional common footnote
capture erase "$OUTPUT_TABLES\rob13_rotemberg_tmp.tex"
* filefilter backslash handling differs across Stata builds; esttab output is
* already usable here, so keep the table unchanged for reproducibility.
	

*===================================
* 2. ALTERNATIVE MARKUP ESTIMATION 
*===================================

*------------------------
* 2.1 KMT methodology (sample drop!?!!?)
*------------------------

**** (1) Setup
preserve
keep isic4 year HHI_dom
bys isic4 year: keep if _n==1
xtset isic4 year
bys isic4 (year): gen l_hhi = L.HHI_dom
keep isic4 year l_hhi
tempfile sectorhhi
save `sectorhhi', replace
restore

merge m:1 isic4 year using `sectorhhi', nogen


preserve
keep firm_id isic4 year change_IP output_IV Z_input $X_lag ls_pre_filled post2016 lnR lnM cogs lnK HHI_dom l_hhi share_sales

drop if missing(firm_id, isic4, year, lnR, lnM, lnK)
xtset firm_id year

**** (2) First stage: share_x = s_hat + b - eps
gen share_x = lnM - lnR
gen l_share = L.share_sales

reghdfe share_x c.lnM c.lnK c.l_share i.l_exporter c.l_hhi, absorb(firm_id year) vce(cluster isic4) resid

est store rob21_kmt1

predict double epshat, resid

// compute bhat = log(mean(esphat))
gen double expeps = exp(epshat)
summ expeps, meanonly
scalar bhat = ln(r(mean))

// recover composite object: s_hat = log(fx) - mu
gen double s_hat = share_x - bhat + epshat

**** (4) Second stage: grid search, CRS imposed ex-ante
tempfile work
save `work', replace

scalar best_ssr = .
scalar best_a = .

tempname memhold
postfile `memhold' alpha ssr N using "$DATA_DERIVED\kmt_grid_results.dta", replace

// Grid search over alpha_M under CRS
forvalues g = 5/95 {
	use `work', clear 
	scalar a = `g'/100
	gen double fhat = a*lnM + (1-a)*lnK
	gen double vhat = lnM - fhat - s_hat - bhat
	xtset firm_id year
	gen double l_vhat = L.vhat
	gen double l_vhat2 = L.vhat^2
	gen double l_vhat3 = L.vhat^3
	gen double y2 = lnR - epshat
	gen double ytilde = y2 - fhat
	reg ytilde c.l_vhat c.l_vhat2 c.l_vhat3 if !missing(ytilde, l_vhat), vce(cluster isic4)
	
	scalar ssr = e(rss)
	scalar N = e(N)
	post `memhold' (a) (ssr) (N)
	
	// update best alpha
	if missing(best_ssr) | ssr < best_ssr {
		scalar best_ssr = ssr
		scalar best_a = a
	}
}
postclose `memhold'

use "$DATA_DERIVED\kmt_grid_results.dta", clear
sort ssr
list in 1/10, clean noobs
scalar list best_a best_ssr

// Second stage at best alpha
use `work', clear
xtset firm_id year
scalar a_hat = best_a
gen double alphaM_kmt = a_hat
gen double alphaK_kmt = 1 - a_hat
gen double fhat_kmt = alphaK_kmt*lnK + alphaM_kmt*lnM
gen double vhat_kmt = lnM - fhat_kmt - s_hat - bhat
gen double l_vhat_kmt = L.vhat_kmt
gen double l_vhat2_kmt = l_vhat_kmt^2
gen double l_vhat3_kmt = l_vhat_kmt^3
gen double y2_kmt = lnR - epshat
gen double ytilde_kmt = y2_kmt - fhat_kmt

reg ytilde_kmt c.l_vhat_kmt c.l_vhat2_kmt c.l_vhat3_kmt if !missing(ytilde_kmt, l_vhat_kmt), vce(cluster isic4)

est store rob21_kmt2
predict double etahat_kmt if e(sample), resid

**** (5) Construct KMT markup estimates
gen double ln_mu_kmt = ln(alphaM_kmt) + lnR - lnM + bhat - epshat
gen double mu_kmt = exp(ln_mu_kmt)
gen double dln_mu_kmt = D.ln_mu_kmt
gen double dmu_kmt = D.mu_kmt

tempfile kmtvars
keep firm_id year mu_kmt ln_mu_kmt dln_mu_kmt dmu_kmt
bys firm_id year: keep if _n == 1
save `kmtvars', replace

**** (6) Run IV specification
use `work', clear
merge 1:1 firm_id year using `kmtvars', nogen

ivreghdfe dln_mu_kmt (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & !missing(dln_mu_kmt), absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob21_iv1

ivreghdfe ln_mu_kmt (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & !missing(ln_mu_kmt), absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob21_iv2

**** (7) Table
capture which esttab
if _rc {
    di as error "esttab is required. Run code/00_setup/install_stata_packages.do before this script."
    exit 499
}

est restore rob21_iv1
estadd local YearFE "Yes"
estadd local SectorFE "Yes"
estadd local Cluster "ISIC4"
estadd scalar alphaM = a_hat 
estadd scalar alphaK = 1 - a_hat
estadd scalar b_hat = bhat

est restore rob21_iv2
estadd local YearFE "Yes"
estadd local SectorFE "Yes"
estadd local Cluster "ISIC4"
estadd scalar alphaM = a_hat
estadd scalar alphaK = 1 - a_hat
estadd scalar b_hat  = bhat

esttab rob21_iv1 rob21_iv2 using "$OUTPUT_TABLES\rob21_kmt_iv.tex", replace ///
    label se star(* 0.10 ** 0.05 *** 0.01) ///
    b(%9.3f) se(%9.3f) ///
    booktabs fragment ///
    mtitles("Dep. var.: dln_mu_kmt" "Dep. var.: ln_mu_kmt") ///
    keep(change_IP Z_input ls_pre_filled 1.post2016 1.post2016#c.ls_pre_filled) ///
    order(change_IP Z_input ls_pre_filled 1.post2016 1.post2016#c.ls_pre_filled) ///
    stats(N alphaM alphaK b_hat, ///
          fmt(0 3 3 3) ///
          labels("Observations" "\alpha_M" "\alpha_K" "b"))

restore

merge 1:1 firm_id year using `kmtvars', nogen


corr ln_mu ln_mu_kmt

ivreghdfe ln_mu_kmt (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2010, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)

gen byte sample_kmt = !missing(dln_mu_kmt)


*-------------------------------
* 2.2. Trimming/winsorization
*-------------------------------
preserve
collapse (mean) dln_mu change_IP output_IV Z_input $X_lag ls_pre_filled post2016, by(firm_id isic4 year)
xtset firm_id year

ivreghdfe dln_mu (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob22_base

clonevar dln_mu_w595 = dln_mu
winsor2 dln_mu_w595, cuts(5 95) replace
ivreghdfe dln_mu_w595 (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob22_1

clonevar dln_mu_w05995 = dln_mu
winsor2 dln_mu_w05995, cuts(0.5 99.5) replace
ivreghdfe dln_mu_w05995 (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob22_2

esttab rob22_base rob22_1 rob22_2 using "$OUTPUT_TABLES\rob22_trimming.tex", ///
    replace se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(change_IP Z_input) ///
    stats(N, labels("Observations")) ///
    title("Trimming/winsorization")
restore


*=====================================
* 3. SELECTION AND PANEL COMPOSITION
*=====================================

preserve
keep firm_id isic4 year dln_mu change_IP output_IV Z_input $X_lag ls_pre_filled post2016 lnSize
drop if missing(dln_mu, change_IP, output_IV, Z_input, ls_pre_filled, post2016, lnSize)
foreach v of varlist $X_lag {
    drop if missing(`v')
}
xtset firm_id year

*----------------------------------------------
* 3.1. The case of long-lived firms/balanced samples 
*----------------------------------------------

bys firm_id: egen n_t = count(year)

ivreghdfe dln_mu (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & n_t>=8, absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob3_bal8

ivreghdfe dln_mu (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & n_t>=7, absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob3_bal7

ivreghdfe dln_mu (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & n_t>=6, absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob3_bal6

ivreghdfe dln_mu (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & n_t>=5, absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob3_bal5

ivreghdfe dln_mu (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & n_t>=4, absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob3_bal4

ivreghdfe dln_mu (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & n_t>=3, absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob3_bal3


*---------------------------------------
* 3.2 Exclude micro/top firms by size
*---------------------------------------

**** (1) Exclude micro firms (bottom decile by size-year)
bys year: egen p10_size = pctile(lnSize), p(10)
ivreghdfe dln_mu (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & lnSize > p10_size, absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob3_nomicro

**** (2) Exclude top 1% by size
bys year: egen p99_size = pctile(lnSize), p(99)
ivreghdfe dln_mu (change_IP = output_IV) Z_input $X_lag c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019) & lnSize<=p99_size, absorb(isic4) vce(cluster isic4) partial(i.year)
est store rob3_top1

* 3.3. Table

esttab rob3_bal8 rob3_bal7 rob3_bal6 rob3_bal5 rob3_bal4 rob3_bal3 rob3_nomicro rob3_top1 using "$OUTPUT_TABLES\rob3_composition.tex", ///
    replace se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(change_IP Z_input lleverage lliquidity llnsize l_age l_exporter) ///
    stats(N, labels("Observations")) ///
    title("The case of long-lived firms and exclusion of micro and top firms by size")

restore

*====================================
* 4. DISTRIBUTION DESIGN ROBUSTNESS
*====================================

*----------------------------
* 4.1. Deciles vs quintiles
*----------------------------
preserve
drop if missing(dln_mu, change_IP, output_IV, Z_input, ls_pre_filled, post2016, lleverage, l_exporter, l_age, lliquidity, llnsize)

bys isic4 year: egen n_jt = count(dln_mu)
bys isic4 year: egen lleverage_j  = mean(lleverage)
bys isic4 year: egen l_exporter_j = mean(l_exporter)
bys isic4 year: egen l_age_j      = mean(l_age)
bys isic4 year: egen lliquidity_j = mean(lliquidity)
bys isic4 year: egen llnsize_j    = mean(llnsize)

global X_lag_j "lleverage_j lliquidity_j llnsize_j l_age_j l_exporter_j"

// order-statistic bias controls
gen n2 = n_jt^2
gen n3 = n_jt^3
global n_poly "n_jt n2 n3"

**** (1) Deciles
forvalues p = 10(10)90 {
	bys isic4 year: egen qd`p' = pctile(dln_mu), p(`p') 
}
bys isic4 year: keep if _n==1
matrix results_dec = J(9,4,.)
matrix colnames results_dec = beta_IP se_IP N R2

local plist_dec "10 20 30 40 50 60 70 80 90"
local r = 1
foreach p of local plist_dec {
    ivreghdfe qd`p' (c.change_IP = c.output_IV) Z_input ///
        $n_poly $X_lag_j c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), ///
        absorb(isic4) vce(cluster isic4) partial(i.year)

    matrix results_dec[`r',1] = _b[change_IP]
    matrix results_dec[`r',2] = _se[change_IP]
    matrix results_dec[`r',3] = e(N)
    matrix results_dec[`r',4] = e(r2)

    eststo dec_`p'
    local r = `r' + 1
}
matrix rownames results_dec = `plist_dec'
matrix list results_dec, format(%9.3f)

restore

preserve
drop if missing(dln_mu, change_IP, output_IV, Z_input, ls_pre_filled, post2016, ///
                lleverage, l_exporter, l_age, lliquidity, llnsize)

bys isic4 year: egen n_jt = count(dln_mu)

bys isic4 year: egen lleverage_j  = mean(lleverage)
bys isic4 year: egen l_exporter_j = mean(l_exporter)
bys isic4 year: egen l_age_j      = mean(l_age)
bys isic4 year: egen lliquidity_j = mean(lliquidity)
bys isic4 year: egen llnsize_j    = mean(llnsize)

global X_lag_j "lleverage_j lliquidity_j llnsize_j l_age_j l_exporter_j"

gen n2 = n_jt^2
gen n3 = n_jt^3
global n_poly "n_jt n2 n3"

**** (2) Quintiles
forvalues p = 20(20)80 {
    bys isic4 year: egen qq`p' = pctile(dln_mu), p(`p')
}

bys isic4 year: keep if _n==1

matrix results_quin = J(4,4,.)
matrix colnames results_quin = beta_IP se_IP N R2

local plist_quin "20 40 60 80"
local r = 1
foreach p of local plist_quin {
    ivreghdfe qq`p' (c.change_IP = c.output_IV) Z_input ///
        $n_poly $X_lag_j c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), ///
        absorb(isic4) vce(cluster isic4) partial(i.year)

    matrix results_quin[`r',1] = _b[change_IP]
    matrix results_quin[`r',2] = _se[change_IP]
    matrix results_quin[`r',3] = e(N)
    matrix results_quin[`r',4] = e(r2)

    eststo quin_`p'
    local r = `r' + 1
}
matrix rownames results_quin = `plist_quin'
matrix list results_quin, format(%9.3f)

restore

*----------------------------------
* 4.2. Rank by markup level 
* - constructing within-sector-year bins based on lagged markups
* - then compute mean markup adjustment within each bin
*----------------------------------
preserve
xtset firm_id year

gen l_ln_mu = L.ln_mu
bysort isic4 year: egen n_jt = count(l_ln_mu)
bysort isic4 year (l_ln_mu): gen rnk = _n if !missing(l_ln_mu)
bysort isic4 year: gen Ncell = sum(!missing(l_ln_mu))
bysort isic4 year: replace Ncell = Ncell[_N]
gen rank_dec = ceil(10 * rnk / Ncell) if !missing(rnk)
replace rank_dec = 10 if rank_dec > 10

bys isic4 year: egen lleverage_j  = mean(lleverage)
bys isic4 year: egen l_exporter_j = mean(l_exporter)
bys isic4 year: egen l_age_j      = mean(l_age)
bys isic4 year: egen lliquidity_j = mean(lliquidity)
bys isic4 year: egen llnsize_j    = mean(llnsize)
global X_lag_j "lleverage_j lliquidity_j llnsize_j l_age_j l_exporter_j"
gen n2 = n_jt^2
gen n3 = n_jt^3
global n_poly "n_jt n2 n3"

// Collapse to sector-year*markup-decile cells
collapse (mean) mean_dln_mu = dln_mu (firstnm) change_IP output_IV Z_input n_jt n2 n3 lleverage_j l_exporter_j l_age_j lliquidity_j llnsize_j ls_pre_filled post2016, by(isic4 year rank_dec)

matrix results_rank = J(10,4,.)
matrix colnames results_rank = beta_IP se_IP N R2

forvalues d = 1/10 {
    ivreghdfe mean_dln_mu (c.change_IP = c.output_IV) Z_input ///
        $n_poly $X_lag_j c.ls_pre_filled##i.post2016 i.year ///
        if rank_dec == `d' & inrange(year, 2011, 2019), ///
        absorb(isic4) vce(cluster isic4) partial(i.year)

    matrix results_rank[`d',1] = _b[change_IP]
    matrix results_rank[`d',2] = _se[change_IP]
    matrix results_rank[`d',3] = e(N)
    matrix results_rank[`d',4] = e(r2)

    eststo rank_`d'
}

matrix rownames results_rank = d1 d2 d3 d4 d5 d6 d7 d8 d9 d10
matrix list results_rank, format(%9.3f)

restore

*------------------------------------------------
* 4.3. Exclude sector-year cells with few firms
* - run the GIVQ design after excluding thin cells
* - cutoffs: n_jt >= 10 and n_jt >= 20
*------------------------------------------------

**** (1) n_jt >= 10
preserve
drop if missing(dln_mu, change_IP, output_IV, Z_input, ls_pre_filled, post2016, lleverage, l_exporter, l_age, lliquidity, llnsize)
bys isic4 year: egen n_jt = count(dln_mu)
keep if n_jt >= 10
bys isic4 year: egen lleverage_j  = mean(lleverage)
bys isic4 year: egen l_exporter_j = mean(l_exporter)
bys isic4 year: egen l_age_j      = mean(l_age)
bys isic4 year: egen lliquidity_j = mean(lliquidity)
bys isic4 year: egen llnsize_j    = mean(llnsize)
global X_lag_j "lleverage_j lliquidity_j llnsize_j l_age_j l_exporter_j"
gen n2 = n_jt^2
gen n3 = n_jt^3
global n_poly "n_jt n2 n3"
forvalues p = 10(10)90 {
    bys isic4 year: egen q10_`p' = pctile(dln_mu), p(`p')
}

bys isic4 year: keep if _n==1

matrix results_n10 = J(9,4,.)
matrix colnames results_n10 = beta_IP se_IP N R2

local plist "10 20 30 40 50 60 70 80 90"
local r = 1
foreach p of local plist {
    ivreghdfe q10_`p' (c.change_IP = c.output_IV) Z_input $n_poly $X_lag_j c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)

    matrix results_n10[`r',1] = _b[change_IP]
    matrix results_n10[`r',2] = _se[change_IP]
    matrix results_n10[`r',3] = e(N)
    matrix results_n10[`r',4] = e(r2)

    eststo n10_`p'
    local r = `r' + 1
}
matrix rownames results_n10 = `plist'
matrix list results_n10, format(%9.3f)

restore

**** (2) n_jt >= 20
preserve
keep if inrange(year, 2011, 2019)
drop if missing(dln_mu, change_IP, output_IV, Z_input, ls_pre_filled, post2016, lleverage, l_exporter, l_age, lliquidity, llnsize)

bys isic4 year: egen n_jt = count(dln_mu)
keep if n_jt >= 20

bys isic4 year: egen lleverage_j  = mean(lleverage)
bys isic4 year: egen l_exporter_j = mean(l_exporter)
bys isic4 year: egen l_age_j      = mean(l_age)
bys isic4 year: egen lliquidity_j = mean(lliquidity)
bys isic4 year: egen llnsize_j    = mean(llnsize)

global X_lag_j "lleverage_j lliquidity_j llnsize_j l_age_j l_exporter_j"

gen n2 = n_jt^2
gen n3 = n_jt^3
global n_poly "n_jt n2 n3"

forvalues p = 10(10)90 {
    bys isic4 year: egen q20_`p' = pctile(dln_mu), p(`p')
}

bys isic4 year: keep if _n==1

matrix results_n20 = J(9,4,.)
matrix colnames results_n20 = beta_IP se_IP N R2

local plist "10 20 30 40 50 60 70 80 90"
local r = 1
foreach p of local plist {
    ivreghdfe q20_`p' (c.change_IP = c.output_IV) Z_input $n_poly $X_lag_j c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)

    matrix results_n20[`r',1] = _b[change_IP]
    matrix results_n20[`r',2] = _se[change_IP]
    matrix results_n20[`r',3] = e(N)
    matrix results_n20[`r',4] = e(r2)

    eststo n20_`p'
    local r = `r' + 1
}
matrix rownames results_n20 = `plist'
matrix list results_n20, format(%9.3f)

restore

*--------------
* 4.4. Graphs
*--------------

**** 4.1. Combine both line graphs 
tempfile dec quin

preserve
clear
matrix M = results_dec
svmat double M, names(col)
gen pct = .
local i = 1
foreach p in 10 20 30 40 50 60 70 80 90 {
    replace pct = `p' in `i'
    local ++i
}
gen ub = beta_IP + 1.96*se_IP
gen lb = beta_IP - 1.96*se_IP
gen spec = "Deciles"
save `dec', replace
restore

preserve
clear
matrix M = results_quin
svmat double M, names(col)
gen pct = .
local i = 1
foreach p in 20 40 60 80 {
    replace pct = `p' in `i'
    local ++i
}
gen ub = beta_IP + 1.96*se_IP
gen lb = beta_IP - 1.96*se_IP
gen spec = "Quintiles"
save `quin', replace
restore

use `dec', clear
append using `quin'

twoway ///
    (rcap ub lb pct if spec=="Deciles", lwidth(vthin)) ///
    (line beta_IP pct if spec=="Deciles", lwidth(medium)) ///
    (scatter beta_IP pct if spec=="Deciles", msize(small)) ///
    (rcap ub lb pct if spec=="Quintiles", lwidth(vthin)) ///
    (line beta_IP pct if spec=="Quintiles", lpattern(dash) lwidth(medium)) ///
    (scatter beta_IP pct if spec=="Quintiles", msymbol(D) msize(small)), ///
    yline(0, lpattern(dash)) ///
    xtitle("Quantile / grouped rank") ///
    ytitle("Coefficient on import penetration") ///
    xlabel(10(10)90) ///
    title("Distributional design robustness: deciles vs quintiles") ///
    legend(order(2 "Deciles" 5 "Quintiles") rows(1)) ///
    graphregion(color(white))

graph export "$OUTPUT_FIGURES\rob41_decquin.png", replace width(2200)

**** 4.2. Decile of lagged markups
preserve
clear

matrix M = results_rank
svmat double M, names(col)

gen dec = _n
gen ub = beta_IP + 1.96*se_IP
gen lb = beta_IP - 1.96*se_IP

twoway ///
    (rcap ub lb dec, lwidth(medthin)) ///
    (line beta_IP dec, lwidth(medium)) ///
    (scatter beta_IP dec, msize(medsmall)), ///
    yline(0, lpattern(dash)) ///
    xtitle("Decile of lagged markup level within sector-year") ///
    ytitle("Coefficient on import penetration") ///
    xlabel(1(1)10) ///
    title("Rank by markup level: robustness") ///
    legend(off) ///
    graphregion(color(white))

graph export "$OUTPUT_FIGURES\rob42_rank.png", replace width(2000)
restore

**** 4.3. Thin-cell robustness
tempfile n10 n20

preserve
clear
matrix M = results_n10
svmat double M, names(col)
gen pct = .
local i = 1
foreach p in 10 20 30 40 50 60 70 80 90 {
    replace pct = `p' in `i'
    local ++i
}
gen ub = beta_IP + 1.96*se_IP
gen lb = beta_IP - 1.96*se_IP
gen spec = "n>=10"
save `n10', replace
restore

preserve
clear
matrix M = results_n20
svmat double M, names(col)
gen pct = .
local i = 1
foreach p in 10 20 30 40 50 60 70 80 90 {
    replace pct = `p' in `i'
    local ++i
}
gen ub = beta_IP + 1.96*se_IP
gen lb = beta_IP - 1.96*se_IP
gen spec = "n>=20"
save `n20', replace
restore

use `n10', clear
append using `n20'

twoway ///
    (rcap ub lb pct if spec=="n>=10", lwidth(vthin)) ///
    (line beta_IP pct if spec=="n>=10", lwidth(medium)) ///
    (scatter beta_IP pct if spec=="n>=10", msize(small)) ///
    (rcap ub lb pct if spec=="n>=20", lwidth(vthin)) ///
    (line beta_IP pct if spec=="n>=20", lpattern(dash) lwidth(medium)) ///
    (scatter beta_IP pct if spec=="n>=20", msymbol(D) msize(small)), ///
    yline(0, lpattern(dash)) ///
    xtitle("Within-sector-year quantile of markup adjustment") ///
    ytitle("Coefficient on import penetration") ///
    xlabel(10(10)90) ///
    title("Distributional robustness: excluding thin cells") ///
    legend(order(2 "n>=10" 5 "n>=20") rows(1)) ///
    graphregion(color(white))

graph export "$OUTPUT_FIGURES\rob43_thin.png", replace width(2200)

log close














 














