# Detailed synthesis of causal-core results

Run: `struct2/outputs/causal_core_20260513`

This note synthesizes the causal-core SMM run using the output files in this folder: the run report, data and model moments, moment gaps, estimated parameters, objective history, residual IV validation, model panel, aggregate and sector counterfactuals, decomposition tables, and allocative-wedge tables. The concise version of the message is: the model does what it was designed to do. It fits the main output-competition IV response, absorbs the residual loading on the output shifter, and generates economically meaningful sector-level counterfactual effects. But it is not yet a full model of markup dynamics, because the input, decomposition, concentration, and selection diagnostics remain far from the data.

## 1. What this run is estimating

The run estimates a causal-core incumbent-markup mechanism. The key design choice is that the SMM objective uses only output-competition IV moments. All input-shock moments, exit moments, and decomposition moments are diagnostic. This distinction matters for interpretation.

The sample in `run_report.md` covers:

| Object | Count |
| --- | ---: |
| Firm-years | 55,943 |
| Firms | 14,612 |
| Sectors | 112 |
| Years | 2011-2019 |

The model panel in `model_panel_estimated.csv` contains firm-year observations with observed markup growth (`dln_mu`), model-implied markup growth (`dln_mu_model`), three output-shock channels, model markups and inverse markups, model shares, exit probabilities, survival probabilities, and the shifters `change_IP`, `output_IV`, and `Z_input`. The panel therefore stores the object that links the estimated parameters to the moment tables and counterfactuals.

The estimated specification should be read as answering one narrow question:

> Can a parsimonious output-competition channel reproduce the causal IV response of incumbent markups to output-market shocks?

It should not yet be read as answering:

> Can this model explain all observed markup growth, entry and exit, input-market shocks, or the accounting decomposition of aggregate markup changes?

The answer to the first question is mostly yes. The answer to the second is clearly no, at least in this run.

## 2. Estimated parameters and economic content

The estimated parameters are:

| Parameter | Value | Status | Interpretation |
| --- | ---: | --- | --- |
| `output_scale` | 3.449 | estimated | Scales the output-competition channel. |
| `output_markup` | -0.674 | estimated | Baseline output-shock effect on markup growth. |
| `high_markup_output` | -1.514 | estimated | Extra output-shock effect for high-markup firms/sectors. |
| `concentration_output` | -3.964 | estimated | Extra output-shock effect in concentrated markets. |
| `share_output` | 0.500 | estimated | Output-shock component in share dynamics. |
| `share_input` | 0.000 | fixed | Input channel switched off. |
| `input_markup` | 0.000 | fixed | Input-markup channel switched off. |
| `mean_reversion` | 1.382 | estimated | Markup process pulls back toward its reference level. |
| `drift` | -0.104 | estimated | Average residual drift in markup dynamics. |
| `exit_intercept` | -2.300 | fixed | Exit block fixed. |
| `exit_ip` | 0.000 | fixed | No IP/output-shock selection effect. |
| `exit_markup` | 0.000 | fixed | No markup-dependent exit effect. |
| `eta` | 1.010 | fixed elasticity | Fixed elasticity parameter. |
| `nu` | 4.000 | fixed elasticity | Fixed elasticity parameter. |
| `rho` | 8.000 | fixed elasticity | Fixed elasticity parameter. |
| `lambda_min` | 0.050 | fixed elasticity | Lower bound for lambda. |
| `lambda_max` | 0.980 | fixed elasticity | Upper bound for lambda. |
| `default_lambda` | 0.850 | fixed elasticity | Default lambda. |

The signs of the output parameters are coherent. The baseline output-markup effect is negative, and the high-markup and concentration interactions are more negative. This says that the model estimates output competition as a markup-reducing force, with larger effects among high-markup firms and in concentrated sectors.

That is exactly the mechanism the causal-core run is meant to isolate. It says: when output-market pressure arrives, incumbent markups fall, and this effect is stronger where markups and concentration are initially high. The estimated model is not neutral about the mechanism; it places the main action in the interaction between output shocks, markup position, and market structure.

The fixed zero input and selection parameters are equally important. They explain many of the diagnostic failures below. The model is not allowed to fit input pass-through or selection even if those mechanisms are present in the data. Those failures should therefore be used to guide the next model, not to reject the output-competition result mechanically.

## 3. Optimization and objective value

