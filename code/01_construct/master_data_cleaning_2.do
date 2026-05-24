version 17
clear all
capture log close
set more off

/*
Compatibility wrapper retained for users who previously launched
master_data_cleaning_2.do. It now delegates to the cleaned construction master.
*/

do "code/01_construct/master.do"
