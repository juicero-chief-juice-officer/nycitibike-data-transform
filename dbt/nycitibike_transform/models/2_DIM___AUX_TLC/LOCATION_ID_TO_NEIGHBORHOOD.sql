{{ config(materialized='table') }}


select 
    locationid as location_id, 
    borough, 
    zone as neighborhood, 
    replace(service_zone,'Boro','Green') as service_zone
from {{ ref('x_seed_taxi_zone_lookup') }}