The objective history in `objective_history.csv` has 512 evaluations. The objective starts around 37.635 and converges to 1.727. The final value in `objective_value.csv` is:

| Object | Value |
| --- | ---: |
| Final SMM objective Q | 1.7266 |

This is a large improvement from the initial parameter vector. It means the optimizer found a much better fit to the targeted causal-core moments. The objective value is not close to zero because several target moments still miss, especially the upper-tail and sector inverse-markup moments. But the optimization did not fail in a mechanical sense: it moved a high initial loss into a much smaller region and produced interpretable parameter values.

The objective value should be reported with two qualifications:

1. It is the objective for the output-competition target moments only.
2. It is not a measure of fit for the full set of diagnostic moments.

## 4. Targeted moment fit

The SMM objective targets six causal-core moments. The table below comes from `moment_gaps_objective.csv` and `moment_gaps_all.csv`.

| Target moment | Data | Model | Gap | Weight | Assessment |
| --- | ---: | ---: | ---: | ---: | --- |
| `baseline_iv_dln_mu` | -0.429 | -0.441 | 0.012 | 50.832 | Very close. The model matches the central IV response. |
| `grouped_iv_q80` | -0.803 | -0.803 | -0.001 | 31.180 | Essentially exact. |
| `grouped_iv_q85` | -1.236 | -0.942 | -0.294 | 11.768 | Model underpredicts the magnitude. |
| `grouped_iv_q90` | -1.625 | -1.771 | 0.146 | 7.608 | Model overpredicts the magnitude. |
| `grouped_iv_q90_cr4_interaction` | -5.371 | -5.042 | -0.329 | 0.369 | Close in sign and order of magnitude; low weight. |
| `sector_inverse_markup_iv` | 0.128 | 0.238 | -0.110 | 40.989 | Important remaining miss. |

The strongest part of the fit is the central incumbent-markup response. The baseline IV moment is very close, and the q80 grouped moment is almost exact. This is the core evidence that the model captures the main causal output-competition elasticity in the data.

The weaker part of the fit is the shape of heterogeneity. The q85 and q90 moments show that the model can generate a steep upper-tail response, but it does not match the tail profile perfectly. It is too weak at q85 and too strong at q90. That pattern suggests that the current interaction structure is too coarse. It can steepen the response at the top, but it cannot flexibly match the gradient across the upper tail.

The sector inverse-markup IV miss is also important. The model predicts a positive response of 0.238 against 0.128 in the data. The sign is right, but the magnitude is too large. Since this moment receives a large weight, it is one of the main contributors to the final objective. This points toward a need to refine aggregation or share dynamics, not just firm-level markup response.

## 5. Non-targeted diagnostic moments

The diagnostic moments are where the model reveals its limits. These moments are not in the causal-core objective, so poor fit is informative about missing mechanisms rather than an immediate failure of the targeted estimation.

### 5.1 Other markup diagnostics

| Diagnostic moment | Data | Model | Gap | Interpretation |
| --- | ---: | ---: | ---: | --- |
| `selection_corrected_iv_dln_mu` | -0.427 | -0.436 | 0.009 | Very close, despite not being separately targeted. |
| `grouped_iv_q75` | -0.397 | -0.656 | 0.259 | Model overstates response below the targeted q80 threshold. |
| `mean_dln_mu` | 0.001 | 0.005 | -0.004 | Mean markup growth is close in absolute terms. |
| `var_dln_mu` | 0.029 | 0.036 | -0.007 | Model generates somewhat too much dispersion in markup growth. |
| `concentration_interaction_iv` | -20.090 | -7.766 | -12.324 | Model strongly underpredicts the concentration-gradient diagnostic. |

The selection-corrected IV result is reassuring. It shows that the baseline causal response is not fragile to the selection correction used in this diagnostic table. The model matches -0.436 against -0.427 in the data.

The q75 result is less reassuring. The model predicts -0.656 where the data show -0.397. Combined with the q80/q85/q90 pattern, this suggests a distributional shape problem. The model can line up some quantile moments, but it spreads the output-shock response too broadly below the upper tail and not smoothly enough within the upper tail.

The concentration interaction is the largest non-targeted markup diagnostic failure. The data moment is -20.090, while the model is -7.766. Even though the estimated concentration-output parameter is strongly negative, the model does not reproduce the full empirical concentration gradient. This could mean one of three things:

