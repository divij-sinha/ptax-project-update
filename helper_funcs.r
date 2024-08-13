label_d <- label_dollar(prefix = "\\$")
label_k <- label_dollar(prefix = "\\$", suffix = "K", scale = 1e-3)
label_m <- label_dollar(prefix = "\\$", suffix = "M", scale = 1e-6)
label_b <- label_dollar(prefix = "\\$", suffix = "B", scale = 1e-9)
label_p_ltx <- label_percent(accuracy = 0.01, suffix = "\\%")

label_dol_amt <- function(val) {
    if (any(val < 1e3)) {
        return(label_d(val))
    } else if (any(val < 1e6)) {
        return(label_k(val))
    } else if (any(val < 1e9)) {
        return(label_m(val))
    } else {
        return(label_b(val))
    }
}

exe_clean <- function(val) {
    val %>%
        str_replace("exe", "") %>%
        str_replace_all("_", " ") %>%
        str_to_title()
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
    tax_bill_data %>%
        filter(agency_major_type == type_to_filter) %>%
        anti_join(shp_df, by = join_by(agency_num == AGENCY)) %>%
        pull(agency_name)
}


correct_shp_names <- function(shp_bnd) {
    shp_bnd %>%
        st_drop_geometry() %>%
        select(AGENCY, AGENCY_DESC) %>%
        inner_join(tax_bill_data, by = join_by(AGENCY == agency_num)) %>%
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
