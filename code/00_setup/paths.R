# Replication path configuration for R scripts.
#
# R scripts should be launched from the repository root through run_all.ps1, or
# with REPLICATION_ROOT set to the repository root.

get_replication_root <- function() {
  env_root <- Sys.getenv("REPLICATION_ROOT", unset = "")
  if (nzchar(env_root)) {
    return(normalizePath(env_root, winslash = "/", mustWork = FALSE))
  }
  normalizePath(getwd(), winslash = "/", mustWork = FALSE)
}

replication_root <- get_replication_root()
code_dir <- file.path(replication_root, "code")
raw_data_dir <- file.path(replication_root, "data", "restricted_placeholder", "raw")
derived_data_dir <- file.path(replication_root, "data", "restricted_placeholder", "derived")
public_data_dir <- file.path(replication_root, "data", "derived_public")
output_tables_dir <- file.path(replication_root, "output", "tables")
output_figures_dir <- file.path(replication_root, "output", "figures")
logs_dir <- file.path(replication_root, "output", "logs")

normalize_project_path <- function(path) {
  x <- gsub("\\\\", "/", path)
  normalizePath(x, winslash = "/", mustWork = FALSE)
}

local_path <- normalize_project_path

dir.create(raw_data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(derived_data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(public_data_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_tables_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_figures_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(logs_dir, recursive = TRUE, showWarnings = FALSE)