1. Concentration enters markup response nonlinearly.
2. Concentration is proxying for omitted sector structure, such as product differentiation, import exposure, or demand curvature.
3. The current aggregation of firm-level shocks into sector-level concentration interactions is too restrictive.

### 5.2 Accounting decomposition diagnostics

| Diagnostic moment | Data | Model | Gap | Interpretation |
| --- | ---: | ---: | ---: | --- |
| `within_decomp_abs_share` | 0.487 | 0.107 | 0.381 | Model puts too little decomposition action within continuing units. |
| `between_decomp_abs_share` | 0.494 | 0.231 | 0.263 | Model puts too little action in between/reallocation terms. |
| `entry_decomp_abs_share` | 0.009 | 0.325 | -0.316 | Model puts far too much action into entry. |
| `exit_decomp_abs_share` | 0.009 | 0.336 | -0.327 | Model puts far too much action into exit. |
| `decomp_total_output_iv` | 0.281 | -0.023 | 0.304 | Model misses total decomposition response. |
| `decomp_within_output_iv` | 0.062 | 0.566 | -0.503 | Model overstates within output-IV component. |
| `decomp_reallocation_output_iv` | 0.093 | -0.146 | 0.239 | Model gets reallocation response wrong in sign. |

This is the clearest evidence that the current model should not be sold as a full accounting model of aggregate markup movements. In the data, the absolute decomposition shares are almost entirely within and between: 0.487 and 0.494. Entry and exit are tiny, each around 0.009.

The model reverses this structure. It gives only 0.107 to within and 0.231 to between, while entry and exit absorb about one third each. This is not a minor miss. It says that the way the model maps firm dynamics into decomposition components is not aligned with the empirical accounting object.

There is also tension in the IV decomposition moments. The data imply a positive total output-IV response in the decomposition table, while the model gives a slightly negative response. The model strongly overpredicts the within component and gets the reallocation component wrong in sign. This combination suggests that simply adding a little noise or retuning the output coefficient will not solve the problem. The decomposition block needs structural attention.

### 5.3 Input-shock diagnostics

| Diagnostic moment | Data | Model | Gap | Interpretation |
| --- | ---: | ---: | ---: | --- |
| `input_shock_between_reallocation` | 8.055 | 3.744 | 4.310 | Model underpredicts input-shock reallocation. |
| `input_shock_within_dln_mu` | 0.142 | -0.306 | 0.448 | Model gets within input-markup relation wrong in sign. |

These misses are not surprising because the input channel is switched off in this run: `share_input = 0` and `input_markup = 0`. The diagnostics nevertheless matter. They show that input shocks are not just harmless residual variation. The data contain a meaningful input-shock reallocation pattern that the model cannot explain.

The sign error in `input_shock_within_dln_mu` is especially useful. The data show a positive relation between input shocks and within markup growth, while the model implies a negative relation. That is a strong reason to add a correlated input block before treating the model as complete.

### 5.4 Selection diagnostics

| Diagnostic moment | Data | Model | Gap | Interpretation |
| --- | ---: | ---: | ---: | --- |
| `exit_rate` | 0.069 | 0.091 | -0.022 | Model exit is too high. |
| `exit_iv` | 0.960 | 0.324 | 0.636 | Model underpredicts output-shock selection response. |

The exit block is fixed in this run, so these failures are expected. But they are still economically important. The model exit rate is 9.1 percent, compared with 6.9 percent in the data. More importantly, the model predicts only one third of the observed exit-IV relation. If exit selection is correlated with output shocks and markup levels, then future versions need a selection block before using the model for welfare or long-run composition counterfactuals.

## 6. Residual IV validation

The residual IV validation in `residual_iv_validation.csv` is one of the strongest pieces of evidence in favor of the causal-core model.

| Validation moment | Value | SE | N obs. | Clusters | First-stage F |
| --- | ---: | ---: | ---: | ---: | ---: |
| `residual_iv_validation` | 0.042 | 0.250 | 31,375 | 90 | 22.930 |

The interpretation is direct. After the model-implied output-competition component is removed, the residual markup growth no longer loads meaningfully on the excluded output shifter. The coefficient is small relative to its standard error. The first stage is strong enough that the near-zero residual coefficient is not simply a weak-instrument artifact.

This validation supports the claim that the model captures the output-shock component of incumbent markup variation. It does not validate the missing input, exit, or decomposition blocks. It validates the causal-core channel and should be presented exactly that way.

