# create_tif_rds.R
#
# Produces five pre-computed RDS files for ptaxsim_explainer_tif.Rmd.
# Output files are suffixed with "_claude" so they never overwrite existing ones.
# After verifying the output, rename/copy to the canonical names if desired:
#
#   data/All_TIF_cntr_claude.RDS               → data/All_TIF_cntr.RDS
#   data/All_Agencies_cntr_sine_levy_claude.RDS → data/All_Agencies_cntr_sine_levy.RDS
#   data/All_Agencies_cntr_levy_claude.RDS      → data/All_Agencies_cntr_levy.RDS
#   data/Agency_Sine_Unus_TIF_claude.rds        → data/Agency_Sine_Unus_TIF.rds
#   data/TIF_Deltas_claude.rds                  → data/TIF_Deltas.rds
#
# Runtime: long — runs full-county lookups and loops over every TIF district.
# Adjust `current_year` and `db_path` before running.

library(DBI)
library(RSQLite)
library(data.table)
library(dplyr)
library(ptaxsim)

# ── Config ────────────────────────────────────────────────────────────────────

current_year <- 2024
db_path      <- "data/ptaxsim-2024.0.0-alpha.2.db"
out_dir      <- "data"

# ── Connect ───────────────────────────────────────────────────────────────────

ptaxsim_db_conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)

# ── Shared county-wide lookups ────────────────────────────────────────────────

message("Fetching all Cook County PINs...")
cook_pins <- DBI::dbGetQuery(
  ptaxsim_db_conn,
  glue::glue_sql(
    "SELECT pin FROM pin WHERE year = ({current_year})",
    .con = ptaxsim_db_conn
  )
)$pin

message("Looking up tax codes for all PINs...")
cook_tax_codes <- lookup_tax_code(current_year, cook_pins)

message("Building agency_dt for all Cook County tax codes...")
agency_dt_all <- lookup_agency(current_year, cook_tax_codes)

message("Fetching all TIF distributions...")
tif_dist_all <- DBI::dbGetQuery(
  ptaxsim_db_conn,
  glue::glue_sql(
    "SELECT * FROM tif_distribution WHERE year = ({current_year})",
    .con = ptaxsim_db_conn
  )
)

# All TIF agency_nums active this year
all_tif_nums <- unique(tif_dist_all$agency_num)
message(glue::glue("Found {length(all_tif_nums)} active TIF districts for {current_year}."))

# ── Helper: EAV increment for a set of TIF distributions ─────────────────────
# Returns a data.frame with columns: agency_num, amt_to_tif
# (the frozen EAV that would flow back to each taxing agency)

compute_eav_deltas <- function(tif_dists) {
  # Pins inside these TIF tax codes
  tif_pins_vec <- DBI::dbGetQuery(
    ptaxsim_db_conn,
    glue::glue_sql(
      "SELECT DISTINCT pin FROM pin
       WHERE tax_code_num IN ({unique(tif_dists$tax_code_num)*})
       AND year = ({current_year})",
      .con = ptaxsim_db_conn
    )
  )$pin

  if (length(tif_pins_vec) == 0) return(NULL)

  tif_pins_dt <- lookup_pin(current_year, pin = tif_pins_vec) %>%
    mutate(tax_code = lookup_tax_code(year, pin))

  # EAV increment per tax code = current total EAV - frozen EAV (floor 0)
  tif_codes_summ <- tif_pins_dt %>%
    group_by(tax_code) %>%
    summarise(total_eav = sum(eav), .groups = "drop") %>%
    left_join(
      tif_dists %>% select(tax_code = tax_code_num, tax_code_frozen_eav),
      by = "tax_code"
    ) %>%
    mutate(amt_to_tif = pmax(total_eav - tax_code_frozen_eav, 0))

  # Sum EAV increment per agency (agencies span multiple tax codes).
  # Only keep agencies that actually overlap with these TIF tax codes.
  agency_dt_all %>%
    filter(tax_code %in% tif_codes_summ$tax_code) %>%
    group_by(agency_num) %>%
    left_join(tif_codes_summ %>% select(tax_code, amt_to_tif), by = "tax_code") %>%
    summarise(amt_to_tif = sum(amt_to_tif, na.rm = TRUE), .groups = "drop") %>%
    filter(amt_to_tif >= 0)
}

