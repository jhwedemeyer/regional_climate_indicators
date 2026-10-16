# Regional Aggregation of Climate Indicators

A showcase pipeline for deriving regional climate indicators for Germany from
gridded reanalysis and observational products, and aggregating them to
several administrative/statistical scales using both area- and
population-weighting, via
[`netcdf2region`](https://github.com/jhwedemeyer/netcdf2region) — a CLI
toolkit I wrote that computes grid-to-region overlap weights and uses them to
reduce gridded NetCDF time series to one weighted value per region per
timestep.

The procedures shown here are similar to those used, for example, in the following studies:

- Wedemeyer, J.H., Kotz, M., Stechemesser, A. & Wenz, L. Empirical evidence
  of climate-induced migration at global scales (under review).
- Lochner, J.H., Stechemesser, A. & Wenz, L. [Climate summits and protests
  have a strong impact on climate change media coverage in Germany.](
    https://www.nature.com/articles/s43247-024-01434-3)
  *Communications Earth & Environment* (2024).


## What this does

Climate datasets (ERA5-Land, E-OBS) are provided on regular lon/lat grids.
Most downstream analyses, however, need values per administrative unit
(e.g. per postal code or district), not per grid cell. This project:

1. **Downloads and crops** raw reanalysis variables to a Germany bounding box.
2. **Derives climate indicators** (temperatures, precipitation, snowfall,
   relative humidity, heat stress, extreme heat events) at daily resolution.
3. **Computes grid-to-region overlap weights** between the climate grids and
   three German region definitions (postal codes, districts, NUTS-3), using the
   `netcdf2region` package.
4. **Aggregates** each indicator to each region with
   `netcdf2region`, both as a
   simple area-weighted spatial mean and as a population-weighted mean,
   producing one CSV time series per region per indicator.

All heavy steps are written as SLURM batch jobs (`#SBATCH` headers) intended
for a HPC cluster, parallelized with GNU `parallel` and `cdo` (Climate Data
Operators), and orchestrated via a `Makefile`.

## Data sources

- **[ERA5-Land](https://cds.climate.copernicus.eu/)** — hourly reanalysis
  (2m temperature, 2m dewpoint temperature, total precipitation, snowfall).
  No ERA5-Land data is shipped with this repo; examples for downloading it
  via the Copernicus Climate Data Store API are provided in
  `data/ERA5-Land_data/download_*.py`.
- **[E-OBS](https://surfobs.climate.copernicus.eu/dataaccess/access_eobs.php)** —
  daily gridded European observational dataset (0.1° resolution) for mean/min/max
  temperature, precipitation, and humidity (`tg`, `tn`, `tx`, `rr`, `hu`).
- **[GPWv4](https://sedac.ciesin.columbia.edu/data/collection/gpw-v4)** — Gridded
  Population of the World, population counts at 30 arc-second resolution,
  used to build population-weighting grids (`data/population_data/compute_mean_population.sh`).
  Two weights are used: a long-term mean population grid and a fixed-year
  (2000) population grid.
- **Region geometries** (`data/shapefiles/`) — German postal code areas
  (`zip_code_shapes.gpkg`), districts/*Kreise* (`kreis_shapes.gpkg`), and
  NUTS-3 regions (`nuts3_germany.gpkg`).

## Regional scales

| Scale | Shapefile | ID field |
|---|---|---|
| Postal code (PLZ) | `zip_code_shapes.gpkg` | `plz` |
| District (Kreis) | `kreis_shapes.gpkg` | `NUTS` |
| NUTS-3 | `nuts3_germany.gpkg` | `NUTS_ID` |

## Pipeline

### 1. Grid-to-region weights

`src/gen_{plz,kreis,nuts3}_weights_for_{e_obs,era5_land}.sh` compute the
fractional overlap of each grid cell with each region polygon for every
combination of source grid (E-OBS, ERA5-Land) and target region (PLZ, Kreis,
NUTS-3), using the custom `compute_grid_weights` CLI, and validate the result
with `validate_weights` (checks for missing regions, off-grid coordinates,
and out-of-range weights). Weights are cached as CSVs in `data/weights/` so
they only need to be recomputed if the grid or shapefiles change.

Run all six jobs with:

```bash
make submit_weights
```

### 2. Indicator generation and aggregation

Each `src/aggregate_*.sh` script follows the same shape:

1. Crop the raw grid to Germany (`cdo sellonlatbox`) and interpolate missing cells, i.e. coastal
   areas (those missing in ERA5-Land), by setting them to nearest-neighbour cells (`cdo setmisstonn`).
2. Derive one or more daily indicators with `cdo`.
3. Build population-weighting grids on the fly by remapping the GPW grid
   onto the indicator's grid (`cdo remapsum`).
4. Aggregate to each region with the custom `netcdf2region` CLI, once with
   plain area weights and once with population weights (mean and 2000-baseline),
   writing one CSV per region scale under `data/results/`.

| Script | Indicator(s) | Source |
|---|---|---|
| `aggregate_temperature.sh` | daily mean/max/min 2m temperature (°C) | ERA5-Land |
| `aggregate_precip.sh` | total daily precipitation (mm) | ERA5-Land |
| `aggregate_snow.sh` | total daily snowfall (mm) | ERA5-Land |
| `aggregate_relhum.sh` | vapor pressure, saturation vapor pressure, relative humidity (exact + approximation), simplified WBGT heat-stress index | ERA5-Land |
| `aggregate_extreme_heat.sh` | heatwave-condition days: daily max temp exceeding both a day-of-year-specific 98th percentile (1961–1990 baseline, ±15-day window) **and** an absolute 28°C threshold | ERA5-Land |
| `aggregate_eobs_data.sh` | daily mean/min/max temperature, precipitation, humidity (array job, one task per variable) | E-OBS |

Run all aggregation jobs with:

```bash
make aggregate
```

### 3. Outputs

Results land in `data/results/` as one CSV time series per
`{weighting}_{indicator}_{region level}_{source}.csv`, e.g.:

- `area_weighted_daymean_temperature_plz_level_era5_land.csv`
- `pop_weighted_vapor_pressure_1950-2022_kreis_level_era5_land.csv`
- `pop_2000_weighted_rr_plz_level_eobs.csv`

Weighting variants per indicator/region combination:
- **`area_weighted_*`** — simple area-weighted spatial mean over the region.
- **`pop_weighted_*`** — weighted by the multi-year mean population grid.
- **`pop_2000_weighted_*`** — weighted by the year-2000 population grid (fixed
  baseline, useful for isolating climate trends from population shifts).

## Tooling

- **[`cdo`](https://code.mpimet.mpg.de/projects/cdo)** — all grid cropping,
  resampling, derived-variable math (`cdo expr`), and regridding for
  population weights.
- **GNU `parallel`** — fans out per-file/per-job work across the SLURM
  allocation's CPUs.
- **[`netcdf2region`](https://github.com/jhwedemeyer/netcdf2region) 0.1.9**
  — provides:
  - `compute_grid_weights` / `validate_weights`, which compute the
    area-overlap weights between a NetCDF grid and a vector shapefile, and
    sanity-check them before use.
  - the main `netcdf2region` CLI, which reduces a gridded NetCDF time series
    to one weighted value per region per timestep, given a precomputed
    grid-to-region weights CSV; optionally multiplies in a secondary
    (population) weights grid for the `pop_weighted_*` /
    `pop_2000_weighted_*` outputs.

## Running on a SLURM cluster

Every script assumes a module system providing `anaconda`, `cdo`, and
`parallel`, plus a project-local conda environment at `.conda/`
(`source activate .conda/`). Submit the pipeline stages via the `Makefile`:

```bash
make submit_weights   # compute + validate all grid-to-region weights
make aggregate         # derive indicators and aggregate to all region levels
```

`submit_weights` must complete (and produce the CSVs in `data/weights/`)
before `aggregate` is run, since every aggregation step consumes the
precomputed weights.
