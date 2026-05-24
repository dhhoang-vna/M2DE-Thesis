# Causal-Core SMM Run Report

This run estimates a causal-core incumbent markup mechanism model. The SMM objective uses only output-competition IV moments.

Input, decomposition, and exit moments are diagnostics only. They are not causal-core SMM targets.

## Sample

- Firm-years: 55,943
- Firms: 14,612
- Sectors: 112
- Years: 2011-2019

## Objective Moments

| moment | data | model | gap | weight |
| --- | --- | --- | --- | --- |
| baseline_iv_dln_mu | -0.4287 | -0.4406 | 0.0119 | 50.8316 |
| grouped_iv_q80 | -0.8034 | -0.8026 | -0.0008 | 31.1801 |
| grouped_iv_q85 | -1.2361 | -0.9418 | -0.2943 | 11.7676 |
| grouped_iv_q90 | -1.6250 | -1.7710 | 0.1461 | 7.6076 |
| grouped_iv_q90_cr4_interaction | -5.3712 | -5.0420 | -0.3292 | 0.3693 |
| sector_inverse_markup_iv | 0.1275 | 0.2377 | -0.1102 | 40.9885 |

## Diagnostic Moments

| moment | role | data | model | gap |
| --- | --- | --- | --- | --- |
| between_decomp_abs_share | accounting_diagnostic | 0.4943 | 0.2312 | 0.2630 |
| concentration_interaction_iv | other_diagnostic | -20.0902 | -7.7658 | -12.3244 |
| decomp_reallocation_output_iv | accounting_diagnostic | 0.0925 | -0.1463 | 0.2388 |
| decomp_total_output_iv | accounting_diagnostic | 0.2812 | -0.0230 | 0.3042 |
| decomp_within_output_iv | accounting_diagnostic | 0.0624 | 0.5655 | -0.5031 |
| entry_decomp_abs_share | accounting_diagnostic | 0.0090 | 0.3255 | -0.3164 |
| exit_decomp_abs_share | accounting_diagnostic | 0.0092 | 0.3365 | -0.3273 |
| exit_iv | selection_diagnostic | 0.9600 | 0.3243 | 0.6357 |
| exit_rate | selection_diagnostic | 0.0694 | 0.0911 | -0.0217 |
| grouped_iv_q75 | other_diagnostic | -0.3972 | -0.6564 | 0.2591 |
| input_shock_between_reallocation | correlated_input_diagnostic | 8.0548 | 3.7444 | 4.3104 |
| input_shock_within_dln_mu | correlated_input_diagnostic | 0.1422 | -0.3063 | 0.4485 |
| mean_dln_mu | other_diagnostic | 0.0011 | 0.0050 | -0.0039 |
| selection_corrected_iv_dln_mu | other_diagnostic | -0.4267 | -0.4361 | 0.0093 |
| var_dln_mu | other_diagnostic | 0.0295 | 0.0362 | -0.0067 |
| within_decomp_abs_share | accounting_diagnostic | 0.4875 | 0.1068 | 0.3807 |

## Objective Value

`Q = 1.7266`

## Estimated Parameters

| parameter | value | status |
| --- | --- | --- |
| output_scale | 3.4494 | estimated |
| output_markup | -0.6737 | estimated |
| high_markup_output | -1.5145 | estimated |
| concentration_output | -3.9640 | estimated |
| share_output | 0.5001 | estimated |
| share_input | 0.0000 | fixed |
| input_markup | 0.0000 | fixed |
| mean_reversion | 1.3815 | estimated |
| drift | -0.1036 | estimated |
| exit_intercept | -2.3000 | fixed |
| exit_ip | 0.0000 | fixed |
| exit_markup | 0.0000 | fixed |
| eta | 1.0100 | fixed_elasticity |
| nu | 4.0000 | fixed_elasticity |
| rho | 8.0000 | fixed_elasticity |
| lambda_min | 0.0500 | fixed_elasticity |
| lambda_max | 0.9800 | fixed_elasticity |
| default_lambda | 0.8500 | fixed_elasticity |

## Residual IV Validation

| moment | value | se | nobs | nclusters | first_stage_f | interpretation |
| --- | --- | --- | --- | --- | --- | --- |
| residual_iv_validation | 0.0417 | 0.2503 | 31375.0000 | 90.0000 | 22.9304 | Residual IV coefficient tests whether the causal-core incumbent-markup model absorbs the output-shock markup variation; small/insignificant values mean residuals no longer load on the excluded output shifter. |

## Interpretation Warning

The counterfactuals are output-competition counterfactuals, not welfare effects. Do not interpret input, decomposition, or exit diagnostics as causal SMM targets until a richer share-transition or selection block is built.
