label_d <- label_dollar(prefix = "\\$", accuracy = 1)
label_k <- label_dollar(prefix = "\\$", suffix = "K", scale = 1e-3, accuracy = 1)
label_m <- label_dollar(prefix = "\\$", suffix = "M", scale = 1e-6, accuracy = 1)
label_b <- label_dollar(prefix = "\\$", suffix = "B", scale = 1e-9, accuracy = 1)
label_p_ltx <- label_percent(accuracy = 0.01, suffix = "\\%")

label_dol_amt <- function(val) {
    if (any(val < 1e5)) {
        return(label_d(val))
    } else if (any(val < 1e6)) {
        return(label_k(val))
    } else if (any(val < 1e9)) {
        return(label_m(val))
    } else {
        return(label_b(val))
    }
}

change_str <- function(val, tense) {
    change <- if (val > 0) "increase" else "decrease"
    if (tense == "past") {
        change <- paste(change, "d", sep = "")
    } else if (tense == "present") {
        change <- paste(change, "s", sep = "")
    }

    return(change)
}

exe_clean <- function(val) {
    val %>%
        str_replace("exe", "") %>%
        str_replace_all("_", " ") %>%
        str_to_title()
}

process_tax_bill <- function(bill) {
    bill %>%
        mutate(agency_total_eav = as.double(agency_total_eav)) %>%
        mutate(agency_major_type = str_to_title(agency_major_type)) %>%
        mutate(tif_agency_name = str_replace_all(tif_agency_name, "TIF - ", "")) %>%
        mutate(tif_agency_name = str_replace_all(tif_agency_name, "RPM1", "Red-Purple Modernisation Phase 1")) %>%
        mutate(tif_agency_name = str_to_title(tif_agency_name)) %>%
        mutate(agency_name = str_to_title(agency_name)) %>%
        filter(agency_total_ext > 0)
}

map_dist <- function(shp_bnd) {
    main_map <- ggplot() +
        geom_sf(data = cook_roads, color = alpha("#888888", map_road_alpha), lwd = map_road_lwd) +
        geom_sf(
            data = shp_bnd,
            alpha = map_fg_fill_alpha,
            lwd = map_fg_lwd,
            aes(fill = agency_name, color = agency_name),
            show.legend = TRUE
        ) +
        geom_sf(
            data = shp_buf_pin,
            alpha = 1,
            lwd = map_fg_lwd,
            fill = "white", color = "white"
        ) +
        geom_sf(
            data = shp_bnd_pin,
            alpha = map_fg_fill_alpha,
            lwd = map_fg_lwd,
            aes(fill = render_pin14, color = render_pin14),
            show.legend = TRUE
        ) +
        scale_fill_manual(values = map_colors, name = "Extent", drop = FALSE, breaks = map_names) +
        scale_color_manual(values = alpha(map_colors, map_color_alpha), name = "Extent", drop = FALSE, breaks = map_names) +
        theme_void()

    if (st_area(st_make_valid(shp_bnd)) > units::set_units(2.5e8, "m^2")) {
        pin_bbox <- st_bbox(shp_bnd_pin)
        pin_xlim <- c(pin_bbox$xmin - 0.02, pin_bbox$xmax + 0.02)
        pin_ylim <- c(pin_bbox$ymin - 0.015, pin_bbox$ymax + 0.015)
        main_map <- main_map +
            geom_rect(
                aes(xmin = pin_xlim[1], xmax = pin_xlim[2], ymin = pin_ylim[1], ymax = pin_ylim[2]),
                color = map_colors[1], fill = NA, lwd = 1.2
            ) +
            theme(
                legend.position = "bottom",
                plot.margin = unit(c(0, 1, 0, 1), "mm")
            ) +
            guides(fill = guide_legend(nrow = 2, byrow = TRUE))


        inset_map <- main_map +
            geom_sf(
                data = cook_roads,
                color = alpha("#888888", map_road_alpha),
                lwd = map_road_lwd + 0.2
            ) +
            coord_sf(xlim = pin_xlim, ylim = pin_ylim, expand = FALSE) +
            guides(fill = "none", color = "none")


        final_map <- main_map + inset_element(inset_map, 0, 0.40, 0.45, 0.70)
    } else {
        pin_bbox <- st_bbox(shp_bnd)
        pin_xlim <- c(pin_bbox$xmin - 5e-3, pin_bbox$xmax + 5e-3)
        pin_ylim <- c(pin_bbox$ymin - 5e-3, pin_bbox$ymax + 5e-3)
        final_map <- main_map +
            geom_sf(data = cook_roads, color = alpha("#888888", map_road_alpha), lwd = map_road_lwd) +
            coord_sf(xlim = pin_xlim, ylim = pin_ylim, expand = FALSE) +
            theme(
                legend.position = "bottom",
                plot.margin = unit(c(0, 1, 0, 1), "mm")
            ) +
            guides(fill = guide_legend(nrow = 2, byrow = TRUE))
    }
    return(final_map)
}


