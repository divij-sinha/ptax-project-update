Rem_One <- function(current_year, pin_14, to_rem) {
  cook_pins <- DBI::dbGetQuery(
    ptaxsim_db_conn,
    glue_sql("
    SELECT pin, class
    FROM pin
    WHERE year = ({current_year})
    ",
             .con = ptaxsim_db_conn))
  
  tif_dt_cntr <- lookup_tif_wrapper(current_year, cook_pins$pin, lookup_tax_code(current_year, cook_pins$pin)) %>%
    mutate(tif_share = ifelse(agency_num == to_rem, 0, tif_share))
  
  tif_agency_cntr_updated <- readRDS("data/Agency_Sine_Unus_TIF_claude_2024.rds") %>%
    filter(TIF == to_rem) %>%
    select(-TIF) %>%
    setDT(key = c("year", "tax_code", "agency_num"))
  
  if(current_year >= 2024){
    tif_bill_cntr <- tax_bill(
      year_vec = current_year,
      pin_vec = pin_14,
      agency_dt = tif_agency_cntr_updated,
      pin_tif_dt = tif_dt_cntr
    )
  } else {
    tif_bill_cntr <- tax_bill(
      year_vec = current_year,
      pin_vec = pin_14,
      agency_dt = tif_agency_cntr_updated,
      tif_dt = tif_dt_cntr
    )
  }
}

Rem_All <- function(current_year, pin_14, levy_change) {
  tif_agency_cntr_updated <- if(levy_change) {
    readRDS("data/All_Agencies_cntr_levy_claude_2024.RDS")
  } else if (T) { 
    readRDS("data/All_Agencies_cntr_sine_levy_claude_2024.RDS")
  }
  
  tif_dt_cntr <- readRDS("data/All_TIF_cntr_claude_2024.RDS")
  if(current_year >= 2024){
    tif_bill_cntr <- tax_bill(
      year_vec = current_year,
      pin_vec = pin_14,
      agency_dt = tif_agency_cntr_updated,
      pin_tif_dt = tif_dt_cntr
    )
  } else {
    tif_bill_cntr <- tax_bill(
      year_vec = current_year,
      pin_vec = pin_14,
      agency_dt = tif_agency_cntr_updated,
      tif_dt = tif_dt_cntr
    )
  }
}

TIF_Remover <- function(current_year, pin_14, to_rem, levy_change) {
  tif_dists <- DBI::dbGetQuery(
    ptaxsim_db_conn,
    glue::glue_sql("
    SELECT *
    FROM tif_distribution
    WHERE year = ({current_year})
  ",
                   .con = ptaxsim_db_conn)
  )%>%
    filter(agency_num %in% to_rem)
  
  tif_pins_vec <- DBI::dbGetQuery(
    ptaxsim_db_conn,
    glue::glue_sql("
    SELECT DISTINCT pin
    FROM pin
    WHERE tax_code_num IN ({unique(tif_dists$tax_code_num)*})
    AND year = ({current_year})
  ",
                   .con = ptaxsim_db_conn
    )) %>%
    pull(pin)
  
  tif_pins_dt <- lookup_pin(current_year, pin = tif_pins_vec) %>%
    mutate(tax_code_num = lookup_tax_code(year, pin))
  
  cook_tax_codes <- DBI::dbGetQuery(
    ptaxsim_db_conn,
    glue_sql("
    SELECT tax_code_num
    FROM tax_code
    WHERE agency_num = '010010000'
    AND year = ({current_year})
    ",
             .con = ptaxsim_db_conn
    ))
  
  cook_pins <- DBI::dbGetQuery(
    ptaxsim_db_conn,
    glue_sql("
    SELECT pin, class
    FROM pin
    WHERE year = ({current_year})
    ",
             .con = ptaxsim_db_conn
    ))
  
  tif_dt_cntr <- lookup_tif_wrapper(current_year, cook_pins$pin, lookup_tax_code(current_year, cook_pins$pin)) %>%
    mutate(tif_share = ifelse(agency_num == to_rem, 0, tif_share))
  
  tif_bills <- tax_bill(
    current_year,
    pin_vec = tif_pins_vec)
  
  tif_agency_cntr <- lookup_agency(
    current_year,
    lookup_tax_code(current_year, cook_pins$pin)
  )
  
  tif_agency_amt_to_add <- readRDS("data/TIF_Deltas_claude_2024.rds") %>%
    data.table() %>%
    filter(TIF %in% to_rem)
  
  tif_agency_cntr_updated  <- if(levy_change) {tif_agency_cntr %>%
      #slice_sample(n=100)%>%
      left_join(tif_agency_amt_to_add, by = "agency_num") %>%
      rowwise() %>%
      mutate(agency_total_eav = sum(agency_total_eav, amt_to_tif, na.rm = TRUE)) %>%
      select(-amt_to_tif) %>%
      rowwise() %>%
      mutate(agency_total_ext = sum(agency_total_ext, new_ext, na.rm = TRUE)) %>%
      select(-new_ext) %>%
      select(-TIF) %>%
      setDT(key = c("year", "tax_code", "agency_num"))
    
  } else if (T) {tif_agency_cntr %>%
      #slice_sample(n=100)%>%
      left_join(tif_agency_amt_to_add %>%
                  select(agency_num, amt_to_tif )
                , by = "agency_num") %>%
      rowwise() %>%
      mutate(agency_total_eav = sum(agency_total_eav, amt_to_tif, na.rm = TRUE)) %>%
      select(-amt_to_tif) %>%
      setDT(key = c("year", "tax_code", "agency_num"))
  }
  if(current_year >= 2024){
    tif_bill_cntr <- tax_bill(
      year_vec = current_year,
      pin_vec = pin_14,
      agency_dt = tif_agency_cntr_updated,
      pin_tif_dt = tif_dt_cntr
    )
  } else {
    tif_bill_cntr <- tax_bill(
      year_vec = current_year,
      pin_vec = pin_14,
      agency_dt = tif_agency_cntr_updated,
      tif_dt = tif_dt_cntr
    )
  }
}