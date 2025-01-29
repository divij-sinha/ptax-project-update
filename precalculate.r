create_tax_bases <- function() {

    # make each year a separate file
    #unique years in pin
    years = dbGetQuery(ptaxsim_db_conn, "select distinct year from pin")$year

    tax_bases_res_com = NULL

    for (year in years) {
        print(glue("Calculating tax bases for {year}"))
        year_bills = NULL
        pin_data = dbGetQuery(ptaxsim_db_conn, glue("
                            SELECT year,
                                pin,
                                tax_code_num,
                                case 
                                when substr(class,1,1) IN ('2','3') then 'res'
                                when class IN ('500', '501', '516', '517', '522', '523', '526','527', '528', '529', '530', '531', '532', '533', '535','590', '591', '592', '597', '599') then 'com' 
                                else 'other' end as type
                            FROM pin
                            where year = {year}"))
                    
        
        #get tax bills for every pin
        pins = pull(pin_data, pin)

        pin_details = lookup_pin(year, pins)

        pin_details = pin_details %>%
            left_join(pin_data, by = c("pin" = "pin", "year" = "year"))

        agency_xwalk = dbGetQuery(ptaxsim_db_conn, glue("select year, agency_num, tax_code_num from tax_code where year = {year}"))

        # join pin_data with agency xwalk using tax_code_num and year
        year_bills = pin_details %>%
            left_join(agency_xwalk, by = c("tax_code_num" = "tax_code_num", "year" = "year")) 


        #summary values
        year_tax_bases_res_com = year_bills %>%
            group_by(year,agency_num, type) %>%
            summarise(eav_total = sum(eav))

        #pivot wider
        year_tax_bases_res_com_wide = pivot_wider(year_tax_bases_res_com, names_from = type, values_from = eav_total)

        if (is.null(tax_bases_res_com)) {
            tax_bases_res_com = year_tax_bases_res_com_wide
        } else {
            tax_bases_res_com = bind_rows(tax_bases_res_com, year_tax_bases_res_com_wide)
        }
    }

    #find share of total for each 
    tax_bases_res_com_share = tax_bases_res_com %>%
        mutate(res_share = res / (res+com+other)) %>%
        select("year","agency_num","res_share" )
    #save file
    saveRDS(tax_bases_res_com_share, "tax_bases_res_com_share.rda")
       
}