Suggested wording for the thesis:

> A residual IV exercise supports the causal-core interpretation. After removing the model-implied output-competition component from incumbent markup growth, the excluded output shifter no longer predicts the residual: the coefficient is 0.042 with a standard error of 0.250, with a first-stage F-statistic of 22.9. The model therefore absorbs the output-shock variation it is designed to explain, although it leaves non-targeted input, reallocation, and selection moments unresolved.

## 7. Aggregate counterfactuals

The aggregate counterfactual file compares the observed model path with a `no_output` scenario that removes the fitted output-competition channel. The main aggregate results are:

| Year | Observed inverse markup | No-output inverse markup | Difference | Observed markup | No-output markup | Difference |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 2011 | 0.8416 | 0.8416 | 0.0000 | 1.1882 | 1.1882 | 0.0000 |
| 2012 | 0.8008 | 0.8008 | 0.0000 | 1.2487 | 1.2488 | 0.0000 |
| 2013 | 0.8575 | 0.8473 | 0.0102 | 1.1662 | 1.1802 | -0.0140 |
| 2014 | 0.8532 | 0.8505 | 0.0027 | 1.1721 | 1.1758 | -0.0037 |
| 2015 | 0.8504 | 0.8467 | 0.0037 | 1.1759 | 1.1811 | -0.0052 |
| 2016 | 0.8490 | 0.8523 | -0.0033 | 1.1779 | 1.1733 | 0.0046 |
| 2017 | 0.8398 | 0.8425 | -0.0027 | 1.1908 | 1.1870 | 0.0039 |
| 2018 | 0.8097 | 0.8111 | -0.0014 | 1.2351 | 1.2329 | 0.0022 |
| 2019 | 0.8234 | 0.8224 | 0.0010 | 1.2145 | 1.2159 | -0.0014 |

The average aggregate inverse markup is 0.8361 in the observed scenario and 0.8350 in the no-output scenario. The average aggregate markup is 1.1966 observed and 1.1981 under no-output. From 2011 to 2019, the observed aggregate inverse markup falls by 0.0183, while the no-output counterfactual falls by 0.0192.

The conclusion is that output competition matters for causal firm- and sector-level responses, but it does not explain much of the aggregate manufacturing markup trend in this counterfactual. The aggregate differences are small and change sign over time. The largest aggregate effect is in 2013, when the observed inverse markup is 0.0102 higher than in the no-output scenario, corresponding to an observed markup about 0.014 lower.

This muted aggregate effect is not a contradiction of the IV result. The IV moments identify local causal responses to output shocks. The aggregate counterfactual combines sectors with heterogeneous shocks, weights, and offsetting effects. A strong local channel can therefore produce a small aggregate mean effect.

## 8. Manufacturing decomposition counterfactuals

The manufacturing decomposition table reports within-sector and between-sector contributions to changes in aggregate inverse markups.

Summing annual changes over 2011-2019:

| Scenario | Total change in inverse markup | Within contribution | Between contribution | Mean absolute annual change |
| --- | ---: | ---: | ---: | ---: |
| Observed | -0.0359 | -0.0558 | 0.0199 | 0.0224 |
| No-output | -0.0366 | -0.0591 | 0.0224 | 0.0194 |

The observed aggregate inverse-markup decline is mostly a within-sector decline partly offset by between-sector reallocation. Removing the output-competition channel makes the total cumulative change only slightly more negative. It also slightly increases the between-sector offset. Again, the output channel changes timing and composition more than it changes the aggregate trend.

The annual pattern is uneven. In the observed scenario, inverse markups fall sharply in 2012, rise in 2013, fall again through 2018, and recover somewhat in 2019. In the no-output scenario, the same broad pattern remains. That persistence of the aggregate path after removing output competition is another sign that additional mechanisms are driving the aggregate movement.

## 9. Sector-level counterfactual heterogeneity

The small aggregate counterfactual masks large sector-year effects in `counterfactual_sector_results.csv`. The largest differences between observed and no-output inverse markups are:

