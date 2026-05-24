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

********************
**** DATA READY ****
********************

log using "$LOGS\6 data_ready.log", replace

global folder "$REPLICATION_ROOT"

* 1. Merging IV with firm-year dataset

use "$DATA_DERIVED\ORBIS\orbis_ppi.dta", clear

merge m:1 isic4 year using "$DATA_DERIVED\IV\output_IV.dta"

* 2. Merging with import penetration 
drop _merge

merge m:1 isic4 year using "$DATA_DERIVED\BACI\IP.dta"

drop _merge

* 3. Merging with labor share data

merge m:1 isic4 year using "$DATA_DERIVED\TurkStat\labor_share_4.dta"

keep if _merge == 3

save "$DATA_DERIVED\data_ready.dta", replace


log close

















