# M2 Development Economics Thesis Replication Package

This repository is the cleaned replication package for
`tex/m2de_thesis.tex` and the thesis PDF `tex/m2de_thesis.pdf`.

GitHub repository: https://github.com/dhhoang-vna/M2DE-Thesis

The package follows the AEA replication-package convention: code, public-facing
tables and figures, paper source, data-availability notes, and verification
metadata are included; restricted firm-level and bulky raw inputs are described
but not redistributed.

## Repository Structure

```text
code/
  00_setup/                  shared path setup and Stata package installer
  01_construct/              data-construction scripts for licensed/raw inputs
  02_analysis/               Stata estimation, robustness, mechanisms, SCM
  03_figures_tables/         descriptive thesis figures and audit tables
  04_calibration_validation/ Monte Carlo and structural validation code
  99_build_paper/            LaTeX build wrapper
data/
  public_raw_or_download_instructions/
  restricted_placeholder/
  derived_public/
output/
  figures/
  tables/
  m2de_thesis_exhibit_hash_check.csv
  tex/
  m2de_thesis.tex
  m2de_thesis.pdf
  M2DEThesis.bib
code/99_build_paper/
  check_m2de_thesis_exhibits.ps1  submitted-exhibit hash checker
```

## Quick Start

1. Read `data_availability.md`.
2. Install Stata 17 or later, R, Python 3.10+, and a TeX distribution with
   `pdflatex` and `biber`.
3. Install Stata packages listed in `code/00_setup/install_stata_packages.do`.
4. Place licensed or locally reconstructed inputs under
   `data/restricted_placeholder/raw/` and
   `data/restricted_placeholder/derived/`.
5. From the repository root, run the current thesis-results pipeline:

```powershell
powershell -ExecutionPolicy Bypass -File code/run_all.ps1 -StataExe "D:\STATA19\StataMP-64.exe" -M2DEThesisResultsOnly -SkipSCM -SkipR -SkipPython -SkipPaper
```

6. Build the paper:

```powershell
powershell -ExecutionPolicy Bypass -File code/99_build_paper/build_paper.ps1
```

For a full raw-data rebuild, run `code/run_all.ps1` without
`-M2DEThesisResultsOnly` after placing all raw inputs. The focused M2DE thesis run is the
recommended audit target for matching the submitted thesis exhibits.

See `manifest.csv` for table/figure provenance and
`output/m2de_thesis_exhibit_hash_check.csv` for the file-level comparison.
