# prep-data.R
# Downloads data, builds tract geometries, and generates PMTiles + config.json.
# Requires: arrow, dplyr, tidyr, sf, jsonlite, pmtiles, tigris, purrr, rmapshaper
# Install pmtiles from: install.packages("pmtiles", repos = "https://walkerke.r-universe.dev")
# pmtiles also requires tippecanoe: brew install tippecanoe

library(arrow)
library(dplyr)
library(tidyr)
library(sf)
library(jsonlite)
library(pmtiles)
library(tigris)
library(purrr)

dir.create("data", showWarnings = FALSE)

# =========================================================================
# 1. Download parquet files from GitHub Releases
# =========================================================================

urls <- c(
  "https://github.com/vehicletrends/vehicletrends/releases/download/data-v1/hhi_pt_60.parquet",
  "https://github.com/vehicletrends/vehicletrends/releases/download/data-v1/hhi_vt_60.parquet",
  "https://github.com/vehicletrends/vehicletrends/releases/download/data-v1/hhi_pb_60.parquet"
)

for (url in urls) {
  dest <- file.path("data", basename(url))
  if (!file.exists(dest)) {
    message("Downloading ", basename(url), "...")
    download.file(url, dest, mode = "wb")
  }
}

# Print parquet schemas (to verify column names)
for (f in list.files("data", pattern = "\\.parquet$", full.names = TRUE)) {
  message("\nSchema for ", basename(f), ":")
  ds <- open_dataset(f)
  print(ds$schema)
}

# =========================================================================
# 2. Download and simplify census tract geometries
# =========================================================================

tracts_file <- "data/tracts.rds"

if (!file.exists(tracts_file)) {
  message(
    "\nDownloading census tract geometries (this may take a few minutes)..."
  )
  options(tigris_use_cache = TRUE)

  # 50 states + DC (FIPS codes <= 56)
  state_codes <- unique(fips_codes$state_code)
  state_codes <- state_codes[as.numeric(state_codes) <= 56]

  tracts <- map_dfr(state_codes, \(s) {
    message("  State FIPS: ", s)
    tracts(state = s, cb = TRUE, year = 2020)
  })

  # Keep only GEOID and geometry
  tracts <- tracts |> select(GEOID, geometry)

  saveRDS(tracts, tracts_file)
  message("Saved ", nrow(tracts), " tracts to ", tracts_file)
}

tracts_simple_file <- "data/tracts_simplified.rds"

if (!file.exists(tracts_simple_file)) {
  message("Simplifying geometries...")
  tracts <- readRDS(tracts_file)
  tracts_simple <- rmapshaper::ms_simplify(
    tracts,
    keep = 0.05,
    keep_shapes = TRUE
  )
  saveRDS(tracts_simple, tracts_simple_file)
  message("Saved simplified tracts to ", tracts_simple_file)
}

# =========================================================================
# 3. Pivot HHI data to wide format and generate PMTiles
# =========================================================================

# --- Short codes for compact property names ---
# Column names follow the pattern: {gv}_{gl}_{hv}_{year}
# e.g. pt_cv_mk_2024 = powertrain/cv/make-HHI/2024

gv_codes <- c(
  powertrain = "pt",
  vehicle_type = "vt",
  price_bin = "pb"
)

# Keys = actual values in parquet, values = short codes for PMTiles columns
gl_codes <- list(
  powertrain = c(
    "cv"    = "cv",
    "flex"  = "flex",
    "hev"   = "hev",
    "phev"  = "phev",
    "bev"   = "bev",
    "diesel" = "dsl",
    "fcev"  = "fcev"
  ),
  vehicle_type = c(
    "car"     = "car",
    "cuv"     = "cuv",
    "suv"     = "suv",
    "pickup"  = "pup",
    "minivan" = "van"
  ),
  price_bin = c(
    "$0-$10k"   = "p0",
    "$10k-$20k" = "p10",
    "$20k-$30k" = "p20",
    "$30k-$40k" = "p30",
    "$40k-$50k" = "p40",
    "$50k-$60k" = "p50",
    "$60k-$70k" = "p60",
    "$70k+"     = "p70"
  )
)

# Display labels for the HTML UI (parquet value -> nice label)
gl_labels <- list(
  powertrain = c(
    "cv"     = "Gasoline",
    "flex"   = "Flex Fuel (E85)",
    "hev"    = "Hybrid Electric (HEV)",
    "phev"   = "Plug-In Hybrid Electric (PHEV)",
    "bev"    = "Battery Electric (BEV)",
    "diesel" = "Diesel",
    "fcev"   = "Fuel Cell"
  ),
  vehicle_type = c(
    "car"     = "Car",
    "cuv"     = "CUV",
    "suv"     = "SUV",
    "pickup"  = "Pickup",
    "minivan" = "Minivan"
  ),
  price_bin = c(
    "$0-$10k"   = "$0-$10k",
    "$10k-$20k" = "$10k-$20k",
    "$20k-$30k" = "$20k-$30k",
    "$30k-$40k" = "$30k-$40k",
    "$40k-$50k" = "$40k-$50k",
    "$50k-$60k" = "$50k-$60k",
    "$60k-$70k" = "$60k-$70k",
    "$70k+"     = "$70k+"
  )
)

