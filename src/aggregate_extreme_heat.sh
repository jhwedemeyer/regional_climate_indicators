#!/bin/bash
#SBATCH --qos=priority
#SBATCH --account=impactee
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
CALC_MEASURES=true

TMP="./temp/heatwave/"
mkdir -p $TMP

agg='daymax'
RAW_CLIMATE_DATA=$TMP"germany_"$agg"_t2m_ERA5-Land.nc"

if [ "$PREPARE_DATA" = true ]; then
    rm -rf "${TMP:?}"/*

    process_file() {
        file="$1"
        TMP="$2"
        filename=$(basename "$file")
        cropped="${TMP}cropped_${filename}"

        cdo -L -b F64 -s sellonlatbox,4,17,46,57 "$file" "$cropped"

        cdo -L -b F64 -s setmisstonn -daymax "$cropped" "${TMP}germany_daymax_${filename}"

        rm -f "$cropped"
    }
    export -f process_file

    for year in {1950..2023}; do
        find /p/projects/climate_data_central/reanalysis/ERA5-Land/2m_temperature/ \
             -name "2m_temperature_ERA5-Land_${year}*.nc"
    done | parallel -j "${SLURM_CPUS_PER_TASK:-16}" process_file {} "$TMP"

    cdo -b F64 mergetime $TMP"germany_daymax_"* $TMP"germany_"$agg"_2m_temperature_ERA5-Land.nc"
    cdo -L -b F64 addc,-273.15 $TMP"germany_"$agg"_2m_temperature_ERA5-Land.nc" $RAW_CLIMATE_DATA
fi

#####################
# Generate measures #
#####################

REF_PERIOD=$TMP"t2m_daymax_ref_1961-1990.nc"
THRESHOLD=$TMP"threshold_p98_doy_1961-1990.nc"
ABOVE_THRESH=$TMP"above_threshold_1950-2023.nc"
ABOVE_28=$TMP"above_28degC_1950-2023.nc"
HEAT_CONDITION=$TMP"heat_condition_1950-2023.nc"
RUN_LENGTH=$TMP"run_length_1950-2023.nc"
HEATWAVE_DAYS=$TMP"heatwave_days_daily_1950-2023.nc"

if [ "$CALC_MEASURES" = true ]; then
	# --- Step 1: Extract reference period 1961-1990 ---
	cdo -L -b F64 selyear,1961/1990 $RAW_CLIMATE_DATA $REF_PERIOD

	# --- Step 2: p98 threshold per DOY with ±15-day running window ---
	# ydrunpctl needs min and max files as bounds for histogram algorithm
	# nts=31 gives a ±15-day window; pooled over 30 ref years = 930 values per DOY
	# Output: one value per DOY (365/366 timesteps)
	cdo -L -b F64 ydrunpctl,98,31 $REF_PERIOD \
	    -ydrunmin,31 $REF_PERIOD \
	    -ydrunmax,31 $REF_PERIOD \
	    $THRESHOLD

	# --- Step 3: t2m > p98 threshold, matched by DOY ---
	# ydaysub subtracts the DOY-matched threshold from the full time series
	# gtc,0 then gives 1 where the anomaly is positive (i.e. t2m > threshold)
	cdo -L -b F64 gtc,0 -ydaysub $RAW_CLIMATE_DATA $THRESHOLD $ABOVE_THRESH

	# --- Step 4: t2m > 28°C ---
	cdo -L -b F64 gtc,28 $RAW_CLIMATE_DATA $ABOVE_28

	# --- Step 5: Both conditions must hold simultaneously ---
	# mul on two binary 0/1 masks = logical AND
	cdo -L -b F64 mul $ABOVE_THRESH $ABOVE_28 $HEAT_CONDITION
fi

# --- Step 6: Regional aggregation at daily level ---
GRIDS=($HEAT_CONDITION)
HANDLES=("t2m")

# prepare population weights
# remap them to 0p1deg grid
# fill nan with zeros
cdo -L setmisstoc,0 -remapsum,$HEAT_CONDITION "data/population_data/gpw_v4_mean_population_count_rev11_30_sec_germany.nc" $TMP"pop_mean_weights.nc"
cdo -L setmisstoc,0 -remapsum,$HEAT_CONDITION "data/population_data/gpw_v4_population_count_rev11_2000_30_sec.nc" $TMP"pop_2000_weights.nc"

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
