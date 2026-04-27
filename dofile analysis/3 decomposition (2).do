clear mata
capture log close
clear

log using "D:\1. M2 Development Economics\0. Thesis\Thesis\Logs\3 decomposition", replace

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"

use "$folder\Data\data_ready.dta", clear


drop _merge

merge m:1 isic4 year using "$folder\Data\UNIDO\apparent_consumption.dta"
drop if missing(isic4, year, firm_id)
drop if missing(share_sales, mu)
drop if mu<=0
drop if share_sales<0

*--------------------------------------
* 0. SECTOR MARKUP VIA HARMONIC MEAN
*--------------------------------------

isid firm_id year
xtset firm_id year

gen double inv_mu = 1/mu

bys isic4 year: egen double inv_mu_j = total(share_sales * inv_mu)
gen double mu_j    = 1 / inv_mu_j
gen double ln_mu_j = ln(mu_j)

preserve
    keep isic4 year inv_mu_j mu_j ln_mu_j
    bys isic4 year: keep if _n == 1

    isid isic4 year
    tsset isic4 year

    gen double d_inv_mu_j = D.inv_mu_j
    gen double d_ln_mu_j  = D.ln_mu_j

    tempfile sector_series
    save `sector_series', replace
restore

merge m:1 isic4 year using `sector_series', nogen

*-------------------------------*
* 1. FOUR-TERM DECOMPOSITION
*-------------------------------*

sort firm_id year

* Lags
by firm_id (year): gen double l_share  = share_sales[_n-1]
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

* Continuers: present in t-1 and t in same sector
gen byte continuer = (l_year == year-1) & (l_isic4 == isic4)

* Entrants for decomposition: present in t, absent in t-1
* Exclude first sample year to avoid left-censoring contamination
gen byte entrant = (year > `minyear') & !continuer
replace entrant = 0 if missing(year) | missing(isic4) | missing(share_sales) | missing(inv_mu)

* Exits for decomposition: present in t-1, absent in t
* Constructed on row t-1, then shifted forward to year t
gen byte exiter_next = 0
replace exiter_next = 1 if !missing(year, isic4, share_sales, inv_mu) ///
    & (missing(f_year) | f_year != year + 1 | f_isic4 != isic4)

* Remove right-censored fake exits in final sample year
replace exiter_next = 0 if year == `maxyear'

*-------------------------------*
* 1B. Firm-level contributions
*-------------------------------*

* Continuers: within and reallocation
gen double d_share    = share_sales - l_share if continuer
gen double d_inv_mu   = inv_mu - l_inv_mu if continuer
gen double s_bar      = 0.5*(share_sales + l_share) if continuer
gen double inv_mu_bar = 0.5*(inv_mu + l_inv_mu) if continuer

gen double contrib_within  = s_bar      * d_inv_mu if continuer
gen double contrib_between = inv_mu_bar * d_share  if continuer

* Entrants: full current contribution
gen double contrib_entry = share_sales * inv_mu if entrant

* Exits: full lagged contribution, assigned to year t
gen double contrib_exit_tmp = share_sales * inv_mu if exiter_next
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

* Sector-year counts and totals from firm-year data
bys isic4 year: gen n_firms = _N
bys isic4 year: egen dom_j  = total(dom_sales)

* Keep one row per sector-year
bys isic4 year: keep if _n == 1

* Keep sector-year variables needed for regressions
keep isic4 year ///
     d_inv_mu_j ///
     change_IP output_IV ///
     Z_input ls_pre_filled ///
     HHI_dom ppi apparent_consumption ///
     n_firms dom_j

isid isic4 year

* Merge decomposition outcomes
merge 1:1 isic4 year using `decomp4', nogen

foreach v in within_inv_mu between_inv_mu entry_inv_mu exit_inv_mu {
    replace `v' = 0 if missing(`v')
}

* Export sector-level decomposition terms for Python moments script
export delimited using "$folder\struct\data\sector_moments.csv", replace


* Optional sign-flipped exit term for easier interpretation in tables
gen double neg_exit_inv_mu = -exit_inv_mu

* Decomposition identity check
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

*--------------------------------------*
* 3A. Check decomposition identity
*--------------------------------------*
summarize decomp_gap, detail

