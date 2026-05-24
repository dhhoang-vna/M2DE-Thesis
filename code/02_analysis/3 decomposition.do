capture confirm global REPLICATION_ROOT
if _rc {
    do "code/00_setup/config.do"
}
else if "${REPLICATION_ROOT}" == "" {
    do "code/00_setup/config.do"
}
clear mata
capture log close
clear

log using "$LOGS\1 baseline_regressions", replace

global folder "$REPLICATION_ROOT"

use "$DATA_DERIVED\data_ready.dta", clear

drop if missing(isic4, year, firm_id)
drop if missing(share_sales, mu)
drop if mu<=0
drop if share_sales<0
drop _merge

merge m:1 isic4 year using "$DATA_DERIVED\UNIDO\apparent_consumption.dta"


*--------------------------------------
* 1. SECTOR MARKUP VIA HARMONIC MEAN
*--------------------------------------

isid firm_id year
xtset firm_id year

gen double inv_mu = 1/mu

bys isic4 year: egen double inv_mu_j = total(share_sales * inv_mu)

gen double mu_j = 1/inv_mu_j
gen double ln_mu_j = ln(mu_j)

// Sector-level changes (will be duplicated, need collapse?)

preserve
keep isic4 year inv_mu_j mu_j ln_mu_j
bys isic4 year: keep if _n==1

collapse(mean) inv_mu_j mu_j ln_mu_j, by(isic4 year)
tsset isic4 year
gen double d_inv_mu_j = D.inv_mu_j
gen double d_ln_mu_j  = D.ln_mu_j

tempfile sector_series
save `sector_series', replace
restore

merge m:1 isic4 year using `sector_series', nogen

gen obs_order = _n

sort isic4 year obs_order

