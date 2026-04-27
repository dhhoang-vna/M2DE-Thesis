clear mata
capture log close
clear

********************
**** DATA READY ****
********************

log using "D:\1. M2 Development Economics\0. Thesis\Thesis\Logs\6 data_ready.log", replace

global folder "D:\1. M2 Development Economics\0. Thesis\Thesis"

* 1. Merging IV with firm-year dataset

use "$folder\Data\ORBIS\orbis_ppi.dta", clear

merge m:1 isic4 year using "$folder\Data\IV\output_IV.dta"

* 2. Merging with import penetration 
drop _merge

merge m:1 isic4 year using "$folder\Data\BACI\IP.dta"

drop _merge

* 3. Merging with labor share data

merge m:1 isic4 year using "$folder\Data\TurkStat\labor_share_4.dta"

keep if _merge == 3

save "$folder\Data\data_ready.dta", replace


log close















