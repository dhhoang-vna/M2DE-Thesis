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
set more off

*******************************************************
**** CHINESE PRODUCT GRANULARITY, BACI HS6 -> ISIC4 ****
*******************************************************

/*
Purpose
-------
Construct a feasible proxy for Chinese exporter granularity in Turkey using
BACI HS6 product-level imports mapped to ISIC Rev. 4 sectors.

Because Chinese firm-exporter data are not available, this script measures
product granularity within each ISIC4-year cell:

    HHI_prod_CHN_jt = sum_h ( M_CHN,TUR,hjt / M_CHN,TUR,jt )^2,

where HS6 products h are mapped into ISIC4 sectors j using the In Song Kim et al.
HS96 -> ISIC4 concordance with shares. This is NOT a firm-level Chinese exporter
HHI. It is a product-concentration proxy for the granularity of Chinese supply
within Turkish manufacturing sectors.

Main outputs
------------
    Data/BACI/chinese_product_granularity_isic4.dta
    Data/BACI/IP_chinese_granularity.dta

Key variables
-------------
    hhi_prod_chn        Product HHI of Chinese imports within ISIC4-year
    n_hs6_chn           Number of positive HS6 product contributions
    max_hs6_share_chn   Largest HS6 product share in the ISIC4-year cell
    eff_n_hs6_chn       Effective number of HS6 products, 1 / HHI
    G_chn_prod          BFNS-style product granularity proxy: IP * HHI
    L_G_chn_prod        One-year lag of G_chn_prod
    IP_bfns_*           Optional BFNS-style corrected IP sensitivity variables

Notes
-----
1. The default year range is 2009-2019 to match the current thesis BACI/IP
   sample and allow lags for 2011-2019 analyses. Change end_year to 2023 if
   you want to use all raw BACI files currently stored locally.
2. The script first looks for pre-filtered China->Turkey files:
       Data/BACI/CHN_TR_YYYY.dta
   and only imports the large raw BACI CSV if the pre-filtered file is missing.
3. The default concordance is the static Kim HS96-ISIC4 file:
       Data/BACI/hs96_isic4_4digit_withshares.dta
   Set use_year_specific_mapping = 1 if you want to use year-specific files
   where available.
*/

log using "$LOGS\4_chinese_granularity.log", replace

global folder "$REPLICATION_ROOT"

local start_year 2009
local end_year   2019

local use_year_specific_mapping 0

local country_china  156
local country_turkey 792

tempfile all_granularity
local first_year_done 1

forvalues yr = `start_year'/`end_year' {

    di as text "------------------------------------------------------------"
    di as text "Processing Chinese imports to Turkey, year `yr'"
    di as text "------------------------------------------------------------"

    local chntr_file "$DATA_DERIVED\BACI\CHN_TR_`yr'.dta"
    local raw_file   "$DATA_RAW\CEPII BACI HS96\BACI_HS96_Y`yr'_V202501.csv"

    capture confirm file "`chntr_file'"
    if !_rc {
        use "`chntr_file'", clear
    }
    else {
        capture confirm file "`raw_file'"
        if _rc {
            di as error "Missing both pre-filtered and raw BACI file for `yr'. Skipping."
            continue
        }

        import delimited using "`raw_file'", clear

        capture confirm variable t
        if !_rc rename t year
        capture confirm variable i
        if !_rc rename i exporter
        capture confirm variable j
        if !_rc rename j importer
        capture confirm variable k
        if !_rc rename k product
        capture confirm variable v
        if !_rc rename v value
        capture confirm variable q
        if !_rc rename q quantity

        keep if exporter == `country_china' & importer == `country_turkey'
        compress
        save "`chntr_file'", replace
    }

    capture confirm variable year
    if _rc gen year = `yr'
    replace year = `yr' if missing(year)

    capture confirm variable value
    if _rc {
        di as error "No value variable in China->Turkey BACI file for `yr'. Skipping."
        continue
    }

    capture confirm variable product
    if _rc {
        di as error "No product variable in China->Turkey BACI file for `yr'. Skipping."
        continue
    }

    keep year exporter importer product value quantity
    capture destring value, replace force
    capture destring quantity, replace force
    keep if value > 0 & !missing(value)

    capture confirm numeric variable product
    if !_rc {
        tostring product, gen(hs6) format(%06.0f)
    }
    else {
        gen str6 hs6 = strtrim(product)
        replace hs6 = substr("000000" + hs6, length("000000" + hs6) - 5, 6)
    }

    keep year hs6 value quantity

    local map_file "$DATA_DERIVED\BACI\hs96_isic4_4digit_withshares.dta"
    if `use_year_specific_mapping' == 1 {
        capture confirm file "$DATA_DERIVED\BACI\hs96_isic4_withshares_`yr'.dta"
        if !_rc local map_file "$DATA_DERIVED\BACI\hs96_isic4_withshares_`yr'.dta"
    }

    joinby hs6 using "`map_file'", unmatched(none)

    drop if missing(isic4) | isic4 == "" | isic4 == "NA"

    capture destring share, replace force
    capture destring isic4, replace force
    drop if missing(isic4) | missing(share) | share <= 0

    gen double value_hs6_isic = value * share
    gen double quantity_hs6_isic = quantity * share if !missing(quantity)

    collapse ///
        (sum) value_hs6_isic quantity_hs6_isic, ///
        by(year isic4 hs6)

    bysort year isic4: egen double chn_m_isic = total(value_hs6_isic)
    drop if missing(chn_m_isic) | chn_m_isic <= 0

    gen double hs6_share_chn = value_hs6_isic / chn_m_isic
    gen double hs6_share_chn_sq = hs6_share_chn^2

    bysort year isic4: egen double hhi_prod_chn = total(hs6_share_chn_sq)
    bysort year isic4: egen n_hs6_chn = count(hs6)
    recast int n_hs6_chn
    bysort year isic4: egen double max_hs6_share_chn = max(hs6_share_chn)

    gen double entropy_piece = -hs6_share_chn * ln(hs6_share_chn) if hs6_share_chn > 0
    bysort year isic4: egen double entropy_hs6_chn = total(entropy_piece)

    gen double eff_n_hs6_chn = 1 / hhi_prod_chn if hhi_prod_chn > 0

    bysort year isic4 (hs6): gen byte tag_isic_year = _n == 1
    keep if tag_isic_year

    keep year isic4 chn_m_isic hhi_prod_chn n_hs6_chn ///
        max_hs6_share_chn entropy_hs6_chn eff_n_hs6_chn

    order year isic4 chn_m_isic hhi_prod_chn n_hs6_chn ///
        max_hs6_share_chn entropy_hs6_chn eff_n_hs6_chn

    compress

    if `first_year_done' == 1 {
        save `all_granularity', replace
        local first_year_done 0
    }
    else {
        append using `all_granularity'
        save `all_granularity', replace
    }
}