*--------------------------------------*
* 3B. Absolute components at sector-year level
*--------------------------------------*
gen double abs_within_inv_mu  = abs(within_inv_mu)
gen double abs_between_inv_mu = abs(between_inv_mu)
gen double abs_entry_inv_mu   = abs(entry_inv_mu)
gen double abs_exit_inv_mu    = abs(exit_inv_mu)

gen double gross_decomp_total = ///
    abs_within_inv_mu + abs_between_inv_mu + abs_entry_inv_mu + abs_exit_inv_mu

gen double share_sum = . 
replace share_sum = ///
    (abs_within_inv_mu + abs_between_inv_mu + abs_entry_inv_mu + abs_exit_inv_mu) ///
    / gross_decomp_total if gross_decomp_total > 0

summarize share_sum, detail

* Save the sector-year regression dataset now
tempfile regdata_sector
save `regdata_sector', replace

*============================================================*
* 3C. BUILD YEARLY WEIGHTED-MASS DATASET
*     This dataset will be used for BOTH:
*     (i) Panel B overall shares
*     (ii) line graph over time
*============================================================*

use `regdata_sector', clear

keep if gross_decomp_total > 0
drop if missing(year, dom_j)

* sector-year weighted absolute masses
gen double yw_within_abs_sy  = abs_within_inv_mu  * dom_j
gen double yw_between_abs_sy = abs_between_inv_mu * dom_j
gen double yw_entry_abs_sy   = abs_entry_inv_mu   * dom_j
gen double yw_exit_abs_sy    = abs_exit_inv_mu    * dom_j
gen double yw_gross_total_sy = gross_decomp_total * dom_j

* collapse to year
collapse (sum) ///
    yw_within_abs_sy ///
    yw_between_abs_sy ///
    yw_entry_abs_sy ///
    yw_exit_abs_sy ///
    yw_gross_total_sy, by(year)

rename yw_within_abs_sy  yw_within_abs
rename yw_between_abs_sy yw_between_abs
rename yw_entry_abs_sy   yw_entry_abs
rename yw_exit_abs_sy    yw_exit_abs
rename yw_gross_total_sy yw_gross_total

* yearly percentage shares for graph
gen double within_share_t  = 100 * yw_within_abs  / yw_gross_total
gen double between_share_t = 100 * yw_between_abs / yw_gross_total
gen double entry_share_t   = 100 * yw_entry_abs   / yw_gross_total
gen double exit_share_t    = 100 * yw_exit_abs    / yw_gross_total

gen double share_total_t = within_share_t + between_share_t + entry_share_t + exit_share_t
summarize share_total_t, detail

*--------------------------------------*
* Panel B totals computed from SAME data
*--------------------------------------*
quietly summarize yw_within_abs, meanonly
scalar S_within_abs = r(sum)

quietly summarize yw_between_abs, meanonly
scalar S_between_abs = r(sum)

quietly summarize yw_entry_abs, meanonly
scalar S_entry_abs = r(sum)

quietly summarize yw_exit_abs, meanonly
scalar S_exit_abs = r(sum)

quietly summarize yw_gross_total, meanonly
scalar S_gross_total = r(sum)

scalar share_within_total  = 100 * S_within_abs  / S_gross_total
scalar share_between_total = 100 * S_between_abs / S_gross_total
scalar share_entry_total   = 100 * S_entry_abs   / S_gross_total
scalar share_exit_total    = 100 * S_exit_abs    / S_gross_total
scalar share_total_check   = ///
    share_within_total + share_between_total + share_entry_total + share_exit_total

local p_within  : display %6.2f scalar(share_within_total)
local p_between : display %6.2f scalar(share_between_total)
local p_entry   : display %6.2f scalar(share_entry_total)
local p_exit    : display %6.2f scalar(share_exit_total)
local p_total   : display %6.2f scalar(share_total_check)

export delimited using "$folder\Tables\decomposition_shares_over_time.csv", replace