# ── Helper: levy delta for a set of TIF distributions ────────────────────────
# Returns a data.frame with columns: agency_num, new_ext
# (the additional levy each agency would collect, proportional to its bill share)

compute_levy_deltas <- function(tif_dists) {
  tif_pins_vec <- DBI::dbGetQuery(
    ptaxsim_db_conn,
    glue::glue_sql(
      "SELECT DISTINCT pin FROM pin
       WHERE tax_code_num IN ({unique(tif_dists$tax_code_num)*})
       AND year = ({current_year})",
      .con = ptaxsim_db_conn
    )
  )$pin

  if (length(tif_pins_vec) == 0) return(NULL)

  tif_bills <- tax_bill(current_year, pin_vec = tif_pins_vec)

  total_tif_revenue <- sum(tif_dists$tax_code_revenue, na.rm = TRUE)

  tif_bills %>%
    filter(agency_minor_type != "TIF") %>%
    group_by(agency_num) %>%
    summarise(bill_share = sum(final_tax), .groups = "drop") %>%
    mutate(
      bill_share = bill_share / sum(bill_share),
      new_ext    = bill_share * total_tif_revenue
    ) %>%
    select(agency_num, new_ext)
}

# ── 1. All_TIF_cntr.RDS ───────────────────────────────────────────────────────
# tif_dt with every tif_share set to 0 (no TIF district collects increment)
#now this is by pin in 2024

message("Building All_TIF_cntr_claude.RDS...")

lookup_tif_wrapper <- function(current_year, pin_14, tax_code_vec){
  #in 2024 ptaxsim updates the lookup_tif to be lookup_pin_tif
  #for 2023 and prior year lookups, the legacy lookup_tif should be used
  #this is hacky but then everytime we call lookup_tif we need to supply both pin_14 and tax_code_vec
  
  if(current_year >= 2024){
    return(lookup_pin_tif(current_year, pin_14))
  } else {
    return(lookup_tif(current_year, tax_code_vec))
  }
}

all_tif_cntr <- lookup_tif_wrapper(current_year, cook_pins, cook_tax_codes) %>%
  mutate(tif_share = 0) 

if(current_year >= 2024){
  all_tif_cntr <- all_tif_cntr %>%
    setDT(key = c("year", "pin", "agency_num"))
} else {
  all_tif_cntr <- all_tif_cntr %>%
    setDT(key = c("year", "tax_code", "agency_num"))
}



saveRDS(all_tif_cntr, file.path(out_dir, "All_TIF_cntr_claude_2024.RDS"))
message("  Saved All_TIF_cntr_claude.RDS")

# ── 2 & 3. All_Agencies_cntr_sine_levy / All_Agencies_cntr_levy ───────────────
# agency_dt for removing ALL TIFs simultaneously

message("Computing EAV deltas for all-TIF removal...")
eav_deltas_all <- compute_eav_deltas(tif_dist_all)

# sine_levy: EAV restored, levy unchanged
message("Building All_Agencies_cntr_sine_levy_claude.RDS...")
all_agencies_sine_levy <- agency_dt_all %>%
  left_join(eav_deltas_all, by = "agency_num") %>%
  mutate(
    amt_to_tif      = replace(amt_to_tif, is.na(amt_to_tif), 0),
    agency_total_eav = agency_total_eav + amt_to_tif
  ) %>%
  select(-amt_to_tif) %>%
  setDT(key = c("year", "tax_code", "agency_num"))

saveRDS(all_agencies_sine_levy, file.path(out_dir, "All_Agencies_cntr_sine_levy_claude_2024.RDS"))
message("  Saved All_Agencies_cntr_sine_levy_claude_2024.RDS")