foreach var in d_inv_mu_j d_ln_mu_j {
    gen `var'_filled = .

    by isic4 year (obs_order): replace `var'_filled = `var' if _n == 1
    by isic4 year (obs_order): replace `var'_filled = `var' if `var' != 0 & !missing(`var')
    by isic4 year (obs_order): replace `var'_filled = `var'_filled[_n-1] if missing(`var'_filled) | `var'_filled == 0
} 

foreach var in d_inv_mu_j d_ln_mu_j {
    replace `var' = `var'_filled
    drop `var'_filled
}

drop obs_order

*--------------------------------------------------
* 2. DECOMPOSITION OF SECTOR INVERSE-MARKUP CHANGE
*--------------------------------------------------

// lags
bys firm_id (year): gen double l_share = share_sales[_n-1]
bys firm_id (year): gen double l_inv_mu = inv_mu[_n-1]

// changes
gen double d_share = share_sales - l_share
gen double d_inv_mu = inv_mu - l_inv_mu

// midpoints
gen double s_bar = 0.5*(share_sales + l_share)
gen double inv_mu_bar = 0.5*(inv_mu + l_inv_mu)

// firm-level contributions 

gen double contrib_within = s_bar*d_inv_mu //within-firm markup adjustment
gen double contrib_between = inv_mu_bar*d_share //reallocation via share shifts

// aggregate contributions to sector-year
bys isic4 year: egen double within_inv_mu = total(contrib_within)
bys isic4 year: egen double between_inv_mu = total(contrib_between)

// checkpoint: within + between = d_ln_mu_j ?!
gen double decomp_gap = d_inv_mu_j - (within_inv_mu + between_inv_mu)

summ decomp_gap, detail //most are small, some extreme values are quite large

* Check % of large decomp_gap observations
gen abs_gap = abs(decomp_gap)
sum abs_gap, detail

* Flag large gap (e.g. abs > 0.5)
gen large_gap = abs_gap > 0.5

* Check how many of these are large
tab large_gap
tab large_gap exit //most not due to exit

cap which winsor2
if _rc ssc install winsor2

clonevar within_inv_mu_raw  = within_inv_mu
clonevar between_inv_mu_raw = between_inv_mu

winsor2 within_inv_mu,  cuts(1 99) replace
winsor2 between_inv_mu, cuts(1 99) replace


// shares of total sector inverse-markup change 
gen double within_share_of_dinv = within_inv_mu / d_inv_mu_j if d_inv_mu_j!=0
gen double between_share_of_dinv = between_inv_mu / d_inv_mu_j if d_inv_mu_j!=0





**** Toy regressions ****

preserve
collapse (mean) d_ln_mu_j change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

ivreghdfe d_ln_mu_j (change_IP = output_IV) Z_input c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(i.isic4##c.year) vce(cluster isic4) //negative (-0.8267), insignificant, but input supply = -5.914 (1%)

restore

*********

preserve
bys isic4 year: gen n_firms = _N
bys isic4 year: egen dom_j = total(dom_sales)

collapse (mean) d_inv_mu_j within_inv_mu between_inv_mu Z_input ls_pre_filled post2016 ///
        HHI_dom ppi apparent_consumption ///
        (first) change_IP output_IV n_firms dom_j, by(isic4 year)

isid isic4 year
tsset isic4 year

gen ldom_j   = L.dom_j
gen ln_ppi   = ln(ppi)
gen lln_ppi  = L.ln_ppi
gen dln_ppi  = D.ln_ppi
gen dHHI     = D.HHI_dom
gen ln_abs   = ln(apparent_consumption)
gen dln_abs  = D.ln_abs

*--- run and store the two IV regressions
eststo clear

eststo total: ///
    ivreghdfe d_inv_mu_j ///
        (change_IP = output_IV) ///
        Z_input c.ls_pre_filled##i.post2016 i.year ///
        if inrange(year, 2011, 2019), ///
        absorb(isic4) vce(cluster isic4) partial(i.year)

eststo within: ///
    ivreghdfe within_inv_mu ///
        (change_IP = output_IV) ///
        Z_input c.ls_pre_filled##i.post2016 i.year ///
        if inrange(year, 2011, 2019), ///
        absorb(isic4) vce(cluster isic4) partial(i.year)

eststo between: ///
    ivreghdfe between_inv_mu ///
        (change_IP = output_IV) ///
        Z_input c.ls_pre_filled##i.post2016 i.year ///
        if inrange(year, 2011, 2019), ///
        absorb(isic4) vce(cluster isic4) partial(i.year)

*--- export LaTeX table
esttab within between using "$OUTPUT_TABLES\decomposition.tex", ///
    replace ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Within inv." "Between inv." "Total") ///
    label booktabs ///
    alignment(D{.}{.}{-1}) ///
    fragment nogaps compress

restore

//Z_input coef = -0.8 to -0.93 negative (5%), output positive but not significant

* Bootstrap
local y within_inv_mu
local x change_IP
local z output_IV
local w Z_input c.ls_pre_filled##i.post2016
local fe isic4 year

reghdfe `y' `w', absorb(`fe') resid(y_mu) vce(cluster isic4)
reghdfe `x' `w', absorb(`fe') resid(x_mu) vce(cluster isic4)
reghdfe `z' `w', absorb(`fe') resid(z_mu) vce(cluster isic4)

ivreg2 y_mu (x_mu = z_mu), nocons cluster(isic4) first
eststo iv_resid

* Wild bootstrap p-value (just store p)
boottest x_mu, cluster(isic4) reps(9999) seed(12345)
eststo iv_resid
estadd scalar p_wild = r(p)  // 

restore

**********


ivreghdfe within_inv_mu (change_IP = output_IV) Z_input L.HHI_dom c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) partial(i.year)



****
summ within_share_of_dinv between_share_of_dinv if inrange(year,2011,2019), detail

drop if abs(d_inv_mu_j) < 0.01


preserve
collapse (mean) within_share_of_dinv between_share_of_dinv change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year
summ within_share_of_dinv between_share_of_dinv if inrange(year, 2011, 2019), detail

restore



/********************************************************************
  Decomposition of sector inverse-markup change (Burstein-style)
  + coherent share construction
  Key fixes:
   (i) compute sector-year totals W_jt, R_jt, and D_jt from the SAME objects
   (ii) form shares from RAW totals (do NOT winsorize W and R separately)
   (iii) trim on near-zero denominators before computing shares
   (iv) optional: winsorize shares (not components) for presentation
********************************************************************/

*----------------------------
* 0) Setup: panel ordering
*----------------------------
sort firm_id year

*----------------------------
* 1) Lags (firm-level)
*----------------------------
bys firm_id (year): gen double l_share  = share_sales[_n-1]
bys firm_id (year): gen double l_inv_mu = inv_mu[_n-1]

* keep only observations with valid lag (optional but recommended)
* drop if missing(l_share) | missing(l_inv_mu)

*----------------------------
* 2) Firm-level changes and midpoints
*----------------------------
gen double d_share    = share_sales - l_share
gen double d_inv_mu   = inv_mu      - l_inv_mu

gen double s_bar      = 0.5*(share_sales + l_share)
gen double inv_mu_bar = 0.5*(inv_mu + l_inv_mu)

*----------------------------
* 3) Firm-level contributions
*----------------------------
gen double contrib_within  = s_bar      * d_inv_mu      // within-firm
gen double contrib_between = inv_mu_bar * d_share       // reallocation

*----------------------------
* 4) Aggregate to sector-year totals (RAW, no winsorization yet)
*    W_jt and R_jt are sums across firms within (isic4,year)
*----------------------------
bys isic4 year: egen double within_inv_mu_raw  = total(contrib_within)
bys isic4 year: egen double between_inv_mu_raw = total(contrib_between)

*----------------------------
* 5) Construct the sector-year total change D_jt CONSISTENTLY
*    IMPORTANT: do NOT rely on a precomputed d_inv_mu_j unless you are
*    100% sure it equals Î”(mu^{-1}_{jt}) computed from the same aggregation.
*
*    Here we compute sector inverse markup as a (market-share) weighted mean:
*       inv_mu_jt = Î£_i s_it * inv_mu_it
*    and then take the change across t.
*----------------------------

* sector inverse markup level (weighted mean) each sector-year
bys isic4 year: egen double inv_mu_jt = total(share_sales * inv_mu)

* lag of sector inverse markup level
bys isic4 (year): gen double l_inv_mu_jt = inv_mu_jt[_n-1]

* sector-year total change (consistent denominator)
gen double d_inv_mu_jt = inv_mu_jt - l_inv_mu_jt

*----------------------------
* 6) Check decomposition gap (RAW)
*    W_jt + R_jt should approximate D_jt (midpoint method)
*----------------------------
gen double decomp_gap_raw = d_inv_mu_jt - (within_inv_mu_raw + between_inv_mu_raw)

* If you want to inspect:
* summ decomp_gap_raw if inrange(year,2011,2019), detail

*----------------------------
* 7) Trim: drop near-zero denominators BEFORE shares
*    This prevents mechanical explosions in shares.
*----------------------------
gen double abs_dinv = abs(d_inv_mu_jt)

* Choose threshold; 0.01 is your earlier choice. Keep it consistent.
drop if missing(d_inv_mu_jt) | abs_dinv < 0.01

* Optionally also trim very large gaps (rare pathologies)
* drop if abs(decomp_gap_raw) > 0.5

*----------------------------
* 8) Shares from RAW totals (coherent)
*----------------------------
gen double within_share_raw  = within_inv_mu_raw  / d_inv_mu_jt
gen double between_share_raw = between_inv_mu_raw / d_inv_mu_jt

* Observation-level identity check (should be close to 1 when gap is small)
gen double share_sum_raw = within_share_raw + between_share_raw
* summ share_sum_raw if inrange(year,2011,2019), detail

*----------------------------
* 9) OPTIONAL: winsorize SHARES (not components) for reporting
*    This keeps the economics (ratios) interpretable while handling tails.
*----------------------------
cap which winsor2
if _rc ssc install winsor2

clonevar within_share = within_share_raw
clonevar between_share = between_share_raw

winsor2 within_share between_share, cuts(1 99) replace

*----------------------------
* 10) Collapse to sector-year dataset for summaries / regressions
*     Use RAW totals if you will re-run IVs on W and R.
*     Use winsorized shares only for descriptive dominance tables/figures.
*----------------------------
preserve
collapse (mean) within_share between_share ///
        (mean) within_share_raw between_share_raw ///
        (mean) decomp_gap_raw ///
        (firstnm) change_IP output_IV Z_input ls_pre_filled post2016 ///
        (mean) within_inv_mu_raw between_inv_mu_raw d_inv_mu_jt ///
        , by(isic4 year)

isid isic4 year
tsset isic4 year

* Descriptive dominance (2011-2019)
summ within_share between_share if inrange(year,2011,2019), detail

* Frequency "majority dominance"
gen dom_within  = within_share  > 0.5
gen dom_between = between_share > 0.5
summ dom_within dom_between if inrange(year,2011,2019)

* Sanity check: shares computed from RAW should sum near 1 on average
gen share_sum_check = within_share_raw + between_share_raw
summ share_sum_check if inrange(year,2011,2019), detail

restore

* Graph
preserve
collapse (mean) within_share between_share, by(year)

twoway ///
 (line within_share year, lwidth(medthick)) ///
 (line between_share year, lpattern(dash)), ///
 legend(order(1 "Within-firm" 2 "Reallocation")) ///
 ytitle("Share of sector markup change") ///
 xtitle("Year")

restore

* Sector heterogeneity
preserve
collapse (mean) within_share between_share, by(isic4)

summarize within_share between_share, detail

restore














preserve
collapse (mean) within_inv_mu HHI_dom age curr_ratio leverage lnSize interest_cover_x_ change_IP output_IV Z_input ls_pre_filled post2016 [aw=dom_sales], by(isic4 year)

isid isic4 year
tsset isic4 year

ivreg2 within_inv_mu (change_IP = output_IV) Z_input c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019) // positive, insignificant

restore


preserve
collapse (mean) within_inv_mu d_inv_mu HHI_dom age curr_ratio leverage lnSize interest_cover_x_ change_IP output_IV Z_input ls_pre_filled post2016 [aw=dom_sales], by(isic4 year)

isid isic4 year
tsset isic4 year

ivreg2 within_inv_mu (change_IP = output_IV) Z_input c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019) // positive, insignificant

restore



summ within_inv_mu between_inv_mu, detail

preserve
collapse (mean) between_inv_mu HHI_dom age curr_ratio leverage lnSize interest_cover_x_ change_IP output_IV Z_input ls_pre_filled post2016 [aw=dom_sales], by(isic4 year)

isid isic4 year
tsset isic4 year

ivreghdfe between_inv_mu (change_IP = output_IV) Z_input c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(i.isic4##c.year) vce(cluster isic4) first // insignificant, but coef = -1.074
restore


preserve
collapse (mean) inv_mu d_inv_mu HHI_dom age curr_ratio leverage lnSize interest_cover_x_ change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

gen d_HHI = HHI_dom - L.HHI_dom

reg inv_mu HHI_dom if inrange(year, 2011, 2019)

restore


// baseline cyclicality

preserve
collapse (mean) dln_mu VA_cost l_share age curr_ratio leverage lnSize interest_cover_x_ change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

gen ln_VA = log(VA_cost) if VA_cost>0
gen d_VA = ln_VA - L.ln_VA

reghdfe dln_mu c.d_VA##c.L.lnSize d_VA c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(i.isic4##c.year) vce(cluster isic4) // insignificant

restore

// import competition and cyclicality

preserve
collapse (mean) d_inv_mu_j HHI_dom dln_mu VA_cost l_share age curr_ratio leverage lnSize interest_cover_x_ change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

gen ln_VA = log(VA_cost) if VA_cost>0
gen d_VA = ln_VA - L.ln_VA

isid firm_id year
tsset firm_id year 

ivreg2 dln_mu (c.d_VA##c.change_IP = c.d_VA##c.output_IV) Z_input d_VA c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019) // insignificant

reg dln_mu c.d_VA##c.HHI_dom d_VA c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019) //-0.056, 5%; interaction: 0.15, 5%

restore



* 3. 

// full sample
use "$DATA_DERIVED\data_ready.dta", clear
drop if missing(isic4, year, firm_id)
drop if missing(share_sales, mu)
drop if mu<=0
drop if share_sales<0

gen double inv_mu = 1/mu

bys isic4 year: egen double inv_mu_j = total(share_sales * inv_mu)

gen double mu_j = 1/inv_mu_j
gen double ln_mu_j = ln(mu_j)

// Sector-level changes (will be duplicated, need collapse?)

preserve
keep isic4 year inv_mu_j mu_j ln_mu_j
bys isic4 year: keep if _n==1

collapse(mean) inv_mu_j mu_j ln_mu_j, by(isic4 year)
tsset isic4 year
gen double d_inv_mu_j = D.inv_mu_j
gen double d_ln_mu_j  = D.ln_mu_j

tempfile sector_series
save `sector_series', replace
restore

merge m:1 isic4 year using `sector_series', nogen

gen obs_order = _n

sort isic4 year obs_order

foreach var in d_inv_mu_j d_ln_mu_j {
    gen `var'_filled = .

    by isic4 year (obs_order): replace `var'_filled = `var' if _n == 1
    by isic4 year (obs_order): replace `var'_filled = `var' if `var' != 0 & !missing(`var')
    by isic4 year (obs_order): replace `var'_filled = `var'_filled[_n-1] if missing(`var'_filled) | `var'_filled == 0
} 

foreach var in d_inv_mu_j d_ln_mu_j {
    replace `var' = `var'_filled
    drop `var'_filled
}

drop obs_order

// balanced sample - keep only firms observed in both t and t-1

xtset firm_id year

* keep only firm-years with lag observed
gen byte has_lag = !missing(L.mu) & !missing(L.share_sales)
keep if has_lag & !missing(mu, share_sales)

* recompute shares within sector-year on the balanced sample
bys isic4 year: egen double shsum_b = total(share_sales)
gen double share_b = share_sales/shsum_b
drop shsum_b

* lagged balanced shares
bys firm_id (year): gen double L_share_b = share_b[_n-1]
gen double inv_mu_b = 1/mu
bys firm_id (year): gen double L_inv_mu_b = inv_mu_b[_n-1]

* changes and midpoints
gen double d_share_b = share_b - L.share_b 
gen double d_inv_mu_b = inv_mu_b - L_inv_mu_b
gen double s_bar_b = 0.5*(share_b + L_share_b)
gen double inv_mu_bar_b = 0.5*(inv_mu_b + L_inv_mu_b)

* firm contributions 
gen double contrib_within_b = s_bar_b*d_inv_mu_b
gen double contrib_between_b = inv_mu_bar_b*d_share_b

* full sample
preserve
keep isic4 year inv_mu_j
collapse (first) inv_mu_j, by(isic4 year)
tsset isic4 year
gen double d_inv_mu_full = D.inv_mu_j
tempfile full
save `full', replace
restore

* collapse to sector-year components
preserve 
keep isic4 year contrib_within_b contrib_between_b share_b inv_mu_b
gen inv_b = share_b*inv_mu_b
collapse (sum) within_b=contrib_within_b between_b=contrib_between_b (sum) inv_mu_j_b = inv_b, by(isic4 year)

* sector change implied by balanced sample
tsset isic4 year
gen double d_inv_mu_bal = D.inv_mu_j_b

* decomposition check 
gen double gap_bal = d_inv_mu_bal - (within_b + between_b)

tempfile bal 
save `bal', replace
restore

use `full', clear
merge 1:1 isic4 year using `bal', nogen

save "$DATA_DERIVED\balanced_sample.dta", replace

use "$DATA_DERIVED\data_ready.dta", clear
drop _merge
isid isic4 year
isid firm_id year
xtset firm_id year
merge m:1 isic4 year using "$DATA_DERIVED\balanced_sample.dta"





corr d_inv_mu_full d_inv_mu_bal
summ d_inv_mu_full d_inv_mu_bal gap_bal


//within and between
preserve
collapse (mean) within_b HHI_dom age curr_ratio leverage lnSize interest_cover_x_ change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

ivreghdfe within_b (change_IP = output_IV) Z_input age curr_ratio leverage lnSize c.ls_pre_filled##i.post2016 if inrange(year, 2011, 2019), absorb(isic4 year) vce(cluster isic4) first // positive, insignificant

restore


preserve
collapse (mean) between_b HHI_dom age curr_ratio leverage lnSize interest_cover_x_ change_IP output_IV Z_input ls_pre_filled post2016, by(isic4 year)

isid isic4 year
tsset isic4 year

ivreghdfe between_b (change_IP = output_IV) Z_input age curr_ratio leverage lnSize c.ls_pre_filled##i.post2016 i.year if inrange(year, 2011, 2019), absorb(isic4) vce(cluster isic4) // 

gen post2017 = year>=2017
gen double changeIP_post2017 = change_IP * post2017
gen double outputIV_post2017 = output_IV * post2017

ivreghdfe between_b (change_IP changeIP_post2017 = output_IV outputIV_post2017) c.ls_pre_filled##i.post2016 i.year if inrange(year,2011,2019), absorb(isic4) vce(cluster isic4)

restore


//sector markup
preserve

* 1) collapse to sector-year means
collapse (mean) d_inv_mu_j HHI_dom age curr_ratio leverage ///
    operating_revenue_turnover_ interest_cover_x_ change_IP output_IV Z_input ///
    ls_pre_filled post2016 lnSize, by(isic4 year)

isid isic4 year
keep if inrange(year, 2011, 2019)

* Save collapsed panel temporarily
tempfile panel
save `panel', replace

* 2) Build top5 list (one row per sector) from the collapsed data
keep isic4 operating_revenue_turnover_
bys isic4: egen avg_turnover = mean(operating_revenue_turnover_)
bys isic4: keep if _n==1

gsort -avg_turnover
gen top5 = (_n <= 5)

keep isic4 top5
tempfile top5
save `top5', replace

* 3) Reload panel and merge top5 flag
use `panel', clear
merge m:1 isic4 using `top5', nogen keep(master match)

* 4) Run IV on top 5 sectors
ivreghdfe d_inv_mu_j (change_IP = output_IV) ///
    Z_input age curr_ratio leverage lnSize c.ls_pre_filled##i.post2016 i.year ///
    if top5==1, absorb(isic4) vce(cluster isic4)

restore




gen post2017 = year>=2017
gen double changeIP_post2017 = change_IP * post2017
gen double outputIV_post2017 = output_IV * post2017


tab isic4  




keep if isic4 == 2220 | isic4 == 1410 | isic4 == 2599 | isic4 = 1312 | isic4 == 2930

log close

