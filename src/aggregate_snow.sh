#! /bin/bash
#SBATCH --qos=priority
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
voi='snowfall'
voi_handle='sf'

# temp folder
TMP="./temp/snow/"
mkdir $TMP

PREPARE_DATA=true

process_file() {
    file="$1"
    TMP="$2"
    filename=$(basename "$file")
    cropped="${TMP}cropped_${filename}"

    cdo -L -s sellonlatbox,4,17,46,57 "$file" "$cropped"
    
    cdo -L -b F64 setmisstonn -daysum "$cropped" "${TMP}germany_daysum_${filename}"

    rm -f "$cropped"
}
export -f process_file

if [ "$PREPARE_DATA" = true ]; then
    rm -rf "${TMP:?}"/*
    find ./data/ERA5-Land_data/ -name $voi"_ERA5-Land_*.nc" | parallel -j "${SLURM_CPUS_PER_TASK:-16}" process_file {} "$TMP"

    # multply by 1000 to convert M to MM
    cdo -L -b F64 -mulc,1000 -mergetime $TMP"germany_daysum_"$voi"_*" $TMP"germany_"$voi"_ERA5-Land.nc"
fi


# prepare population weights
# remap them to 0p1deg grid
# fill nan with zeros
cdo -L setmisstoc,0 -remapsum,$TMP"germany_"$voi"_ERA5-Land.nc" "data/population_data/gpw_v4_mean_population_count_rev11_30_sec_germany.nc" $TMP"pop_mean_weights.nc"
cdo -L setmisstoc,0 -remapsum,$TMP"germany_"$voi"_ERA5-Land.nc" "data/population_data/gpw_v4_population_count_rev11_2000_30_sec.nc" $TMP"pop_2000_weights.nc"


INFILE=$TMP"germany_"$voi"_ERA5-Land.nc"
# area weighted aggregation
netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_PLZ_weights.csv" --method "mean" --var $voi_handle --output "data/results/area_weighted_snowfall_plz_level_era5_land.csv"
netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_KREIS_weights.csv" --method "mean" --var $voi_handle --output "data/results/area_weighted_snowfall_kreis_level_era5_land.csv"

# population weighted aggregation
netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_PLZ_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_weighted_snowfall_plz_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_mean_weights.nc" --secondary_weights_var "Band1"
netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_PLZ_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_2000_weighted_snowfall_plz_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_2000_weights.nc" --secondary_weights_var "Band1"

netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_KREIS_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_weighted_snowfall_kreis_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_mean_weights.nc" --secondary_weights_var "Band1"
netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_KREIS_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_2000_weighted_snowfall_kreis_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_2000_weights.nc" --secondary_weights_var "Band1"

