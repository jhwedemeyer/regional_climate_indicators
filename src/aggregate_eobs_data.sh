#! /bin/bash
#SBATCH --qos=short
#SBATCH --account=compacts
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=300000
#SBATCH --output=temp/agg-%A_%a.out
#SBATCH --error=temp/agg-%A_%a.err
#SBATCH --array=0-4

module purge
module load anaconda
module load cdo
module load parallel
#source activate .conda/

export PATH="$HOME/.local/bin:$PATH"

TMP="./temp/agg-eobs/"
mkdir -p "$TMP"
EOBS_DIR="/p/projects/impactee/Data/E-OBS/"

# measure definitions: raw E-OBS filename + cdo variable handle, indexed identically
GRIDS=("tg_ens_mean_0.1deg_reg_v33.0e.nc" "tn_ens_mean_0.1deg_reg_v33.0e.nc" "tx_ens_mean_0.1deg_reg_v33.0e.nc" "rr_ens_mean_0.1deg_reg_v33.0e.nc" "hu_ens_mean_0.1deg_reg_v33.0e.nc")
HANDLES=("tg" "tn" "tx" "rr" "hu")

# this task's measure, selected by array index
i=$SLURM_ARRAY_TASK_ID
RAWFILE="${GRIDS[$i]}"
INFILE=$TMP$RAWFILE
INFILE_base=$(basename "$RAWFILE" .nc)
voi_handle="${HANDLES[$i]}"

# crop germany and handle nan values for this measure only
cdo -L -b F64 -setmisstonn -sellonlatbox,4,17,46,57  $EOBS_DIR$RAWFILE $INFILE

# prepare population weights for this measure's grid
# (remapped to 0.1deg grid, nan filled with zeros; named per-measure so
#  concurrently running array tasks never write the same file)
POP_MEAN_WEIGHTS=$TMP"pop_mean_weights_${voi_handle}.nc"
POP_2000_WEIGHTS=$TMP"pop_2000_weights_${voi_handle}.nc"
cdo -L setmisstoc,0 -remapsum,$INFILE "data/population_data/gpw_v4_mean_population_count_rev11_30_sec_germany.nc" $POP_MEAN_WEIGHTS
cdo -L setmisstoc,0 -remapsum,$INFILE "data/population_data/gpw_v4_population_count_rev11_2000_30_sec.nc" $POP_2000_WEIGHTS

# the 6 netcdf2region calls for this measure are independent of each other,
# so run them in parallel across the task's allocated CPUs
CMDS=(
  "netcdf2region --netcdf $INFILE --weights data/weights/E_OBS_to_PLZ_weights.csv --method mean --var $voi_handle --output data/results/area_weighted_${voi_handle}_plz_level_eobs.csv"
  "netcdf2region --netcdf $INFILE --weights data/weights/E_OBS_to_KREIS_weights.csv --method mean --var $voi_handle --output data/results/area_weighted_${voi_handle}_kreis_level_eobs.csv"
  "netcdf2region --netcdf $INFILE --weights data/weights/E_OBS_to_PLZ_weights.csv --method mean --var $voi_handle --output data/results/pop_weighted_${voi_handle}_plz_level_eobs.csv --secondary_weights_netcdf $POP_MEAN_WEIGHTS --secondary_weights_var Band1"
  "netcdf2region --netcdf $INFILE --weights data/weights/E_OBS_to_PLZ_weights.csv --method mean --var $voi_handle --output data/results/pop_2000_weighted_${voi_handle}_plz_level_eobs.csv --secondary_weights_netcdf $POP_2000_WEIGHTS --secondary_weights_var Band1"
  "netcdf2region --netcdf $INFILE --weights data/weights/E_OBS_to_KREIS_weights.csv --method mean --var $voi_handle --output data/results/pop_weighted_${voi_handle}_kreis_level_eobs.csv --secondary_weights_netcdf $POP_MEAN_WEIGHTS --secondary_weights_var Band1"
  "netcdf2region --netcdf $INFILE --weights data/weights/E_OBS_to_KREIS_weights.csv --method mean --var $voi_handle --output data/results/pop_2000_weighted_${voi_handle}_kreis_level_eobs.csv --secondary_weights_netcdf $POP_2000_WEIGHTS --secondary_weights_var Band1"
)
 
printf "%s\n" "${CMDS[@]}" | parallel --memfree 8G --jobs "${SLURM_CPUS_PER_TASK:-16}"