hv_codes <- c(
  hhi_make = "mk",
  hhi_vehicle_type = "vt",
  hhi_price_bin = "pb"
)

parquet_files <- c(
  powertrain = "data/hhi_pt_60.parquet",
  vehicle_type = "data/hhi_vt_60.parquet",
  price_bin = "data/hhi_pb_60.parquet"
)

group_cols <- c(
  powertrain = "powertrain",
  vehicle_type = "vehicle_type",
  price_bin = "price_bin"
)

# --- Pivot each dataset to wide format ---

pivot_wide <- function(data, gv) {
  group_col <- group_cols[gv]
  gv_code <- gv_codes[gv]
  codes <- gl_codes[[gv]]

  data |>
    filter(.data[[group_col]] %in% names(codes)) |>
    mutate(gl_code = codes[.data[[group_col]]]) |>
    pivot_longer(
      cols = starts_with("hhi_"),
      names_to = "hhi_var",
      values_to = "hhi_val"
    ) |>
    mutate(
      hv_code = hv_codes[hhi_var],
      col_name = paste(gv_code, gl_code, hv_code, listing_year, sep = "_")
    ) |>
    select(GEOID, col_name, hhi_val) |>
    pivot_wider(names_from = col_name, values_from = hhi_val)
}

message("Pivoting parquet data to wide format...")
wide_list <- lapply(names(parquet_files), function(gv) {
  message("  ", gv, "...")
  data <- read_parquet(parquet_files[gv])
  pivot_wide(data, gv)
})

# Merge all wide datasets by GEOID
message("Merging datasets...")
all_hhi <- wide_list[[1]]
for (i in 2:length(wide_list)) {
  all_hhi <- full_join(all_hhi, wide_list[[i]], by = "GEOID")
}

# Round to reduce file size
all_hhi <- all_hhi |>
  mutate(across(where(is.numeric), \(x) round(x, 3)))

message("  ", ncol(all_hhi) - 1, " HHI columns for ", nrow(all_hhi), " tracts")

# --- Join to tract geometries ---

message("Joining to tract geometries...")
tracts <- readRDS("data/tracts_simplified.rds")
tracts_hhi <- tracts |>
  inner_join(all_hhi, by = "GEOID")

message("  ", nrow(tracts_hhi), " tracts with HHI data")

# --- Generate PMTiles via tippecanoe ---

pmtiles_file <- "data/hhi_tracts.pmtiles"

message("Creating PMTiles (this may take a few minutes)...")
pm_create(
  tracts_hhi,
  pmtiles_file,
  layer_name = "tracts",
  min_zoom = 2,
  max_zoom = 12,
  simplification = 2,
  detect_shared_borders = TRUE,
  generate_ids = TRUE,
  no_tile_size_limit = TRUE,
  no_feature_limit = TRUE
)

message("Saved PMTiles to ", pmtiles_file)

# =========================================================================
# 4. Generate config JSON for the HTML viewer
# =========================================================================

# Collect actual years from data
all_years <- sort(unique(read_parquet(parquet_files[1])$listing_year))

config <- list(
  groupVars = lapply(names(gv_codes), function(gv) {
    codes  <- gl_codes[[gv]]
    labels <- gl_labels[[gv]]
    list(
      label = switch(
        gv,
        powertrain = "Powertrain",
        vehicle_type = "Vehicle Type",
        price_bin = "Price Bin"
      ),
      code = unname(gv_codes[gv]),
      levels = lapply(seq_along(codes), function(i) {
        list(label = unname(labels[names(codes)[i]]), code = unname(codes[i]))
      }),
      # Which HHI dimension to exclude (self-referential)
      excludeHhi = switch(gv, vehicle_type = "vt", price_bin = "pb", NULL)
    )
  }),
  hhiVars = list(
    list(label = "Make", code = "mk"),
    list(label = "Vehicle Type", code = "vt"),
    list(label = "Price Bin", code = "pb")
  ),
  years = as.integer(all_years)
)

config_file <- "data/config.json"
write_json(config, config_file, auto_unbox = TRUE, pretty = TRUE)
message("Saved config to ", config_file)

message("\nDone! To view locally, run from the hhi-map directory:")
message("  Rscript serve.R")
