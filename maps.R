get_shp_bnd_cook <- function() {
  read_sf(
    paste0(
      "https://gis.cookcountyil.gov/traditional/rest/services/",
      "plss/MapServer/1/query?outFields=*&where=1%3D1&f=geojson"
    )
  )
}

get_shp_bnd_pin <- function(pin, year) {
  lookup_pin10_geometry(year, substr(pin, 1, 10)) %>%
    st_as_sf(wkt = "geometry", crs = "WGS84")
}

get_shp_agency <- function(agency_num, agency_category_code) {
  read_sf(
    glue(
      "https://gis.cookcountyil.gov/traditional/rest/services/",
      "clerkTaxDistricts/MapServer/{agency_category_code}/query?",
      "where=AGENCY={agency_num}&",
      "outFields=*&outSR=4326&f=json"
    )
  ) %>%
    rename(shape_area = contains("area")) %>%
    rename(AGENCY_DESC = contains("AGENCY_DESC")) %>%
    mutate(AGENCY_DESC = str_to_title(AGENCY_DESC)) %>%
    mutate(AGENCY = as.character(agency_num))
}


get_shp_twn_muni <- function(tax_bill_data_sub) {
  muni_code <- tax_bill_data_sub %>%
    filter(agency_minor_type == "MUNI") %>%
    pull(agency_num)
  twn_code <- tax_bill_data_sub %>%
    filter(agency_minor_type == "TOWNSHIP") %>%
    pull(agency_num)
  twn_name_orig <- tax_bill_current %>%
    filter(agency_minor_type == "TOWNSHIP") %>%
    pull(agency_name)
  twn_name <- twn_name_orig %>%
    str_replace_all("Town", "Town Of")


  if (length(muni_code) > 0) {
    shp_twn_muni <- get_shp_agency(muni_code, 10)
  } else {
    shp_twn_muni <- get_shp_agency(twn_code, 10)
  }
  if ((length(twn_name) > 0) && (length(muni_code) > 0)) {
    shp_twn <- get_shp_twn(twn_name) %>%
      mutate(AGENCY = twn_code) %>%
      mutate(AGENCY_DESC = twn_name_orig)
    shp_twn_muni <- do.call(
      rbind,
      list(select_merge_cols(shp_twn_muni), select_merge_cols(shp_twn))
    )
  }
  return(shp_twn_muni)
}

select_merge_cols <- function(df) {
  df <- df %>%
    select(
      OBJECTID, AGENCY, AGENCY_DESC, created_user, created_date,
      last_edited_user, last_edited_date, ORIGOID, GlobalID, geometry
    )
  return(df)
}


get_shp_twn <- function(agency_name) {
  read_sf(
    glue(
      "https://gis.cookcountyil.gov/traditional/rest/services/",
      "politicalBoundary/MapServer/3/query?",
      "where=NAME_TMP%20%3D%20'{URLencode(agency_name)}'&",
      "outFields=*&outSR=4326&f=json"
    )
  )
}


get_shp_all_schools <- function(agency_list) {
  rbind(
    do.call(rbind, mapply(get_shp_agency, agency_list, 0, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 2, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 6, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 16, SIMPLIFY = F))
  )
}

get_shp_all_others <- function(agency_list) {
  rbind(
    do.call(rbind, mapply(get_shp_agency, agency_list, 1, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 3, SIMPLIFY = F)),
    # do.call(rbind, mapply(get_shp_agency, agency_list, 4, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 5, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 7, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 8, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 9, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 11, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 12, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 13, SIMPLIFY = F)),
    do.call(rbind, mapply(get_shp_agency, agency_list, 14, SIMPLIFY = F))
  )
}

get_shp_tifs <- function(agency_list) {
  rbind(
    do.call(rbind, mapply(get_shp_agency, agency_list, 18, SIMPLIFY = F))
  ) %>%
    mutate(AGENCY_DESC = str_replace_all(AGENCY_DESC, "Tif ", "")) %>%
    mutate(AGENCY_DESC = str_replace_all(AGENCY_DESC, "Rpm1", "Red-Purple Modernisation Phase 1"))
}

# shp_bnd_municipalities <- read_sf(paste0(
#   "https://opendata.arcgis.com/api/v3/datasets/",
#   "534226c6b1034985aca1e14a2eb234af_2/downloads/data?",
#   "format=geojson&spatialRefId=4326&where=1%3D1"
# ))

# shp_bnd_riverside <- shp_bnd_municipalities %>%
#   filter(AGENCY_DESC == "VILLAGE OF RIVERSIDE") %>%
#   select(agency = AGENCY, name = AGENCY_DESC) %>%
#   mutate(agency = "31090000")

# shp_bnd_chicago <- shp_bnd_municipalities %>%
#   filter(AGENCY_DESC == "CITY OF CHICAGO") %>%
#   select(agency = AGENCY, name = AGENCY_DESC)



