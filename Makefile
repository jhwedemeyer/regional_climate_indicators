submit_weights:
	sbatch src/gen_kreis_weights_for_e_obs.sh
	sbatch src/gen_kreis_weights_for_era5_land.sh
	sbatch src/gen_nuts3_weights_for_e_obs.sh
	sbatch src/gen_nuts3_weights_for_era5_land.sh
	sbatch src/gen_plz_weights_for_e_obs.sh
	sbatch src/gen_plz_weights_for_era5_land.sh

aggregate:
	sbatch src/aggregate_extreme_heat.sh  
	sbatch src/aggregate_precip.sh  
	sbatch src/aggregate_relhum.sh  
	sbatch src/aggregate_snow.sh  
	sbatch src/aggregate_temperature.sh
	sbatch src/aggregate_eobs_data.sh

