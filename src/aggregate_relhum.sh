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

PREPARE_DATA=true

# temp folder
TMP="./temp/relhum/"
mkdir $TMP

RAW_CLIMATE_DATA=$TMP"germany_t2m_d2m_ERA5-Land_1950-2022.nc"

if [ "$PREPARE_DATA" = true ]; then
    rm -rf "${TMP:?}"/*
    ###############
    # input files #
    ###############
    voi='2m_dewpoint_temperature'
    voi_handle='d2m'

    process_file() {
        file="$1"
        TMP="$2"
        filename=$(basename "$file")
        # cut file to size of Germany
        # fill missing data (over the sea) with nearest neighbours
        # !dont change lon-lat-box without recalculating the weights!
        cdo -L -b F64 -s setmisstonn -daymean -sellonlatbox,4,17,46,57 "$file" "${TMP}germany_daymean_${filename}"
    }
    export -f process_file

    {
    	# dew point files
        find ./data/ERA5-Land_data/ -name "2m_dewpoint_temperature_ERA5-Land_*.nc"
        
        # temperature files
        for year in {1950..2022}; do
            find /p/projects/climate_data_central/reanalysis/ERA5-Land/2m_temperature/ \
                 -name "2m_temperature_ERA5-Land_${year}*"
        done
    } | parallel -j "${SLURM_CPUS_PER_TASK:-16}" process_file {} "$TMP"

    # merge to one dataframe per variable
    cdo -b F64 mergetime $TMP"germany_daymean_2m_dewpoint_temperature_"* $TMP"germany_daymean_2m_dewpoint_temperature_ERA5-Land_1950-2022.nc"
    cdo -b F64 mergetime $TMP"germany_daymean_2m_temperature_"* $TMP"germany_daymean_2m_temperature_ERA5-LAND_1950-2022.nc"

    # merge to one overall dataframe
    cdo -L -b F64 -addc,-273.15 -merge $TMP"germany_daymean_2m_temperature_ERA5-LAND_1950-2022.nc" $TMP"germany_daymean_2m_dewpoint_temperature_ERA5-Land_1950-2022.nc" $RAW_CLIMATE_DATA
fi


#####################
# Generate measures #
#####################

# vapor pressure
VAPOR_PRESSURE=$TMP"vapor_pressure_1950-2022.nc"
cdo -L -b F64 expr,'eTd=6.1094*exp((17.625*d2m)/(243.04+d2m))' $RAW_CLIMATE_DATA $VAPOR_PRESSURE

# saturation vapor pressure
SATURATION_VAPOR_PRESSURE=$TMP"saturation_vapor_pressure_1950-2022.nc"
cdo -L -b F64 expr,'esT=6.1094*exp((17.625*t2m)/(243.04+t2m))' $RAW_CLIMATE_DATA $SATURATION_VAPOR_PRESSURE

# relative humidity
RELATIVE_HUMIDITY=$TMP"relative_humidity_1950-2022.nc"
cdo -L -b F64 expr,'rh=eTd/esT*100' -merge $VAPOR_PRESSURE $SATURATION_VAPOR_PRESSURE $RELATIVE_HUMIDITY

# sWBGT
sWBGT=$TMP"swbgt_1950-2022.nc"
cdo -L -b F64 expr,'sWBGT=0.567*t2m+0.393*eTd+3.94' -merge $VAPOR_PRESSURE $RAW_CLIMATE_DATA $sWBGT

# relative humidity approximation
RELATIVE_HUMIDITY_APPROX=$TMP"relative_humidity_approx_1950-2022.nc"
cdo -L -b F64 expr,'rh=100 - 5 * (t2m - d2m)' $RAW_CLIMATE_DATA $RELATIVE_HUMIDITY_APPROX

# calc regional averages

GRIDS=($VAPOR_PRESSURE $SATURATION_VAPOR_PRESSURE $RELATIVE_HUMIDITY $sWBGT $RELATIVE_HUMIDITY_APPROX)
HANDLES=("eTd" "esT" "rh" "sWBGT" "rh")
# prepare population weights
# remap them to 0p1deg grid
# fill nan with zeros
cdo -L setmisstoc,0 -remapsum,$VAPOR_PRESSURE "data/population_data/gpw_v4_mean_population_count_rev11_30_sec_germany.nc" $TMP"pop_mean_weights.nc"
cdo -L setmisstoc,0 -remapsum,$VAPOR_PRESSURE "data/population_data/gpw_v4_population_count_rev11_2000_30_sec.nc" $TMP"pop_2000_weights.nc"

for i in "${!GRIDS[@]}"; do
	INFILE="${GRIDS[$i]}"
	INFILE_base=$(basename "${GRIDS[$i]}" .nc)
	voi_handle="${HANDLES[$i]}"

	# area weighted aggregation
	netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_PLZ_weights.csv" --method "mean" --var $voi_handle --output "data/results/area_weighted_"$INFILE_base"_plz_level_era5_land.csv"
	
	netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_KREIS_weights.csv" --method "mean" --var $voi_handle --output "data/results/area_weighted_"$INFILE_base"_kreis_level_era5_land.csv"

	# population weighted aggregation
	netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_PLZ_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_weighted_"$INFILE_base"_plz_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_mean_weights.nc" --secondary_weights_var "Band1"
	netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_PLZ_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_2000_weighted_"$INFILE_base"_plz_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_2000_weights.nc" --secondary_weights_var "Band1"
	
	netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_KREIS_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_weighted_"$INFILE_base"_kreis_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_mean_weights.nc" --secondary_weights_var "Band1"
	netcdf2region --netcdf $INFILE --weights "data/weights/ERA5Land_to_KREIS_weights.csv" --method "mean" --var $voi_handle --output "data/results/pop_2000_weighted_"$INFILE_base"_kreis_level_era5_land.csv" --secondary_weights_netcdf $TMP"pop_2000_weights.nc" --secondary_weights_var "Band1"
done

