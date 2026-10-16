#! /bin/bash
#SBATCH --qos=short
#SBATCH --account=compacts
#SBATCH --nodes=1 
#SBATCH --ntasks-per-node=1 
#SBATCH --cpus-per-task=16
#SBATCH --mem=60000
#SBATCH --output=temp/agg-%j.out
#SBATCH --error=temp/agg-%j.err

module purge
module load anaconda
module load cdo
module load parallel 
source activate .conda/


# variable of interest
voi='total_precipitation'
voi_handle='tp'

PREPARE_DATA=true

# temp folder
TMP="./temp/precip/"
mkdir $TMP

YEAR_START=1950
YEAR_END=2023

process_file() {
    file="$1"
    TMP="$2"
    filename=$(basename "$file")
    cropped="${TMP}cropped_${filename}"

    cdo -L -s sellonlatbox,4,17,46,57 "$file" "$cropped"
    
    # selhour,0 = total precipitation of the prev. day, since the data is cumulative. do shift in the next step (after mergetime)
    cdo -L -b F64 setmisstonn -selhour,0 "$cropped" "${TMP}germany_midnight_${filename}"

    rm -f "$cropped"
}
export -f process_file

if [ "$PREPARE_DATA" = true ]; then
    rm -rf "${TMP:?}"/*
    for year in $(seq $YEAR_START $YEAR_END); do
	find /p/projects/climate_data_central/reanalysis/ERA5-Land/$voi/ \
	     -name "${voi}_ERA5-Land_${year}*"
    done | parallel -j "${SLURM_CPUS_PER_TASK:-16}" process_file {} "$TMP"

    # shift by one day as midnight total rainfall is the total of the prev. day
    # multply by 1000 to convert M to MM
    cdo -L -b F64 -mulc,1000 -shifttime,-1days -mergetime $TMP"germany_midnight_"$voi"_*" $TMP"germany_"$voi"_ERA5-Land.nc"
fi

# calc regional averages

# prepare population weights
# remap them to 0p1deg grid
# fill nan with zeros
cdo -L setmisstoc,0 -remapsum,$TMP"germany_"$voi"_ERA5-Land.nc" "data/population_data/gpw_v4_mean_population_count_rev11_30_sec_germany.nc" $TMP"pop_mean_weights.nc"
cdo -L setmisstoc,0 -remapsum,$TMP"germany_"$voi"_ERA5-Land.nc" "data/population_data/gpw_v4_population_count_rev11_2000_30_sec.nc" $TMP"pop_2000_weights.nc"


INFILE=$TMP"germany_"$voi"_ERA5-Land.nc"
# area weighted aggregation
netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_PLZ_weights.csv" --method "mean" --var $voi_handle --output "data/results/area_weighted_total_precipitation_plz_level_era5_land.csv"
netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_KREIS_weights.csv" --method "mean" --var $voi_handle --output "data/results/area_weighted_total_precipitation_kreis_level_era5_land.csv"

# population weighted aggregation
netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_PLZ_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_weighted_total_precipitation_plz_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_mean_weights.nc" --secondary_weights_var "Band1"
netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_PLZ_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_2000_weighted_total_precipitation_plz_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_2000_weights.nc" --secondary_weights_var "Band1"

netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_KREIS_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_weighted_total_precipitation_kreis_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_mean_weights.nc" --secondary_weights_var "Band1"
netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_KREIS_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_2000_weighted_total_precipitation_kreis_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_2000_weights.nc" --secondary_weights_var "Band1"


