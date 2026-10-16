#!/bin/bash 
#SBATCH --qos=priority
#SBATCH --account=compacts
#SBATCH --nodes=1 
#SBATCH --job-name=pop_agg
#SBATCH --ntasks-per-node=1 
#SBATCH --cpus-per-task=16
#SBATCH --output=temp/temp-%j.out
#SBATCH --error=temp/temp-%j.err
#SBATCH --mail-type=fail
#SBATCH --mem=60000

# Crops GPW v4 population count data (2000-2020) to a lon/lat box over Germany
# and computes the 2000-2020 time-mean population count on the 30 arc-second grid.

# Some initial setup
module purge
module load cdo

cdo -L setmisstoc,0 -setyear,2000 -sellonlatbox,4,17,46,57 /p/projects/compacts/data/population/gpw/gpw_v4_population_count_rev11_2000_30_sec.nc gpw_v4_population_count_rev11_2000_30_sec.nc
cdo -L setmisstoc,0 -setyear,2005 -sellonlatbox,4,17,46,57 /p/projects/compacts/data/population/gpw/gpw_v4_population_count_rev11_2005_30_sec.nc gpw_v4_population_count_rev11_2005_30_sec.nc
cdo -L setmisstoc,0 -setyear,2010 -sellonlatbox,4,17,46,57 /p/projects/compacts/data/population/gpw/gpw_v4_population_count_rev11_2010_30_sec.nc gpw_v4_population_count_rev11_2010_30_sec.nc
cdo -L setmisstoc,0 -setyear,2015 -sellonlatbox,4,17,46,57 /p/projects/compacts/data/population/gpw/gpw_v4_population_count_rev11_2015_30_sec.nc gpw_v4_population_count_rev11_2015_30_sec.nc
cdo -L setmisstoc,0 -setyear,2020 -sellonlatbox,4,17,46,57 /p/projects/compacts/data/population/gpw/gpw_v4_population_count_rev11_2020_30_sec.nc gpw_v4_population_count_rev11_2020_30_sec.nc

cdo -L timmean -mergetime gpw_v4_population_count_rev11_2000_30_sec.nc gpw_v4_population_count_rev11_2005_30_sec.nc gpw_v4_population_count_rev11_2010_30_sec.nc gpw_v4_population_count_rev11_2015_30_sec.nc gpw_v4_population_count_rev11_2020_30_sec.nc gpw_v4_mean_population_count_rev11_30_sec_germany.nc



