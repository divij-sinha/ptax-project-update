# The journalists want to share a brief fact which can be directly looked up


current_year <- 2024
db_path <- "data/ptaxsim-2024.0.0-alpha.2.db"
ptaxsim_db_conn <- dbConnect(SQLite(), db_path, flags = RSQLite::SQLITE_RO)

cook_pins <- DBI::dbGetQuery(
  ptaxsim_db_conn,
  glue_sql("
    SELECT pin, class
    FROM pin
    WHERE year = ({current_year})
    ", .con = ptaxsim_db_conn))

tif_agency_cntr_updated <- readRDS("data/All_Agencies_cntr_sine_levy_claude_2024.RDS")
tif_dt_cntr <- readRDS("data/All_TIF_cntr_claude_2024.RDS")

tif_bill_cntr <- tax_bill(
  year_vec = current_year,
  pin_vec = cook_pins$pin,
  agency_dt = tif_agency_cntr_updated,
  pin_tif_dt = tif_dt_cntr
)

original_bills <- tax_bill(
  year_vec = current_year,
  pin_vec = cook_pins$pin
)


#by pin
bill_deltas <- tif_bill_cntr %>% group_by(pin) %>% summarize(final_tax = sum(final_tax)) %>%
  left_join(
    original_bills %>% group_by(pin) %>% summarize(original_tax = sum(final_tax))
  ) %>%
  mutate(
    fact = str_glue("If all TIFs are removed and levies are held constant, PIN {pin}'s tax bill in 2024 would be ",
                    "{scales::dollar(original_tax - final_tax)} less (from {scales::dollar(original_tax)} to {scales::dollar(final_tax)}).")
  )

#by municipality (or township for Cicero/Maine/Lemont/Orland)
muni_ls <- tif_bill_cntr %>% filter(agency_minor_type == 'MUNI') %>% select(pin, muni_name = agency_name)
town_ls <- tif_bill_cntr %>% filter(agency_minor_type == 'TOWNSHIP') %>% select(pin, muni_name = agency_name)
muni_ls <- muni_ls %>% bind_rows(town_ls %>% filter(!pin %in% muni_ls$pin))


muni_deltas <- tif_bill_cntr %>% left_join(muni_ls) %>% group_by(muni_name) %>% mutate(muni_name = replace_na(muni_name, 'Unincorporated')) %>%
  summarize(final_tax = sum(final_tax)) %>%
  left_join(
    original_bills %>% left_join(muni_ls) %>% group_by(muni_name) %>% summarize(original_tax = sum(final_tax))
  ) %>%
  mutate(
    fact = str_glue("If all TIFs are removed and levies are held constant, taxpayers in the {stringr::str_to_title(muni_name)} in 2024 would pay ",
                    "{scales::dollar(original_tax - final_tax)} less (from {scales::dollar(original_tax)} to {scales::dollar(final_tax)}).")
  )

bill_deltas %>% write_csv('data/pin_facts.csv')
muni_deltas %>% write_csv('data/muni_facts.csv')