# levy: EAV restored AND levy raised proportionally
message("Computing levy deltas for all-TIF removal...")
levy_deltas_all <- compute_levy_deltas(tif_dist_all)

message("Building All_Agencies_cntr_levy_claude.RDS...")
all_agencies_levy <- agency_dt_all %>%
  left_join(eav_deltas_all, by = "agency_num") %>%
  left_join(levy_deltas_all, by = "agency_num") %>%
  mutate(
    amt_to_tif       = replace(amt_to_tif, is.na(amt_to_tif), 0),
    new_ext          = replace(new_ext, is.na(new_ext), 0),
    agency_total_eav = agency_total_eav + amt_to_tif,
    agency_total_ext = agency_total_ext + new_ext
  ) %>%
  select(-amt_to_tif, -new_ext) %>%
  setDT(key = c("year", "tax_code", "agency_num"))

saveRDS(all_agencies_levy, file.path(out_dir, "All_Agencies_cntr_levy_claude_2024.RDS"))
message("  Saved All_Agencies_cntr_levy_claude_2024.RDS")

# ── 4 & 5. Agency_Sine_Unus_TIF.rds + TIF_Deltas.rds ────────────────────────
# Loop over every TIF, compute per-TIF deltas, accumulate into two files.

message(glue::glue("Looping over {length(all_tif_nums)} TIFs for Agency_Sine_Unus_TIF / TIF_Deltas..."))

agency_sine_unus_list <- vector("list", length(all_tif_nums))
tif_deltas_list       <- vector("list", length(all_tif_nums))

for (i in seq_along(all_tif_nums)) {
  tif_num <- all_tif_nums[i]
  if (i %% 10 == 0) message(glue::glue("  {i}/{length(all_tif_nums)}: {tif_num}"))

  tif_dists_one <- tif_dist_all %>% filter(agency_num == tif_num)

  eav_deltas_one  <- compute_eav_deltas(tif_dists_one)
  levy_deltas_one <- compute_levy_deltas(tif_dists_one)

  if (is.null(eav_deltas_one)) next

  # Agency_Sine_Unus_TIF: EAV restored, levies flat, tagged with TIF column
  agency_one <- agency_dt_all %>%
    left_join(eav_deltas_one, by = "agency_num") %>%
    mutate(
      amt_to_tif       = replace(amt_to_tif, is.na(amt_to_tif), 0),
      agency_total_eav = agency_total_eav + amt_to_tif
    ) %>%
    select(-amt_to_tif) %>%
    mutate(TIF = tif_num)

  agency_sine_unus_list[[i]] <- agency_one

  # TIF_Deltas: the per-agency delta row for this TIF
  if (!is.null(levy_deltas_one)) {
    delta_one <- eav_deltas_one %>%
      left_join(levy_deltas_one, by = "agency_num") %>%
      mutate(
        new_ext = replace(new_ext, is.na(new_ext), 0),
        TIF     = tif_num
      )
    tif_deltas_list[[i]] <- delta_one
  } else {
    tif_deltas_list[[i]] <- eav_deltas_one %>%
      mutate(new_ext = 0, TIF = tif_num)
  }
}

message("Binding and saving Agency_Sine_Unus_TIF_claude.rds...")
agency_sine_unus <- bind_rows(agency_sine_unus_list) %>%
  setDT(key = c("year", "tax_code", "agency_num"))
saveRDS(agency_sine_unus, file.path(out_dir, "Agency_Sine_Unus_TIF_claude_2024.rds"))
message("  Saved Agency_Sine_Unus_TIF_claude_2024.rds")

message("Binding and saving TIF_Deltas_claude.rds...")
tif_deltas <- bind_rows(tif_deltas_list) %>%
  setDT()
saveRDS(tif_deltas, file.path(out_dir, "TIF_Deltas_claude_2024.rds"))
message("  Saved TIF_Deltas_claude_2024.rds")

# ── Cleanup ───────────────────────────────────────────────────────────────────

DBI::dbDisconnect(ptaxsim_db_conn)
message("Done.")