twoway ///
    (line within_share_t year,   lpattern(solid)     lwidth(medthick) msymbol(none)) ///
    (line between_share_t year,  lpattern(dash)      lwidth(medthick) msymbol(none)) ///
    (line entry_share_t year,    lpattern(shortdash) lwidth(medium)   msymbol(none)) ///
    (line exit_share_t year,     lpattern(dot)       lwidth(medium)   msymbol(none)), ///
    xlabel(2011(1)2019, labsize(small) angle(0)) ///
    ylabel(0(10)100, labsize(small) angle(0) format(%2.0f)) ///
    xtitle("Year", size(medsmall)) ///
    ytitle("Share of gross absolute decomposition mass (%)", size(medsmall)) ///
    legend(order(1 "Within-firm adjustment" ///
                 2 "Reallocation" ///
                 3 "Entry" ///
                 4 "Exit") ///
           rows(2) size(small) region(lstyle(none))) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    yscale(range(0 100)) ///
    xscale(range(2011 2019)) ///
    title("Absolute contribution shares over time", size(medium)) ///
    name(decomp_shares_time, replace)

graph export "$folder\Figs\decomposition_shares_over_time.png", replace width(2400)

* go back to regression dataset
use `regdata_sector', clear

*============================================================*
* 3C. YEARLY + POOLED DESCRIPTIVE SUMMARY OF DECOMPOSITION
*     3-part gross absolute decomposition:
*     Within / Reallocation / Selection(= Entry + Exit)
*============================================================*

use `regdata_sector', clear

keep if gross_decomp_total > 0
drop if missing(year, dom_j)

*--------------------------------------*
* 1. Weighted absolute masses at sector-year level
*--------------------------------------*
gen double yw_within_abs_sy      = abs_within_inv_mu  * dom_j
gen double yw_reallocation_abs_sy= abs_between_inv_mu * dom_j
gen double yw_selection_abs_sy   = (abs_entry_inv_mu + abs_exit_inv_mu) * dom_j
gen double yw_gross_total_sy     = gross_decomp_total * dom_j

*--------------------------------------*
* 2. Collapse to year for time-series composition
*--------------------------------------*
collapse (sum) ///
    yw_within_abs_sy ///
    yw_reallocation_abs_sy ///
    yw_selection_abs_sy ///
    yw_gross_total_sy, by(year)

rename yw_within_abs_sy       yw_within_abs
rename yw_reallocation_abs_sy yw_reallocation_abs
rename yw_selection_abs_sy    yw_selection_abs
rename yw_gross_total_sy      yw_gross_total

* Yearly shares (% of gross absolute mass)
gen double within_share_t       = 100 * yw_within_abs       / yw_gross_total
gen double reallocation_share_t = 100 * yw_reallocation_abs / yw_gross_total
gen double selection_share_t    = 100 * yw_selection_abs    / yw_gross_total

* Check
gen double share_total_t = within_share_t + reallocation_share_t + selection_share_t
summarize share_total_t, detail

* Save yearly dataset for export / later use
tempfile yearly_decomp3
save `yearly_decomp3', replace

export delimited using "$folder\Tables\decomposition_3parts_over_time.csv", replace

*--------------------------------------*
* 3. 100% stacked bar chart by year
*--------------------------------------*
graph bar (asis) ///
    within_share_t ///
    reallocation_share_t ///
    selection_share_t, ///
    over(year, label(labsize(small) angle(0))) ///
    stack ///
    asyvars ///
    ylabel(0(10)100, labsize(small) angle(0) format(%2.0f)) ///
    ytitle("Share of gross absolute decomposition mass (%)", size(medsmall)) ///
    legend(order(1 "Within-firm adjustment" ///
                 2 "Reallocation" ///
                 3 "Selection (entry + exit)") ///
           rows(1) size(small) region(lstyle(none))) ///
    title("Yearly composition of gross absolute markup adjustment", size(medium)) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(decomp3_stacked_yearly, replace)

graph export "$folder\Figs\decomposition_3parts_stacked_yearly.png", replace width(2400)

*--------------------------------------*
* 4. Compute pooled full-sample shares from SAME yearly masses
*--------------------------------------*
use `yearly_decomp3', clear

quietly summarize yw_within_abs, meanonly
scalar S_within_abs = r(sum)

quietly summarize yw_reallocation_abs, meanonly
scalar S_reallocation_abs = r(sum)

quietly summarize yw_selection_abs, meanonly
scalar S_selection_abs = r(sum)