render_bill <- function(df, group_order) {
    df %>%
        select(
            # c(agency_name, agency_major_type, agency_total_eav, agency_total_ext, agency_tax_rate, tax_amt_pre_exe, tax_amt_post_exe)
            c(agency_name, agency_major_type, agency_total_eav, agency_total_ext, agency_tax_rate, tax_amt_post_exe)
        ) %>%
        # mutate(agency_major_type = str_to_title(agency_major_type)) %>%
        group_by(agency_major_type) %>%
        arrange(desc(tax_amt_post_exe), .by_group = T) %>%
        gt() %>%
        cols_label(
            agency_name = "Tax District",
            agency_total_eav = "Agency Tax Base",
            agency_total_ext = "Agency Tax Levy",
            agency_tax_rate = "Agency Tax Rate",
            # tax_amt_pre_exe = "Tax Pre-exemption",
            tax_amt_post_exe = "Final Tax Owed"
        ) %>%
        row_group_order(group_order) %>%
        fmt(agency_name, fns = str_to_title) %>%
        # fmt_currency(c(tax_amt_pre_exe, tax_amt_post_exe)) %>%
        fmt_currency(c(tax_amt_post_exe)) %>%
        fmt_currency(c(agency_total_eav, agency_total_ext), suffixing = T) %>%
        fmt_percent(agency_tax_rate) %>%
        tab_options(row_group.as_column = T)
}

name_map_colors <- function(map_colors, map_names) {
    if (length(map_colors) >= length(map_names)) {
        return(set_names(map_colors[1:length(map_names)], map_names))
    }
}

render_pin <- function(pin) {
    render10 <- paste(
        substr(pin, 1, 2),
        substr(pin, 3, 4),
        substr(pin, 5, 7),
        substr(pin, 8, 10),
        sep = "-"
    )
    if (nchar(pin) == 14) {
        return(paste(render10, substr(pin, 11, 14), sep = "-"))
    } else {
        return(render10)
    }
}

render_name <- function(name, css_name = NULL) {
    if (is.null(css_name)) {
        css_name <- name
    }
    glue(
        "[**<<str_to_title(name)>>**]",
        '{style="background-color: <<css_colors[css_name]>>;"}',
        .open = "<<", .close = ">>"
    ) %>%
        str_replace_all("Eav", "EAV") %>%
        str_replace_all("Pin", "PIN")
}

render_twn_muni <- function() {
    paste(
        render_name(
            shp_bnd_twn_muni$agency_name %>% as.character()
        ),
        sep = "", collapse = " and "
    )
}


map_inter <- function(shp_bnd_lst) {
    shp_bnd_lst %>%
        st_make_valid() %>%
        st_simplify() %>%
        st_intersection() %>%
        filter(n.overlaps == nrow(shp_bnd_lst)) %>%
        summarise(geometry = st_combine(geometry)) %>%
        st_make_valid() %>%
        st_simplify()
}

get_missing_dis <- function(shp_df, type_to_filter) {
    tax_bill_current %>%
        filter(agency_major_type == type_to_filter) %>%
        anti_join(shp_df, by = join_by(agency_num == AGENCY)) %>%
        pull(agency_name)
}