| ISIC4 | Year | Difference in inverse markup | Difference in log markup | Domestic sales | CR4 | Firms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 2790 | 2013 | 0.2954 | -0.3601 | 746,484,416 | 0.850 | 75 |
| 1629 | 2013 | 0.2199 | -0.2548 | 486,663,104 | 0.889 | 40 |
| 3230 | 2016 | -0.2005 | 0.2899 | 25,962,954 | 0.922 | 10 |
| 2513 | 2017 | -0.1934 | 0.2665 | 102,808,832 | 0.960 | 9 |
| 2513 | 2016 | 0.1868 | -0.2115 | 103,142,952 | 0.979 | 5 |
| 2431 | 2016 | -0.1744 | 0.1984 | 313,867,872 | 0.833 | 33 |
| 2790 | 2015 | 0.1662 | -0.1913 | 819,416,000 | 0.869 | 59 |
| 2513 | 2018 | -0.1396 | 0.1948 | 96,441,216 | 0.938 | 11 |
| 2431 | 2017 | -0.1233 | 0.1364 | 309,378,624 | 0.835 | 29 |
| 2610 | 2016 | -0.1131 | 0.1514 | 77,833,920 | 0.513 | 30 |

These large effects occur mostly in concentrated sectors. Several have CR4 above 0.8, and some have very few firms. This is consistent with the estimated concentration-output and high-markup-output parameters: the output-competition channel has bite in particular market structures.

The sector table therefore gives the most nuanced counterfactual conclusion:

> Output competition does not move the aggregate manufacturing markup path very much, but it has large, concentrated effects in specific sector-years. The aggregate result is muted because the sector effects are heterogeneous and offset each other.

This is likely the strongest empirical narrative for the counterfactual section. It avoids overstating aggregate importance while preserving the economic relevance of the mechanism.

## 10. Decomposition tables and component shares

The detailed decomposition tables in `counterfactual_decomposition_tables.csv` show how changes in sector inverse markups are split into within, between, entry, and exit components. Averaging absolute shares across non-baseline sector-years gives:

| Scenario | Within | Between | Entry | Exit |
| --- | ---: | ---: | ---: | ---: |
| Observed | 0.168 | 0.218 | 0.306 | 0.308 |
| No-output | 0.160 | 0.221 | 0.308 | 0.311 |

The counterfactual barely changes these component shares. This is useful because it says that removing output competition does not mechanically reorganize the model's decomposition structure. But it also reinforces the diagnostic problem: the model's decomposition structure is unlike the empirical accounting moments, where within and between dominate and entry/exit are tiny.

The conclusion should be:

1. Within this estimated model, output competition does not drive a large change in the decomposition shares.
2. Relative to the data, the model places too much decomposition action in entry and exit.
3. Future work should fix the decomposition/transition block before using these component shares as substantive evidence.

## 11. Allocative-wedge counterfactuals

The allocative-wedge table reports markup-dispersion wedges by sector-year. The summary is:

| Scenario | N | Mean | Median | p90 | p99 | Max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Observed | 942 | 0.0797 | 0.0410 | 0.1420 | 0.8848 | 4.6455 |
| No-output | 942 | 0.0792 | 0.0408 | 0.1410 | 0.8848 | 4.6455 |

The no-output counterfactual barely changes the markup-dispersion wedge. This is a strong warning against interpreting the current counterfactuals as welfare or allocative-efficiency results. The output-competition channel moves some sector-year markups, but the markup-dispersion wedge is almost unchanged in the aggregate distribution.

The right statement is:

> In this causal-core run, output-competition shocks explain targeted markup responses but do not materially change the distribution of markup-dispersion wedges. Welfare or allocative-efficiency conclusions require a richer model of demand, production, input distortions, and reallocation.

## 12. How to read the whole run

The run gives a coherent but narrow result. The targeted causal evidence says output competition lowers incumbent markups, especially in high-markup and concentrated settings. The residual validation says the model absorbs the output-shock variation it is supposed to absorb. The sector counterfactuals show that the mechanism has large local effects. But the aggregate counterfactual, allocative-wedge table, decomposition diagnostics, input-shock diagnostics, and exit diagnostics all say that this mechanism is not enough to explain the broader markup path.

The most defensible thesis conclusion is:

> The causal-core model identifies a robust output-competition markup channel. It matches the baseline IV response and the q80 response closely, captures the broad upper-tail pattern, and passes a residual IV validation. However, the mechanism has limited aggregate counterfactual bite because sector-year effects offset each other. The model also fails to match non-targeted input, reallocation, and selection diagnostics, indicating that the output-competition channel is only one component of markup dynamics.

This conclusion is stronger than saying "the model works" and stronger than saying "the model fails." It says exactly what works, what does not, and why that distinction is economically meaningful.

