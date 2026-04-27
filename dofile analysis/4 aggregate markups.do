clear mata
capture log close
clear

log using "D:\1. M2 Development Economics\0. Thesis\Thesis\Logs\3 decomposition (3)", replace

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"

use "$folder\Data\data_ready.dta", clear

drop _merge

merge m:1 isic4 year using "$folder\Data\UNIDO\apparent_consumption.dta"

drop if missing(isic4, year, firm_id)
drop if missing(mu, dom_sales)
drop if mu <= 0
drop if dom_sales < 0

*============================================================*
* 0. CONSISTENT SHARES AND MARKUPS ON THE ESTIMATION SAMPLE
*============================================================*

isid firm_id year
xtset firm_id year

gen double inv_mu = 1/mu

* Rebuild domestic-sales totals on the surviving sample
bys isic4 year: egen double dom_j = total(dom_sales)
bys year:       egen double dom_total = total(dom_sales)

* Rebuild within-sector and economy-wide shares on the surviving sample
gen double share_sales_est = dom_sales / dom_j     if dom_j > 0
gen double s_agg           = dom_sales / dom_total if dom_total > 0

* Diagnostics: sector shares should sum to 1
bys isic4 year: egen double share_sum_est = total(share_sales_est)
summarize share_sum_est, detail

* Sector harmonic markup
bys isic4 year: egen double inv_mu_j = total(share_sales_est * inv_mu)
gen double mu_j    = 1 / inv_mu_j
gen double ln_mu_j = ln(mu_j)

preserve
    keep isic4 year inv_mu_j mu_j ln_mu_j dom_j
    bys isic4 year: keep if _n == 1

    isid isic4 year
    tsset isic4 year

    gen double d_inv_mu_j = D.inv_mu_j
    gen double d_ln_mu_j  = D.ln_mu_j

    tempfile sector_series
    save `sector_series', replace
restore

merge m:1 isic4 year using `sector_series', nogen

*============================================================*
* A. AGGREGATE MARKUP SERIES: BOTTOM-UP vs DLEU-STYLE
*============================================================*

* Direct firm-level Bottom-Up harmonic aggregate
bys year: egen double inv_mu_agg_BU_firm = total(s_agg * inv_mu)
gen double mu_agg_BU_firm    = 1 / inv_mu_agg_BU_firm
gen double ln_mu_agg_BU_firm = ln(mu_agg_BU_firm)

* DLEU-style arithmetic aggregate
bys year: egen double mu_agg_DLEU = total(s_agg * mu)
gen double ln_mu_agg_DLEU = ln(mu_agg_DLEU)

preserve
    keep year dom_total ///
         inv_mu_agg_BU_firm mu_agg_BU_firm ln_mu_agg_BU_firm ///
         mu_agg_DLEU ln_mu_agg_DLEU
    bys year: keep if _n == 1

    isid year
    tsset year

    gen double d_inv_mu_agg_BU  = D.inv_mu_agg_BU_firm
    gen double d_ln_mu_agg_BU   = D.ln_mu_agg_BU_firm
    gen double d_mu_agg_DLEU    = D.mu_agg_DLEU
    gen double d_ln_mu_agg_DLEU = D.ln_mu_agg_DLEU

    gen double gap_level_BU_DLEU = mu_agg_BU_firm - mu_agg_DLEU
    gen double gap_log_BU_DLEU   = ln_mu_agg_BU_firm - ln_mu_agg_DLEU

    tempfile agg_markup_series
    save `agg_markup_series', replace
restore

* Sector-rebuilt Bottom-Up aggregate: should match the firm-level one
preserve
    keep isic4 year mu_j dom_j
    bys isic4 year: keep if _n == 1

    bys year: egen double dom_total_j = total(dom_j)
    gen double s_j_agg = dom_j / dom_total_j if dom_total_j > 0

    gen double inv_mu_j_check = 1 / mu_j
    bys year: egen double inv_mu_agg_BU_sector = total(s_j_agg * inv_mu_j_check)

    gen double mu_agg_BU_sector    = 1 / inv_mu_agg_BU_sector
    gen double ln_mu_agg_BU_sector = ln(mu_agg_BU_sector)

    keep year inv_mu_agg_BU_sector mu_agg_BU_sector ln_mu_agg_BU_sector
    bys year: keep if _n == 1

    tempfile agg_from_sectors
    save `agg_from_sectors', replace
restore