use `all_granularity', clear
isid year isic4, sort
order isic4 year
sort isic4 year

label var chn_m_isic          "Chinese imports to Turkey, allocated to ISIC4 (BACI value)"
label var hhi_prod_chn        "Product HHI of Chinese imports within ISIC4-year"
label var n_hs6_chn           "Number of positive HS6 product contributions"
label var max_hs6_share_chn   "Largest HS6 product share in ISIC4-year Chinese imports"
label var entropy_hs6_chn     "Entropy of HS6 product shares in ISIC4-year Chinese imports"
label var eff_n_hs6_chn       "Effective number of HS6 products, 1/product HHI"

save "$DATA_DERIVED\BACI\chinese_product_granularity_isic4.dta", replace


*******************************************
**** MERGE WITH ABSORPTION AND BASELINE IP
*******************************************

tempfile absorption_clean ip_clean granularity_clean

save `granularity_clean', replace

capture confirm file "$DATA_DERIVED\UNIDO\absorption.dta"
if !_rc {
    use "$DATA_DERIVED\UNIDO\absorption.dta", clear

    capture confirm numeric variable year
    if _rc destring year, replace force

    capture confirm numeric variable isic4
    if _rc destring isic4, replace force

    rename Absorption apparent_consumption_gran
    keep year isic4 apparent_consumption_gran
    drop if missing(year) | missing(isic4)
    duplicates drop year isic4, force
    save `absorption_clean', replace
}

capture confirm file "$DATA_DERIVED\BACI\IP.dta"
if !_rc {
    use "$DATA_DERIVED\BACI\IP.dta", clear

    capture confirm numeric variable year
    if _rc destring year, replace force

    capture confirm numeric variable isic4
    if _rc destring isic4, replace force

    rename value_isic value_isic_baseline
    rename apparent_consumption apparent_consumption_baseline
    rename IP IP_baseline
    rename change_IP change_IP_baseline

    keep year isic4 value_isic_baseline apparent_consumption_baseline ///
        IP_baseline change_IP_baseline
    duplicates drop year isic4, force
    save `ip_clean', replace
}

use `granularity_clean', clear

capture confirm file "$DATA_DERIVED\UNIDO\absorption.dta"
if !_rc {
    merge 1:1 year isic4 using `absorption_clean', nogen keep(master match)
}

