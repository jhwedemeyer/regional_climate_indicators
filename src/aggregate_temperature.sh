#! /bin/bash
#SBATCH --qos=short
#SBATCH --account=compacts
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=200000
#SBATCH --output=temp/agg-%j.out
#SBATCH --error=temp/agg-%j.err

module purge
module load anaconda
module load cdo
module load parallel 
source activate .conda/

PREPARE_DATA=true
TMP="./temp/agg-temperatures/"
mkdir -p "$TMP"


YEAR_START=1950
YEAR_END=2023

process_file() {
    file="$1"
    TMP="$2"
    filename=$(basename "$file")
    cropped="${TMP}cropped_${filename}"

    cdo -L -s sellonlatbox,4,17,46,57 "$file" "$cropped"

    cdo -L -s setmisstonn -daymean "$cropped" "${TMP}germany_daymean_${filename}"
    cdo -L -s setmisstonn -daymax  "$cropped" "${TMP}germany_daymax_${filename}"
    cdo -L -s setmisstonn -daymin  "$cropped" "${TMP}germany_daymin_${filename}"

    rm -f "$cropped"
}
export -f process_file

if [ "$PREPARE_DATA" = true ]; then
    rm -rf "${TMP:?}"/*
    for year in $(seq $YEAR_START $YEAR_END); do
	find /p/projects/climate_data_central/reanalysis/ERA5-Land/2m_temperature/ \
	     -name "2m_temperature_ERA5-Land_${year}*"
    done | parallel -j "${SLURM_CPUS_PER_TASK:-16}" process_file {} "$TMP"

    for agg in 'daymean' 'daymax' 'daymin'; do
        cdo -L -addc,-273.15 -mergetime "${TMP}germany_${agg}_2m_temperature_"* \
            "${TMP}germany_${agg}_2m_temperature_ERA5-LAND.nc"
    done
fi

# prepare population weights
# remap them to 0p1deg grid
# fill nan with zeros
cdo -L setmisstoc,0 -remapsum,$TMP"germany_daymean_2m_temperature_ERA5-LAND.nc" "data/population_data/gpw_v4_mean_population_count_rev11_30_sec_germany.nc" $TMP"pop_mean_weights.nc"
cdo -L setmisstoc,0 -remapsum,$TMP"germany_daymean_2m_temperature_ERA5-LAND.nc" "data/population_data/gpw_v4_population_count_rev11_2000_30_sec.nc" $TMP"pop_2000_weights.nc"

# calc regional averages in parallel
JOBS_FILE=$(mktemp)

for agg in 'daymean' 'daymax' 'daymin'; do
    INFILE=$TMP"germany_"$agg"_2m_temperature_ERA5-LAND.nc"

    # area weighted
    echo "netcdf2region --netcdf $INFILE --weights data/weights/ERA5Land_to_PLZ_weights.csv --method mean --var t2m --output data/results/area_weighted_${agg}_temperature_plz_level_era5_land.csv" >> "$JOBS_FILE"
    echo "netcdf2region --netcdf $INFILE --weights data/weights/ERA5Land_to_KREIS_weights.csv --method mean --var t2m --output data/results/area_weighted_${agg}_temperature_kreis_level_era5_land.csv" >> "$JOBS_FILE"

    # population weighted
    echo "netcdf2region --netcdf $INFILE --weights data/weights/ERA5Land_to_PLZ_weights.csv --method mean --var t2m --output data/results/pop_weighted_${agg}_temperature_plz_level_era5_land.csv --secondary_weights_netcdf ${TMP}pop_mean_weights.nc --secondary_weights_var Band1" >> "$JOBS_FILE"
    echo "netcdf2region --netcdf $INFILE --weights data/weights/ERA5Land_to_PLZ_weights.csv --method mean --var t2m --output data/results/pop_2000_weighted_${agg}_temperature_plz_level_era5_land.csv --secondary_weights_netcdf ${TMP}pop_2000_weights.nc --secondary_weights_var Band1" >> "$JOBS_FILE"
    echo "netcdf2region --netcdf $INFILE --weights data/weights/ERA5Land_to_KREIS_weights.csv --method mean --var t2m --output data/results/pop_weighted_${agg}_temperature_kreis_level_era5_land.csv --secondary_weights_netcdf ${TMP}pop_mean_weights.nc --secondary_weights_var Band1" >> "$JOBS_FILE"
    echo "netcdf2region --netcdf $INFILE --weights data/weights/ERA5Land_to_KREIS_weights.csv --method mean --var t2m --output data/results/pop_2000_weighted_${agg}_temperature_kreis_level_era5_land.csv --secondary_weights_netcdf ${TMP}pop_2000_weights.nc --secondary_weights_var Band1" >> "$JOBS_FILE"
done

parallel --memfree 8G -j "${SLURM_CPUS_PER_TASK:-16}" < "$JOBS_FILE"
rm -f "$JOBS_FILE"