preserve
    use `agg_markup_series', clear
    merge 1:1 year using `agg_from_sectors', nogen

    gen double check_BU_level = mu_agg_BU_firm - mu_agg_BU_sector
    gen double check_BU_log   = ln_mu_agg_BU_firm - ln_mu_agg_BU_sector

    summarize check_BU_level check_BU_log, detail

    export delimited using "$folder\Tables\aggregate_markup_series.csv", replace
restore

*============================================================*
* 1. FOUR-TERM DECOMPOSITION
*============================================================*

sort firm_id year

* Lags
by firm_id (year): gen double l_share  = share_sales_est[_n-1]
by firm_id (year): gen double l_inv_mu = inv_mu[_n-1]
by firm_id (year): gen int    l_year   = year[_n-1]
by firm_id (year): gen        l_isic4  = isic4[_n-1]

* Leads
by firm_id (year): gen int f_year  = year[_n+1]
by firm_id (year): gen     f_isic4 = isic4[_n+1]

* Sample endpoints
quietly summarize year, meanonly
local minyear = r(min)
local maxyear = r(max)

*-------------------------------*
* 1A. Continue / enter / exit
*-------------------------------*

gen byte continuer = (l_year == year-1) & (l_isic4 == isic4)

gen byte entrant = (year > `minyear') & !continuer
replace entrant = 0 if missing(year) | missing(isic4) | missing(share_sales_est) | missing(inv_mu)

gen byte exiter_next = 0
replace exiter_next = 1 if !missing(year, isic4, share_sales_est, inv_mu) ///
    & (missing(f_year) | f_year != year + 1 | f_isic4 != isic4)

replace exiter_next = 0 if year == `maxyear'

*-------------------------------*
* 1B. Firm-level contributions
*-------------------------------*

gen double d_share    = share_sales_est - l_share if continuer
gen double d_inv_mu   = inv_mu - l_inv_mu if continuer
gen double s_bar      = 0.5*(share_sales_est + l_share) if continuer
gen double inv_mu_bar = 0.5*(inv_mu + l_inv_mu) if continuer

gen double contrib_within  = s_bar      * d_inv_mu if continuer
gen double contrib_between = inv_mu_bar * d_share  if continuer

gen double contrib_entry = share_sales_est * inv_mu if entrant

gen double contrib_exit_tmp = share_sales_est * inv_mu if exiter_next
gen int    year_exit        = year + 1 if exiter_next

*-------------------------------*
* 1C. Collapse exit term separately
*-------------------------------*
preserve
    keep if exiter_next
    keep isic4 year_exit contrib_exit_tmp
    collapse (sum) exit_inv_mu = contrib_exit_tmp, by(isic4 year_exit)
    rename year_exit year
    tempfile exitterm
    save `exitterm', replace
restore

*-------------------------------*
* 1D. Collapse all decomposition terms to sector-year
*-------------------------------*
bys isic4 year: egen double within_inv_mu  = total(contrib_within)
bys isic4 year: egen double between_inv_mu = total(contrib_between)
bys isic4 year: egen double entry_inv_mu   = total(contrib_entry)

preserve
    keep isic4 year within_inv_mu between_inv_mu entry_inv_mu
    bys isic4 year: keep if _n == 1

    merge 1:1 isic4 year using `exitterm', nogen
    replace exit_inv_mu = 0 if missing(exit_inv_mu)

    tempfile decomp4
    save `decomp4', replace
restore

*============================================================*
* 2. BUILD SECTOR-YEAR REGRESSION DATASET
*============================================================*
preserve

bys isic4 year: gen n_firms = _N
bys isic4 year: keep if _n == 1

keep isic4 year ///
     d_inv_mu_j ///
     change_IP output_IV ///
     Z_input ls_pre_filled post2016 ///
     HHI_dom ppi apparent_consumption ///
     n_firms dom_j

isid isic4 year

merge 1:1 isic4 year using `decomp4', nogen

foreach v in within_inv_mu between_inv_mu entry_inv_mu exit_inv_mu {
    replace `v' = 0 if missing(`v')
}

gen double neg_exit_inv_mu = -exit_inv_mu

gen double decomp_total = within_inv_mu + between_inv_mu + entry_inv_mu - exit_inv_mu
gen double decomp_gap   = d_inv_mu_j - decomp_total

summarize decomp_gap, detail

*============================================================*
* 3. ADDITIONAL CONTROLS + DECOMPOSITION SHARES
*============================================================*
tsset isic4 year

gen double ldom_j = L.dom_j

gen double ln_ppi  = ln(ppi) if ppi > 0
gen double dln_ppi = D.ln_ppi

gen double dHHI = D.HHI_dom

gen double ln_abs  = ln(apparent_consumption) if apparent_consumption > 0
gen double dln_abs = D.ln_abs

summarize decomp_gap, detail

gen double abs_within_inv_mu  = abs(within_inv_mu)
gen double abs_between_inv_mu = abs(between_inv_mu)
gen double abs_entry_inv_mu   = abs(entry_inv_mu)
gen double abs_exit_inv_mu    = abs(exit_inv_mu)

gen double gross_decomp_total = ///
    abs_within_inv_mu + abs_between_inv_mu + abs_entry_inv_mu + abs_exit_inv_mu

gen double within_share  = abs_within_inv_mu  / gross_decomp_total if gross_decomp_total > 0
gen double between_share = abs_between_inv_mu / gross_decomp_total if gross_decomp_total > 0
gen double entry_share   = abs_entry_inv_mu   / gross_decomp_total if gross_decomp_total > 0
gen double exit_share    = abs_exit_inv_mu    / gross_decomp_total if gross_decomp_total > 0

gen double share_sum = within_share + between_share + entry_share + exit_share
summarize share_sum, detail

gen double w_within_abs  = abs_within_inv_mu  * dom_j if gross_decomp_total > 0 & !missing(dom_j)
gen double w_between_abs = abs_between_inv_mu * dom_j if gross_decomp_total > 0 & !missing(dom_j)
gen double w_entry_abs   = abs_entry_inv_mu   * dom_j if gross_decomp_total > 0 & !missing(dom_j)
gen double w_exit_abs    = abs_exit_inv_mu    * dom_j if gross_decomp_total > 0 & !missing(dom_j)

gen double w_gross_total = gross_decomp_total * dom_j if gross_decomp_total > 0 & !missing(dom_j)

quietly summarize w_within_abs, meanonly
scalar S_within_abs = r(sum)

quietly summarize w_between_abs, meanonly
scalar S_between_abs = r(sum)

quietly summarize w_entry_abs, meanonly
scalar S_entry_abs = r(sum)

quietly summarize w_exit_abs, meanonly
scalar S_exit_abs = r(sum)

quietly summarize w_gross_total, meanonly
scalar S_gross_total = r(sum)

scalar share_within_total  = 100 * S_within_abs  / S_gross_total
scalar share_between_total = 100 * S_between_abs / S_gross_total
scalar share_entry_total   = 100 * S_entry_abs   / S_gross_total
scalar share_exit_total    = 100 * S_exit_abs    / S_gross_total

scalar share_total_check = ///
    share_within_total + share_between_total + share_entry_total + share_exit_total

*============================================================*
* 4. IV REGRESSIONS: DEFINE CONTROL SETS
*============================================================*

local sample if inrange(year, 2011, 2019)
local fe absorb(isic4) vce(cluster isic4) partial(i.year)

local c0 i.year
local c1 Z_input c.ls_pre_filled##i.post2016 i.year
local c2 Z_input c.ls_pre_filled##i.post2016 dln_ppi i.year
local c3 Z_input c.ls_pre_filled##i.post2016 dln_ppi dHHI i.year
local c4 Z_input c.ls_pre_filled##i.post2016 dln_ppi dHHI dln_abs i.year
local c5 Z_input c.ls_pre_filled##i.post2016 dln_ppi dHHI dln_abs ldom_j n_firms i.year

local rhs `c1'

*============================================================*
* 5. MAIN DECOMPOSITION REGRESSIONS
*============================================================*

eststo clear

eststo total: ///
    ivreghdfe d_inv_mu_j ///
        (change_IP = output_IV) ///
        `rhs' ///
        `sample', ///
        `fe'

eststo within: ///
    ivreghdfe within_inv_mu ///
        (change_IP = output_IV) ///
        `rhs' ///
        `sample', ///
        `fe'

eststo between: ///
    ivreghdfe between_inv_mu ///
        (change_IP = output_IV) ///
        `rhs' ///
        `sample', ///
        `fe'

eststo entry: ///
    ivreghdfe entry_inv_mu ///
        (change_IP = output_IV) ///
        `rhs' ///
        `sample', ///
        `fe'

eststo negexit: ///
    ivreghdfe neg_exit_inv_mu ///
        (change_IP = output_IV) ///
        `rhs' ///
        `sample', ///
        `fe'

*============================================================*
* 6. EXPORT MAIN LATEX TABLE
*============================================================*

esttab total within between entry negexit using "$folder\Tables\decomposition1.tex", ///
    replace ///
    keep(change_IP Z_input) ///
    order(change_IP Z_input) ///
    varlabels( ///
        change_IP "Import penetration change" ///
        Z_input   "Input-tariff exposure" ///
    ) ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Total" "Within" "Reallocation" "Entry" "- Exit") ///
    stats(N, fmt(0) labels("Observations")) ///
    label booktabs ///
    alignment(D{.}{.}{-1}) ///
    fragment nogaps compress

restore

*============================================================*
* 7. LINE GRAPHS FOR AGGREGATE MARKUPS
*============================================================*

preserve
    use `agg_markup_series', clear
    merge 1:1 year using `agg_from_sectors', nogen

    sort year
    tsset year

    twoway ///
        (line mu_agg_BU_firm year, lwidth(medthick) lpattern(solid)) ///
        (line mu_agg_BU_sector year, lwidth(medthick) lpattern(dash)) ///
        (line mu_agg_DLEU year, lwidth(medthick) lpattern(dot)), ///
        title("Aggregate Markup Measures over Time") ///
        subtitle("Turkey manufacturing, annual series") ///
        xtitle("Year") ///
        ytitle("Aggregate markup") ///
        xlabel(2011(1)2019, angle(0)) ///
        ylabel(, angle(0)) ///
        legend(order(1 "Bottom-Up (firm-level harmonic)" ///
                     2 "Bottom-Up (sector-rebuilt harmonic)" ///
                     3 "DLEU-style (sales-weighted arithmetic)") ///
               rows(3) ring(0) pos(11) region(lstyle(none))) ///
        graphregion(color(white)) ///
        plotregion(color(white)) ///
        name(graph_markup_compare_level, replace)

    graph export "$folder\Tables\aggregate_markup_compare_level.png", replace width(2000)

    twoway ///
        (line ln_mu_agg_BU_firm year, lwidth(medthick) lpattern(solid)) ///
        (line ln_mu_agg_BU_sector year, lwidth(medthick) lpattern(dash)) ///
        (line ln_mu_agg_DLEU year, lwidth(medthick) lpattern(dot)), ///
        title("Log Aggregate Markup Measures over Time") ///
        subtitle("Turkey manufacturing, annual series") ///
        xtitle("Year") ///
        ytitle("Log aggregate markup") ///
        xlabel(2011(1)2019, angle(0)) ///
        ylabel(, angle(0)) ///
        legend(order(1 "Bottom-Up (firm-level harmonic)" ///
                     2 "Bottom-Up (sector-rebuilt harmonic)" ///
                     3 "DLEU-style (sales-weighted arithmetic)") ///
               rows(3) ring(0) pos(11) region(lstyle(none))) ///
        graphregion(color(white)) ///
        plotregion(color(white)) ///
        name(graph_markup_compare_log, replace)

    graph export "$folder\Tables\aggregate_markup_compare_log.png", replace width(2000)

    quietly summarize year, meanonly
    local firstyear = r(min)

    quietly summarize mu_agg_BU_firm if year == `firstyear', meanonly
    scalar base_BU_firm = r(mean)

    quietly summarize mu_agg_BU_sector if year == `firstyear', meanonly
    scalar base_BU_sector = r(mean)

    quietly summarize mu_agg_DLEU if year == `firstyear', meanonly
    scalar base_DLEU = r(mean)

    gen double idx_BU_firm   = 100 * mu_agg_BU_firm   / base_BU_firm
    gen double idx_BU_sector = 100 * mu_agg_BU_sector / base_BU_sector
    gen double idx_DLEU      = 100 * mu_agg_DLEU      / base_DLEU

    twoway ///
        (line idx_BU_firm year, lwidth(medthick) lpattern(solid)) ///
        (line idx_BU_sector year, lwidth(medthick) lpattern(dash)) ///
        (line idx_DLEU year, lwidth(medthick) lpattern(dot)), ///
        title("Aggregate Markup Measures over Time") ///
        subtitle("Normalized to 100 in `firstyear'") ///
        xtitle("Year") ///
        ytitle("Index (`firstyear' = 100)") ///
        xlabel(2011(1)2019, angle(0)) ///
        ylabel(, angle(0)) ///
        legend(order(1 "Bottom-Up (firm-level harmonic)" ///
                     2 "Bottom-Up (sector-rebuilt harmonic)" ///
                     3 "DLEU-style (sales-weighted arithmetic)") ///
               rows(3) ring(0) pos(11) region(lstyle(none))) ///
        graphregion(color(white)) ///
        plotregion(color(white)) ///
        name(graph_markup_compare_index, replace)

    graph export "$folder\Tables\aggregate_markup_compare_index.png", replace width(2000)
restore