capture confirm file "$DATA_DERIVED\BACI\IP.dta"
if !_rc {
    merge 1:1 year isic4 using `ip_clean', nogen keep(master match)
}

gen double IP_chn_gran = chn_m_isic / apparent_consumption_gran ///
    if apparent_consumption_gran > 0 & !missing(apparent_consumption_gran)

gen double apparent_consumption = apparent_consumption_baseline
replace apparent_consumption = apparent_consumption_gran ///
    if missing(apparent_consumption) & !missing(apparent_consumption_gran)

gen double IP_chn = IP_baseline
replace IP_chn = IP_chn_gran if missing(IP_chn) & !missing(IP_chn_gran)

gen double G_chn_prod = IP_chn * hhi_prod_chn
label var IP_chn_gran "Chinese import penetration recomputed from granularity file"
label var IP_chn      "Chinese import penetration used for granularity proxy"
label var G_chn_prod  "Product-granularity proxy: Chinese IP times product HHI"
label var apparent_consumption "Absorption denominator used for IP sensitivity variables"

xtset isic4 year
gen double L_hhi_prod_chn = L.hhi_prod_chn
gen double L_G_chn_prod = L.G_chn_prod
gen double D_hhi_prod_chn = D.hhi_prod_chn
gen double D_G_chn_prod = D.G_chn_prod

label var L_hhi_prod_chn "Lagged product HHI of Chinese imports"
label var L_G_chn_prod   "Lagged product-granularity proxy"
label var D_hhi_prod_chn "Change in product HHI of Chinese imports"
label var D_G_chn_prod   "Change in product-granularity proxy"


**************************************************
**** OPTIONAL BFNS-STYLE CORRECTED IP VARIABLES
**************************************************

/*
BFNS industry-level correction:

    log(M_tilde_jt) = log(M_jt) + kappa * (sigma - 1) * S_jt * HHI_jt.

Here S_jt is proxied by Chinese import penetration IP_chn, and HHI_jt by the
HS6 product HHI. kappa = 1 is Cournot-style; kappa = 1/sigma is a conservative
price-competition-style scaling. These variables are sensitivity objects, not
the baseline treatment.
*/

gen double ln_chn_m_isic = ln(chn_m_isic) if chn_m_isic > 0

foreach s in 4 5 6 {
    gen double lnM_bfns_c_s`s' = ln_chn_m_isic + (`s' - 1) * G_chn_prod ///
        if !missing(ln_chn_m_isic, G_chn_prod)
    gen double M_bfns_c_s`s' = exp(lnM_bfns_c_s`s')
    gen double IP_bfns_c_s`s' = M_bfns_c_s`s' / apparent_consumption ///
        if apparent_consumption > 0

    gen double lnM_bfns_p_s`s' = ln_chn_m_isic + ((`s' - 1) / `s') * G_chn_prod ///
        if !missing(ln_chn_m_isic, G_chn_prod)
    gen double M_bfns_p_s`s' = exp(lnM_bfns_p_s`s')
    gen double IP_bfns_p_s`s' = M_bfns_p_s`s' / apparent_consumption ///
        if apparent_consumption > 0

    label var IP_bfns_c_s`s' "BFNS-corrected IP, Cournot scaling, sigma=`s'"
    label var IP_bfns_p_s`s' "BFNS-corrected IP, conservative price scaling, sigma=`s'"
}

order isic4 year chn_m_isic IP_chn IP_baseline IP_chn_gran ///
    hhi_prod_chn G_chn_prod L_hhi_prod_chn L_G_chn_prod ///
    n_hs6_chn max_hs6_share_chn eff_n_hs6_chn entropy_hs6_chn

sort isic4 year
compress

save "$DATA_DERIVED\BACI\IP_chinese_granularity.dta", replace


************************
**** BASIC DIAGNOSTICS
************************

di as text "Summary of Chinese product granularity proxy:"
summ hhi_prod_chn G_chn_prod L_G_chn_prod n_hs6_chn max_hs6_share_chn ///
    if inrange(year, 2011, 2019), detail

capture noisily corr hhi_prod_chn G_chn_prod IP_chn IP_baseline ///
    if inrange(year, 2011, 2019)

/*
Suggested merge into firm- or sector-year analysis files:

    merge m:1 isic4 year using "$DATA_DERIVED\BACI\IP_chinese_granularity.dta", ///
        keepusing(hhi_prod_chn G_chn_prod L_hhi_prod_chn L_G_chn_prod ///
                  IP_bfns_c_s4 IP_bfns_c_s5 IP_bfns_c_s6 ///
                  IP_bfns_p_s4 IP_bfns_p_s5 IP_bfns_p_s6)

For refinement 2, use L_G_chn_prod or L_hhi_prod_chn as the predetermined
foreign-granularity control. For refinement 3, interact change_IP or its IV
counterpart with L_G_chn_prod and/or domestic HHI.
*/

log close