correct_shp_names <- function(shp_bnd) {
    shp_bnd %>%
        st_drop_geometry() %>%
        select(AGENCY, AGENCY_DESC) %>%
        inner_join(tax_bill_current, by = join_by(AGENCY == agency_num)) %>%
        select(AGENCY, agency_name, AGENCY_DESC) %>%
        mutate(agency_name = str_to_title(agency_name)) %>%
        left_join(x = shp_bnd, y = ., by = join_by(AGENCY, AGENCY_DESC))
}

css_get_colors <- function(vals) {
    mapply(css_get_color, vals)
}

css_get_color <- function(val) {
    if (val %in% names(css_colors)) {
        return(css_colors[val])
    } else if (val %in% tax_bill_data$agency_name) {
        start_val <- tax_bill_data %>%
            filter(agency_name == val) %>%
            pull(agency_num) %>%
            str_sub(1, 2)
        if (start_val == "01") {
            return(css_colors["Cook County"])
        } else if (start_val == "02") {
            twn_name <- tax_bill_data %>%
                filter(agency_minor_type == "TOWNSHIP") %>%
                pull(agency_name)
            return(css_colors[twn_name])
        } else if (start_val == "03") {
            muni_name <- tax_bill_data %>%
                filter(agency_minor_type == "MUNI") %>%
                pull(agency_name)
            return(css_colors[muni_name])
        } else {
            return("#e7e7e7")
        }
    } else {
        return("#FFFFFF")
    }
}


display_two_bills <- function(df1, df2, import_col) {
    df1 <- df1 %>%
        replace(is.na(.), 0) %>%
        mutate(final_tax = tax_amt_post_exe) %>%
        mutate(com_share = 1 - res_share) %>%
        filter(final_tax > 0) %>%
        select(agency_major_type, agency_name, final_tax, agency_total_ext, eav_res_share, com_share) %>%
        group_by(agency_major_type) %>%
        rename(
            final_tax_df1 = final_tax,
            agency_total_ext_df1 = agency_total_ext,
            eav_res_share_df1 = eav_res_share,
            com_share_df1 = com_share
        )

    df2 <- df2 %>%
        replace(is.na(.), 0) %>%
        mutate(final_tax = tax_amt_post_exe) %>%
        mutate(com_share = 1 - res_share) %>%
        filter(final_tax > 0) %>%
        select(agency_major_type, agency_name, final_tax, agency_total_ext, eav_res_share, com_share) %>%
        group_by(agency_major_type) %>%
        rename(
            final_tax_df2 = final_tax,
            agency_total_ext_df2 = agency_total_ext,
            eav_res_share_df2 = eav_res_share,
            com_share_df2 = com_share
        )


    full_join(df1, df2, by = join_by(agency_name == agency_name, agency_major_type == agency_major_type)) %>%
        mutate(change_in_agency_total_ext = (agency_total_ext_df2 - agency_total_ext_df1) / agency_total_ext_df1) %>%
        mutate(change_in_eav_res_share = (eav_res_share_df2 - eav_res_share_df1) / eav_res_share_df1) %>%
        mutate(change_in_com_share = (com_share_df2 - com_share_df1) / com_share_df1) %>%
        mutate(change_in_tax = final_tax_df2 - final_tax_df1) %>%
        mutate(change_in_tax_bar = change_in_tax) %>%
        mutate(eav_res_share_df1 = eav_res_share_df1 * 1e4) %>%
        mutate(eav_res_share_df2 = eav_res_share_df2 * 1e4) %>%
        select(!c(final_tax_df1, final_tax_df2)) %>%
        group_by(agency_major_type) %>%
        gt() %>%
        grand_summary_rows(
            fns = list(
                label = "Total Tax Owed",
                id = "sum",
                fn = "sum"
            ),
            columns = c(change_in_tax),
            fmt = ~ fmt_currency(., rows = "sum")
        ) %>%
        fmt_currency(change_in_tax) %>%
        fmt_currency(c(agency_total_ext_df1, agency_total_ext_df2), suffixing = TRUE) %>%
        fmt_percent(c(change_in_agency_total_ext, change_in_eav_res_share, eav_res_share_df1, eav_res_share_df2, change_in_com_share, com_share_df1, com_share_df2)) %>%
        gtExtras::gt_plt_bar(column = change_in_tax_bar, color = "orange", width = 12) %>%
        tab_style(
            style = list(
                cell_text(weight = "bold")
            ),
            locations = list(
                cells_stub_grand_summary(),
                cells_grand_summary()
            )
        ) %>%
        tab_options(row_group.as_column = T) %>%
        cols_label(
            agency_name = "Tax District",
            change_in_tax = "Change in Tax Amount",
            change_in_tax_bar = "",
            agency_total_ext_df1 = "Tax Levy Prior",
            agency_total_ext_df2 = "Tax Levy Current",
            eav_res_share_df1 = "EAV Residential Share Prior",
            eav_res_share_df2 = "EAV Residential Share Current",
            com_share_df1 = "Commercial Share Prior",
            com_share_df2 = "Commercial Share Current",
            change_in_agency_total_ext = "Change in Tax Levy",
            change_in_eav_res_share = "Change in EAV Residential Share",
            change_in_com_share = "Change in Commercial Share"
        ) %>%
        cols_hide(columns = !(contains(import_col) | c("agency_name", "change_in_tax", "change_in_tax_bar")))
}