## 13. What to report in the thesis

The results section should be organized around four claims.

### Claim 1: The output-competition IV response is real and quantitatively matched

Report the baseline IV moment and the q80/q85/q90 moments. Emphasize that the model matches the baseline response (-0.441 versus -0.429) and q80 response (-0.803 versus -0.803). Then acknowledge the remaining tail shape misses.

Suggested text:

> The estimated model closely matches the central output-competition response of incumbent markups. The baseline IV coefficient is -0.429 in the data and -0.441 in the model. The q80 grouped moment is also nearly identical. The model generates the steepening of the response in the upper tail, although it underpredicts the q85 response and overpredicts the q90 response.

### Claim 2: The estimated mechanism is concentrated among high-markup and concentrated sectors

Use the estimated parameters and top sector counterfactual differences. The concentration-output parameter is -3.964, and the largest sector-year effects are concentrated in high-CR4 sectors such as ISIC 2790, 1629, 3230, 2513, and 2431.

Suggested text:

> The estimated interaction terms indicate that output competition matters most where initial market power is high. The high-markup output coefficient is -1.514 and the concentration-output coefficient is -3.964. In the counterfactuals, the largest sector-year effects appear in concentrated sectors, several with CR4 above 0.8.

### Claim 3: The residual IV validation supports the causal-core interpretation

Report the residual IV coefficient, standard error, and first-stage F-statistic.

Suggested text:

> A residual IV validation supports the interpretation that the model absorbs the output-shock component of markup growth. After subtracting the model-implied output-competition component, the residual coefficient on the output shifter is 0.042 with a standard error of 0.250. The first-stage F-statistic is 22.9.

### Claim 4: The current model is incomplete outside the output channel

Report the diagnostic failures directly. The decomposition shares are the clearest: data within/between shares are 0.487/0.494, while model within/between shares are 0.107/0.231 and model entry/exit shares are 0.325/0.336. Also mention input and exit diagnostics.

Suggested text:

> The model does not reproduce the non-targeted accounting and selection moments. In the data, within and between components account for nearly all absolute decomposition movements, while entry and exit are each about one percent. The model instead assigns about one third of movements to entry and one third to exit. It also misses the input-shock and exit-IV diagnostics. These patterns point to missing input and selection mechanisms rather than to failure of the targeted output-competition channel.

## 14. What not to claim

Do not claim that this run estimates welfare effects. The run report explicitly warns that the counterfactuals are output-competition counterfactuals, not welfare effects.

Do not claim that output competition explains the aggregate markup trend. The aggregate observed and no-output paths are very close. The average inverse markup is 0.8361 observed and 0.8350 under no-output, and the 2011-2019 changes differ by less than 0.001.

Do not claim that the model explains entry and exit. Exit is fixed, the model exit rate is too high, and the exit-IV diagnostic is much smaller than in the data.

Do not claim that input shocks are irrelevant. The current run switches off the input channel, yet the diagnostics show meaningful input-shock patterns in the data.

Do not use the decomposition shares as substantive evidence without qualification. They are model outputs, but they do not match the empirical accounting decomposition.

## 15. What to do next

The next steps should be ordered by how directly they address the current gaps.

### Step 1: Add an input-shock block

The input diagnostics are too large to ignore. Add nonzero `input_markup` and `share_input`, and allow input shocks to affect within markup growth and reallocation. The immediate target should be to match the sign of `input_shock_within_dln_mu` and the magnitude of `input_shock_between_reallocation`.

Concrete target:

| Moment | Data | Current model | Desired direction |
| --- | ---: | ---: | --- |
| `input_shock_within_dln_mu` | 0.142 | -0.306 | Move upward and fix sign. |
| `input_shock_between_reallocation` | 8.055 | 3.744 | Increase reallocation response. |

### Step 2: Fix the decomposition/transition mapping

The model decomposition shares are the largest structural mismatch. Investigate whether the model is mechanically generating too much entry/exit because of how sector membership, continuing firms, or weights are defined. Before adding more parameters, verify that the decomposition code uses the same continuing/entry/exit definitions in data and model.

Concrete checks:

1. Confirm that the model and data define continuing firms identically.
2. Verify whether model `exit_prob_model` is being translated into realized exits or expected exits in the decomposition.
3. Check whether small sectors mechanically inflate entry and exit absolute shares.
4. Recompute decomposition diagnostics on a balanced continuing-firm sample as a robustness check.

