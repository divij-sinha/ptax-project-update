map_dist_1 <- function(shp_bnd) {
    main_map <- ggplot() +
        geom_sf(data = cook_roads, color = alpha("#888888", map_road_alpha), lwd = map_road_lwd) +
        geom_sf(
            data = shp_bnd,
            alpha = map_fg_fill_alpha,
            lwd = map_fg_lwd,
            aes(fill = agency_name, color = agency_name)
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
            aes(fill = render_pin14, color = render_pin14)
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


map_dist_2 <- function(shp_bnd) {
    main_map <- ggplot() +
        geom_sf(data = cook_roads, color = alpha("#888888", map_road_alpha), lwd = map_road_lwd) +
        geom_sf(
            data = shp_bnd,
            alpha = map_fg_fill_alpha,
            lwd = map_fg_lwd,
            aes(fill = agency_name, color = agency_name)
        ) +
        geom_sf(
            data = shp_buf_pin,
            alpha = 0,
            lwd = map_fg_lwd,
            fill = "white", color = "white"
        ) +
        geom_sf(
            data = shp_bnd_pin,
            alpha = map_fg_fill_alpha,
            lwd = map_fg_lwd,
            aes(fill = render_pin14, color = render_pin14)
        ) +
        scale_fill_manual(values = map_colors, name = "Extent", drop = FALSE, breaks = map_names) +
        scale_color_manual(values = alpha(map_colors, map_color_alpha), name = "Extent", drop = FALSE, breaks = map_names) +
        theme_void()

    if (st_area(st_make_valid(shp_bnd)) > units::set_units(2.5e8, "m^2")) {
        pin_bbox <- st_bbox(shp_bnd_pin)
        pin_xlim <- c(pin_bbox$xmin - 0.015, pin_bbox$xmax + 0.015)
        pin_ylim <- c(pin_bbox$ymin - 0.0112, pin_bbox$ymax + 0.0112)
        main_map <- main_map +
            geom_rect(
                aes(xmin = pin_xlim[1], xmax = pin_xlim[2], ymin = pin_ylim[1], ymax = pin_ylim[2]),
                color = "#88CCEE", fill = NA, lwd = 1.2
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


map_dist_3 <- function(shp_bnd) {
    main_map <- ggplot() +
        geom_sf(data = cook_roads, color = alpha("#888888", map_road_alpha), lwd = map_road_lwd) +
        geom_sf(
            data = shp_bnd,
            alpha = map_fg_fill_alpha,
            lwd = map_fg_lwd,
            aes(fill = agency_name, color = agency_name)
        ) +
        geom_sf(
            data = shp_buf_pin,
            alpha = 0.35,
            lwd = map_fg_lwd,
            fill = "white", color = "white"
        ) +
        geom_sf(
            data = shp_bnd_pin,
            alpha = 1,
            lwd = map_fg_lwd,
            aes(fill = render_pin14, color = render_pin14)
        ) +
        scale_fill_manual(values = map_colors, name = "Extent", drop = FALSE, breaks = map_names) +
        scale_color_manual(values = alpha(map_colors, map_color_alpha), name = "Extent", drop = FALSE, breaks = map_names) +
        theme_void()

    if (st_area(st_make_valid(shp_bnd)) > units::set_units(2e8, "m^2")) {
        pin_bbox <- st_bbox(shp_bnd_pin)
        pin_xlim <- c(pin_bbox$xmin - 0.02, pin_bbox$xmax + 0.02)
        pin_ylim <- c(pin_bbox$ymin - 0.015, pin_bbox$ymax + 0.015)
        main_map <- main_map +
            geom_rect(
                aes(xmin = pin_xlim[1], xmax = pin_xlim[2], ymin = pin_ylim[1], ymax = pin_ylim[2]),
                color = "#88CCEE", fill = NA, lwd = 1.2
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

map_dist_4 <- function(shp_bnd) {
    main_map <- ggplot() +
        geom_sf(data = cook_roads, color = alpha("#888888", map_road_alpha), lwd = map_road_lwd) +
        geom_sf(
            data = shp_bnd,
            alpha = map_fg_fill_alpha,
            lwd = map_fg_lwd,
            aes(fill = agency_name, color = agency_name)
        ) +
        geom_sf(
            data = shp_buf_pin,
            alpha = 0.35,
            lwd = 0.6,
            fill = "white", color = "white"
        ) +
        geom_sf(
            data = shp_bnd_pin,
            alpha = 1,
            lwd = map_fg_lwd,
            aes(fill = render_pin14, color = render_pin14)
        ) +
        scale_fill_manual(values = map_colors, name = "Extent", drop = FALSE, breaks = map_names) +
        scale_color_manual(values = alpha(map_colors, map_color_alpha), name = "Extent", drop = FALSE, breaks = map_names) +
        theme_void()

    if (st_area(st_make_valid(shp_bnd)) > units::set_units(2e8, "m^2")) {
        pin_bbox <- st_bbox(shp_bnd_pin)
        pin_xlim <- c(pin_bbox$xmin - 0.01, pin_bbox$xmax + 0.01)
        pin_ylim <- c(pin_bbox$ymin - 0.0075, pin_bbox$ymax + 0.0075)
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
            coord_sf(xlim = pin_xlim, ylim = pin_ylim, expand = FALSE) +
            guides(fill = "none", color = "none")


        final_map <- main_map +
            geom_sf(
                data = cook_roads,
                color = alpha("#888888", map_road_alpha + 0.2),
                lwd = map_road_lwd
            ) +
            geom_rect(
                aes(xmin = pin_xlim[1], xmax = pin_xlim[2], ymin = pin_ylim[1], ymax = pin_ylim[2]),
                color = map_colors[1], fill = map_colors[1], lwd = 1.2
            ) + inset_element(inset_map, 0, 0.40, 0.45, 0.70)
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