display_two_bills_simplified <- function(df1, df2, import_col) {
    df1 <- df1 %>%
        replace(is.na(.), 0) %>%
        mutate(final_tax = tax_amt_post_exe) %>%
        mutate(com_share = 1 - res_share) %>%
        filter(final_tax > 0) %>%
        select(agency_major_type, agency_name, final_tax, agency_total_ext, eav_res_share, com_share) %>%
        group_by(agency_major_type) %>%
        rename(
            final_tax_df1 = final_tax,
            agency_total_ext_df1 = agency_total_ext,
            eav_res_share_df1 = eav_res_share,
            com_share_df1 = com_share
        ) %>%
        group_by(agency_major_type) %>%
        summarise(
            final_tax_group_df1 = sum(final_tax_df1),
        )

    df2 <- df2 %>%
        replace(is.na(.), 0) %>%
        mutate(final_tax = tax_amt_post_exe) %>%
        mutate(com_share = 1 - res_share) %>%
        filter(final_tax > 0) %>%
        select(agency_major_type, agency_name, final_tax, agency_total_ext, eav_res_share, com_share) %>%
        group_by(agency_major_type) %>%
        rename(
            final_tax_df2 = final_tax,
            agency_total_ext_df2 = agency_total_ext,
            eav_res_share_df2 = eav_res_share,
            com_share_df2 = com_share
        ) %>%
        group_by(agency_major_type) %>%
        summarise(
            final_tax_group_df2 = sum(final_tax_df2),
        )


    full_join(df1, df2, by = join_by(agency_major_type == agency_major_type)) %>%
        mutate(change_in_tax = final_tax_group_df2 - final_tax_group_df1) %>%
        mutate(change_in_tax_bar = change_in_tax) %>%
        select(!c(final_tax_group_df1, final_tax_group_df2)) %>%
        group_by(agency_major_type) %>%
        gt() %>%
        grand_summary_rows(
            fns = list(
                label = "Total Tax Owed",
                id = "sum",
                fn = "sum"
            ),
            columns = c(change_in_tax),
            fmt = ~ fmt_currency(., rows = "sum")
        ) %>%
        fmt_currency(change_in_tax) %>%
        gtExtras::gt_plt_bar(column = change_in_tax_bar, color = "orange", width = 12) %>%
        tab_style(
            style = list(
                cell_text(weight = "bold")
            ),
            locations = list(
                cells_stub_grand_summary(),
                cells_grand_summary()
            )
        ) %>%
        tab_options(row_group.as_column = T) %>%
        cols_label(
            agency_major_type = "",
            change_in_tax = "Change in Tax Amount",
            change_in_tax_bar = "",
        ) %>%
        cols_hide(columns = !(contains(import_col) | c("agency_major_type", "change_in_tax", "change_in_tax_bar")))
}
