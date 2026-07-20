# Hero headline numbers — standalone, all PINs.
#
# Computes the figure quoted in the explainer's hero for every PIN in the
# county: how much lower (or higher) each bill would have been under the
# Scenario 4 counterfactual — all TIFs eliminated, levies held constant —
# which is the "nothing else changed" case the hero copy describes.
#
# Runnable on its own:
#
#   Rscript hero_headline.R                      # all PINs, 2024
#   Rscript hero_headline.R 2023                 # all PINs, 2023
#   Rscript hero_headline.R 2024 out.parquet     # explicit output path
#
# The default output path carries the tax year — data/hero_headline_all_pins_
# {year}.parquet — and every row repeats that year in a `year` column, so a
# consumer can confirm the file holds what its name claims.
#
# It sets up its own libraries, database connection and helpers, so it shares
# no state with ptaxsim_explainer_tif.qmd. Run from the project root, or set
# PTAX_PROJECT_ROOT, so the relative data/ paths resolve.

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(stringr)
  library(glue)
  library(data.table)
  library(formattable)
  library(ptaxsim)
})

DB_PATH <- "data/ptaxsim-2024.0.0.db"

# Default output path for a given tax year. The year is in the filename so
# consumers can address a specific year's results without guessing, and is
# repeated inside the data so they can verify it.
hero_output_path <- function(current_year) {
  file.path("data", sprintf("hero_headline_all_pins_%d.parquet", current_year))
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

# Rem_All() and its siblings in tif_qmd_functions.R reach for `ptaxsim_db_conn`
# and `lookup_tif_wrapper` as globals, so both have to exist in this script's
# environment before that file is sourced.
hero_setup <- function(db_path = DB_PATH) {
  root <- Sys.getenv("PTAX_PROJECT_ROOT")
  if (nzchar(root)) setwd(root)

  if (!file.exists(db_path)) {
    stop("Database not found at '", db_path, "'. Run from the project root ",
         "or set PTAX_PROJECT_ROOT.", call. = FALSE)
  }

  ptaxsim_db_conn <<- dbConnect(SQLite(), db_path, flags = RSQLite::SQLITE_RO)

  # Duplicated from the qmd's setup chunk rather than shared: ptaxsim renamed
  # lookup_tif to lookup_pin_tif in 2024, and the pre-2024 path still needs the
  # legacy call. Keep in sync with the copy in ptaxsim_explainer_tif.qmd.
  lookup_tif_wrapper <<- function(current_year, pin_14, tax_code_vec) {
    if (current_year >= 2024) {
      lookup_pin_tif(current_year, pin_14)
    } else {
      lookup_tif(current_year, tax_code_vec)
    }
  }

  source("tif_qmd_functions.R")

  invisible(ptaxsim_db_conn)
}

# Every PIN on record for the year.
all_pins <- function(current_year) {
  dbGetQuery(
    ptaxsim_db_conn,
    "SELECT pin FROM pin WHERE year = ?",
    params = list(current_year)
  )$pin
}

# ---------------------------------------------------------------------------
# Headline
# ---------------------------------------------------------------------------

# Both tax_bill() calls take the whole PIN vector at once and return one row
# per pin/agency, so the totals come from a single grouped sum rather than any
# per-PIN iteration.
hero_headline <- function(pins, current_year = 2024) {
  current_bill <- tax_bill(
    year_vec = current_year,
    pin_vec = pins,
    simplify = FALSE
  )
  counterfactual_bill <- Rem_All(current_year, pins, FALSE)

  current_totals <- current_bill %>%
    group_by(pin) %>%
    summarise(current_total = sum(tax_amt_post_exe, na.rm = TRUE), .groups = "drop")

  counterfactual_totals <- counterfactual_bill %>%
    group_by(pin) %>%
    summarise(counterfactual_total = sum(final_tax, na.rm = TRUE), .groups = "drop")

  current_totals %>%
    inner_join(counterfactual_totals, by = "pin") %>%
    # Positive = the bill would have been lower without TIFs, the expected
    # direction. A property can land the other way, so direction is read off
    # the sign rather than assumed.
    mutate(
      # Integer, not the double current_year arrives as — consumers match this
      # against the year in the filename, and a float year serialises as
      # "2024.0" in JSON.
      year = as.integer(current_year),
      diff = current_total - counterfactual_total,
      amount = as.character(currency(abs(diff), digits = 0)),
      direction = if_else(diff < 0, "higher", "lower")
    ) %>%
    select(pin, year, current_total, counterfactual_total, diff, amount, direction)
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

# Only runs under Rscript; sourcing the file just defines the functions above.
if (sys.nframe() == 0 && !interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  current_year <- if (length(args) >= 1) as.integer(args[1]) else 2024
  out_path <- if (length(args) >= 2) args[2] else hero_output_path(current_year)

  if (is.na(current_year)) {
    cat("Usage: Rscript hero_headline.R [year] [out.parquet]\n")
    quit(status = 1)
  }

  hero_setup()
  on.exit(dbDisconnect(ptaxsim_db_conn), add = TRUE)

  pins <- all_pins(current_year)
  if (length(pins) == 0) {
    stop("No PINs found for year ", current_year, ".", call. = FALSE)
  }
  message(glue("Computing headline figures for {length(pins)} PINs ({current_year})..."))

  res <- hero_headline(pins, current_year)

  # Guard against writing a file whose name and contents disagree — the
  # consumer trusts the year in the filename to pick the file, and the year in
  # the data to confirm it picked right.
  stopifnot(all(res$year == current_year))

  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  arrow::write_parquet(res, out_path)

  message(glue(
    "Wrote {nrow(res)} rows for {current_year} to {out_path}. ",
    "Median: {as.character(currency(median(res$diff), digits = 0))} lower."
  ))
}