quietly summarize yw_gross_total, meanonly
scalar S_gross_total = r(sum)

scalar share_within_total       = 100 * S_within_abs       / S_gross_total
scalar share_reallocation_total = 100 * S_reallocation_abs / S_gross_total
scalar share_selection_total    = 100 * S_selection_abs    / S_gross_total
scalar share_total_check        = ///
    share_within_total + share_reallocation_total + share_selection_total

display "Within share (total):       " %6.2f scalar(share_within_total)
display "Reallocation share (total): " %6.2f scalar(share_reallocation_total)
display "Selection share (total):    " %6.2f scalar(share_selection_total)
display "Total check:                " %6.2f scalar(share_total_check)

*--------------------------------------*
* 5. Build tiny dataset for pooled bar chart
*--------------------------------------*
clear
set obs 3

gen str20 component = ""
replace component = "Within-firm adjustment" in 1
replace component = "Reallocation"          in 2
replace component = "Selection (entry+exit)" in 3

gen double share = .
replace share = scalar(share_within_total)       in 1
replace share = scalar(share_reallocation_total) in 2
replace share = scalar(share_selection_total)    in 3

export delimited using "$folder\Tables\decomposition_3parts_pooled_shares.csv", replace

*--------------------------------------*
* 6. Pooled full-sample bar chart
*--------------------------------------*
graph bar share, ///
    over(component, label(labsize(small) angle(20))) ///
    blabel(bar, format(%4.1f) size(small)) ///
    ylabel(0(10)100, labsize(small) angle(0) format(%2.0f)) ///
    ytitle("Share of gross absolute decomposition mass (%)", size(medsmall)) ///
    title("Pooled contribution shares over the full sample", size(medium)) ///
    legend(off) ///
    graphregion(color(white)) ///
    plotregion(color(white)) ///
    name(decomp3_pooled_bar, replace)

graph export "$folder\Figs\decomposition_3parts_pooled_bar.png", replace width(2400)

*--------------------------------------*
* 7. Return to original sector-year regression dataset
*--------------------------------------*
use `regdata_sector', clear

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
* 6. EXPORT LATEX TABLE WITH TWO PANELS
*============================================================*

tempfile panelA
esttab total within between entry negexit using `panelA', ///
    replace ///
    keep(change_IP Z_input) ///
    order(change_IP Z_input) ///
    varlabels( ///
        change_IP "Import penetration change" ///
        Z_input   "Input-supply control" ///
    ) ///
    b(%9.3f) se(%9.3f) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Total" "Within" "Reallocation" "Entry" "- Exit") ///
    stats(N, fmt(0) labels("Observations")) ///
    label booktabs ///
    alignment(D{.}{.}{-1}) ///
    fragment nogaps compress

file open tbl using "$folder\Tables\decomposition.tex", write replace
file write tbl "\begin{tabular}{l*{5}{c}}" _n
file write tbl "\toprule" _n
file write tbl " & Total & Within & Reallocation & Entry & - Exit \\" _n
file write tbl "\midrule" _n
file write tbl "\multicolumn{6}{l}{\textit{Panel A. IV estimates}} \\" _n
file close tbl

file open src using `panelA', read
file open tbl using "$folder\Tables\decomposition.tex", write append

file read src line
while r(eof)==0 {
    file write tbl `"`macval(line)'"' _n
    file read src line
}

file write tbl "\midrule" _n
file write tbl "\multicolumn{6}{l}{\textit{Panel B. Shares of gross absolute decomposition mass (size-weighted, \%)}} \\" _n
file write tbl "\addlinespace[2pt]" _n
file write tbl "Within-firm adjustment & \multicolumn{5}{c}{`p_within'} \\" _n
file write tbl "Reallocation & \multicolumn{5}{c}{`p_between'} \\" _n
file write tbl "Entry & \multicolumn{5}{c}{`p_entry'} \\" _n
file write tbl "Exit & \multicolumn{5}{c}{`p_exit'} \\" _n
file write tbl "\midrule" _n
file write tbl "Total & \multicolumn{5}{c}{`p_total'} \\" _n
file write tbl "\bottomrule" _n
file write tbl "\end{tabular}" _n

file close src
file close tbl

restore
log close