### Step 3: Estimate a selection block

The exit diagnostics imply that selection is not ignorable. Introduce markup-dependent and output-shock-dependent exit:

| Moment | Data | Current model | Desired direction |
| --- | ---: | ---: | --- |
| `exit_rate` | 0.069 | 0.091 | Lower average exit. |
| `exit_iv` | 0.960 | 0.324 | Increase output-shock selection response. |

This matters because selection can affect both measured markup growth and aggregate reallocation. A richer selection block may also reduce the decomposition mismatch.

### Step 4: Make the upper-tail response more flexible

The q75/q80/q85/q90 pattern suggests that a single high-markup interaction is too coarse. Consider replacing or supplementing the current upper-tail structure with a spline, bins, or continuous nonlinear function of initial markup rank.

The goal is not to overfit every quantile. The goal is to avoid a model that overstates q75, matches q80, understates q85, and overstates q90. That alternating pattern is a sign that the functional form is too rigid.

### Step 5: Revisit concentration interactions

The model underpredicts the broad concentration interaction even though the estimated concentration-output parameter is large. This suggests that concentration may enter through more than one channel. Test whether the concentration effect varies with sector size, import exposure, initial markup dispersion, or number of firms.

Potential specifications:

1. Nonlinear CR4 terms.
2. Separate effects for high-CR4 and low-firm-count sectors.
3. Interactions between concentration and initial markup rank.
4. Sector-level random effects or shrinkage for sparse sectors.

### Step 6: Separate causal counterfactuals from welfare counterfactuals

Keep the current output-competition counterfactuals as causal mechanism exercises. Do not label them welfare results. A welfare version would need a richer mapping from markups to quantities, costs, demand elasticities, entry/exit, and allocative efficiency.

The allocative-wedge table is useful as a diagnostic, but the near-identical observed and no-output wedge distributions show that this run is not yet informative about welfare changes.

### Step 7: Produce figures for the paper

This folder currently contains no figure files. The following figures would make the results easier to read:

1. Target moment fit plot: data vs model for baseline, q80, q85, q90, CR4 interaction, and sector inverse-markup IV.
2. Moment gap heatmap: targeted moments and diagnostic moments grouped by role.
3. Aggregate counterfactual path: observed vs no-output inverse markup and markup by year.
4. Sector heterogeneity plot: top sector-year counterfactual effects, colored by CR4.
5. Decomposition comparison: data vs model absolute shares for within, between, entry, and exit.
6. Residual IV validation plot: coefficient with confidence interval around zero.

These figures would communicate the central message quickly: strong fit on the causal-core target, weak fit on omitted mechanisms, small aggregate counterfactual effect, large sector-level heterogeneity.

## 16. Recommended revision to the model narrative

The model narrative should not say:

> The structural model explains markup dynamics in manufacturing.

It should say:

> The causal-core model isolates the output-competition component of incumbent markup dynamics. It matches the targeted IV response and passes residual validation, but it leaves input shocks, selection, and accounting reallocation to future extensions.

This framing is more precise and more credible. It turns the limitations into a clear research agenda rather than a defensive caveat.

## 17. Final interpretation

The results support three substantive conclusions.

First, output competition causally reduces incumbent markups. The baseline IV response is negative and closely matched by the model, and the residual validation removes the remaining output-shifter loading.

Second, the output-competition channel is heterogeneous. It is strongest in high-markup and concentrated environments, and some sector-year counterfactual effects are large. This sectoral heterogeneity is economically meaningful even though the aggregate effect is small.

Third, output competition is not the whole story. The aggregate markup path, input-shock responses, exit patterns, and decomposition shares require additional mechanisms. The next model should add input shocks, selection, and a corrected transition/decomposition block before making broader claims about aggregate dynamics or welfare.

The best one-paragraph conclusion is:

> The causal-core run identifies a robust output-competition markup channel. The model matches the central incumbent IV response, reproduces much of the upper-tail pattern, and passes a residual IV validation showing that the excluded output shifter no longer predicts model residuals. Counterfactuals show large effects in some concentrated sector-years but only small aggregate effects, because sector-level responses offset each other. The model does not match non-targeted input, decomposition, or selection diagnostics, so the current results should be interpreted as evidence for one causal mechanism rather than as a full structural account of manufacturing markup dynamics.
