#!/bin/bash 
#SBATCH --qos=short
#SBATCH --account=impactee
#SBATCH --nodes=1 
#SBATCH --ntasks-per-node=1 
#SBATCH --cpus-per-task=16
#SBATCH --mem=100000
#SBATCH --output=temp/weights-%j.out
#SBATCH --error=temp/weights-%j.err


export PATH="$HOME/.local/bin:$PATH"


# Setup python environment
module purge
module load anaconda
module load cdo
source activate .conda/

# Setup paths
NETCDF_GRID="/p/projects/climate_data_central/reanalysis/ERA5-Land/2m_temperature/2m_temperature_ERA5-Land_20240201-20240229.nc"
SHAPEFILE="data/shapefiles/zip_code_shapes.gpkg"
WEIGHTS_OUTPUT="data/weights/ERA5Land_to_PLZ_weights.csv"
TMP="temp/weights"$SLURM_JOB_ID"/"

mkdir -p $TMP

# Settings for parallel computation
NUMBER_OF_JOBS=16 # Number of parallel jobs set to the number of CPU cores

# transfer to -180 180
# cut file to size of Germany
# fill missing data (over the sea) with nearest neighbours
# !dont change lon-lat-box without recalculating the weights!
cdo -L -setmisstonn \
    -sellonlatbox,5.86769733,15.04115953,47.270114,55.05816517 \
    -sellonlatbox,-180,180,-90,90 \
    $NETCDF_GRID $TMP"germany_era5_land.nc"

NETCDF_GRID=$TMP"germany_era5_land.nc"

# Run the Python script
compute_grid_weights $TMP"germany_era5_land.nc" $SHAPEFILE $WEIGHTS_OUTPUT --yes --n_jobs=$NUMBER_OF_JOBS --gid "plz"

if [ $? -ne 0 ]; then
    echo "compute_grid_weights failed; not validating." >&2
    exit 1
fi

# Check the freshly computed weights before anything downstream consumes them.
# Errors (regions missing entirely, coordinates off the grid, weights out of
# range) exit non-zero and fail the job; cell sums above the ceiling are only
# reported, since overlapping source polygons make them legitimate.
validate_weights "$WEIGHTS_OUTPUT" \
    --netcdf "$NETCDF_GRID" \
    --shapefile "$SHAPEFILE" \
    --gid "plz"