# shp_bnd_riverside_pins <- read_sf(glue(
#   "https://datacatalog.cookcountyil.gov/resource/",
#   "77tz-riq7.geojson?MUNICIPALITY=Riverside&$limit=100000"
# )) %>%
#   select(pin10, geometry) %>%
#   filter(as.logical(st_intersects(st_centroid(.), shp_bnd_riverside)))

# shp_bnd_elem_dist <- read_sf(paste0(
#   "https://opendata.arcgis.com/api/v3/datasets/",
#   "cbcf6b1c3aaa420d90ccea6af877562b_2/downloads/data?",
#   "format=geojson&spatialRefId=4326&where=1%3D1"
# )) %>%
#   filter(AGENCY_DESCRIPTION == "SCHOOL DISTRICT 96")

# shp_bnd_elem_dist_pins <- read_sf(glue(
#   "https://datacatalog.cookcountyil.gov/resource/",
#   "77tz-riq7.geojson?elemschltaxdist=SCHOOL%20DISTRICT%2096",
#   "&$limit=100000"
# )) %>%
#   filter(!pin10 %in% shp_bnd_riverside_pins$pin10) %>%
#   filter(is.na(as.logical(st_intersects(st_centroid(.), shp_bnd_riverside))))

# shp_bnd_township <- read_sf(paste0(
#   "https://opendata.arcgis.com/api/v3/datasets/",
#   "78fe09c5954e41e19b65a4194eed38c7_3/downloads/data?",
#   "format=geojson&spatialRefId=4326&where=1%3D1"
# )) %>%
#   filter(NAME == "RIVERSIDE")

# shp_bnd_township_pins <- read_sf(glue(
#   "https://datacatalog.cookcountyil.gov/resource/",
#   "77tz-riq7.geojson?politicaltownship=Town%20of%20Riverside",
#   "&$limit=50000"
# )) %>%
#   filter(!pin10 %in% shp_bnd_riverside_pins$pin10) %>%
#   filter(!pin10 %in% shp_bnd_elem_dist_pins$pin10) %>%
#   filter(is.na(as.logical(st_intersects(st_centroid(.), shp_bnd_riverside)))) %>%
#   filter(is.na(as.logical(st_intersects(st_centroid(.), shp_bnd_elem_dist))))

# shp_bnd_hs_dist <- read_sf(paste0(
#   "https://opendata.arcgis.com/api/v3/datasets/",
#   "0657c2831de84e209863eac6c9296081_6/downloads/data?",
#   "format=geojson&spatialRefId=4326&where=1%3D1"
# )) %>%
#   filter(AGENCY_DESC == "RIVERSIDE BROOKFIELD HIGH SCHOOL 208")

# shp_bnd_hs_dist_pins <- read_sf(glue(
#   "https://datacatalog.cookcountyil.gov/resource/",
#   "77tz-riq7.geojson?highschltaxdist=RIVERSIDE%20BROOKFIELD%20HIGH%20SCHOOL%20208",
#   "&$limit=50000"
# )) %>%
#   filter(!pin10 %in% shp_bnd_riverside_pins$pin10) %>%
#   filter(!pin10 %in% shp_bnd_elem_dist_pins$pin10) %>%
#   filter(!pin10 %in% shp_bnd_township_pins$pin10) %>%
#   filter(is.na(as.logical(st_intersects(st_centroid(.), shp_bnd_riverside)))) %>%
#   filter(is.na(as.logical(st_intersects(st_centroid(.), shp_bnd_elem_dist)))) %>%
#   filter(is.na(as.logical(st_intersects(st_centroid(.), shp_bnd_township))))

# shp_bnd_cc_dist <- read_sf(glue(
#   "https://datacatalog.cookcountyil.gov/resource/",
#   "b8q9-dfei.geojson?MAX_AGENCY=TRITON%20COMM%20COLL%20DISTR%20504"
# ))

# shp_bnd_hs_diff <- shp_bnd_hs_dist %>%
#   st_difference(shp_bnd_township)
# shp_bnd_township_diff <- shp_bnd_township %>%
#   st_difference(shp_bnd_elem_dist)
# shp_bnd_elem_diff <- shp_bnd_elem_dist %>%
#   st_difference(shp_bnd_riverside)


# Community College Tax District (0)
# Drainage Tax District (1)
# Elementary School Tax District (2)
# Fire Protection Tax District (3)
# Forest Preserve Holdings Tax District (4)
# Home Equity Assurance Tax District (5)
# High School Tax District (6)
# Library Tax District (7)
# Metropolitan Water Reclamation Tax District (8)
# Mosquito Abatement Tax District (9)
# Municipal Tax District (10)
# Park Tax District (11)
# Sanitary Tax District (12)
# Special Service Tax District (13)
# Street Light Tax District (14)
# Tax Increment Financing Tax District (2018) (15)
# Unit School Tax District (16)
# Chicago Wards 2015 (17)
# Tax Increment Financing Tax District (18)
