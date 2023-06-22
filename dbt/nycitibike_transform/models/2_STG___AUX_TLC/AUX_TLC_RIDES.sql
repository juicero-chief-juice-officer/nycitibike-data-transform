{% set  source_dataset = '1_SRC___AUX_TLC'%}

{% set table_columns = {
    'RIDES_FHV': {'pickup_datetime':'pickup_datetime','dropoff_datetime':'dropOff_datetime','pickup_location_id':'PUlocationID','dropoff_location_id':'DOlocationID','passenger_count':'x','trip_distance':'x','trip_type':'x','rate_code_id':'x','fare_amount':'x','tip_amount':'x','tolls_amount':'x','airport_fee':'x','ehail_fee':'x','congestion_surcharge':'x','improvement_surcharge':'x','mta_tax':'x','extra':'x','total_amount':'x','payment_type':'x','store_and_fwd_flag':'x','sr_flag':'SR_Flag','vendor_id':'x','dispatching_base_num':'dispatching_base_num','affiliated_base_number':'Affiliated_base_number'}, 
'RIDES_YELLOW': {'pickup_datetime':'tpep_pickup_datetime','dropoff_datetime':'tpep_dropoff_datetime','pickup_location_id':'PULocationID','dropoff_location_id':'DOLocationID','passenger_count':'passenger_count','trip_distance':'trip_distance','trip_type':'x','rate_code_id':'RatecodeID','fare_amount':'fare_amount','tip_amount':'tip_amount','tolls_amount':'tolls_amount','airport_fee':'Airport_fee','ehail_fee':'x','congestion_surcharge':'congestion_surcharge','improvement_surcharge':'improvement_surcharge','mta_tax':'mta_tax','extra':'extra','total_amount':'total_amount','payment_type':'payment_type','store_and_fwd_flag':'store_and_fwd_flag','sr_flag':'x','vendor_id':'VendorID','dispatching_base_num':'x','affiliated_base_number':'x'}, 
'RIDES_GREEN': {'pickup_datetime':'lpep_pickup_datetime','dropoff_datetime':'lpep_dropoff_datetime','pickup_location_id':'PULocationID','dropoff_location_id':'DOLocationID','passenger_count':'passenger_count','trip_distance':'trip_distance','trip_type':'trip_type','rate_code_id':'RatecodeID','fare_amount':'fare_amount','tip_amount':'tip_amount','tolls_amount':'tolls_amount','airport_fee':'x','ehail_fee':'ehail_fee','congestion_surcharge':'congestion_surcharge','improvement_surcharge':'improvement_surcharge','mta_tax':'mta_tax','extra':'extra','total_amount':'total_amount','payment_type':'payment_type','store_and_fwd_flag':'store_and_fwd_flag','sr_flag':'x','vendor_id':'VendorID','dispatching_base_num':'x','affiliated_base_number':'x'}, 
'RIDES_FHVHV': {'pickup_datetime':'Pickup_datetime','dropoff_datetime':'DropOff_datetime','pickup_location_id':'PULocationID','dropoff_location_id':'DOLocationID','passenger_count':'x','trip_distance':'trip_miles','trip_type':'x','rate_code_id':'x','fare_amount':'base_passenger_fare','tip_amount':'tips','tolls_amount':'tolls','airport_fee':'airport_fee','ehail_fee':'x','congestion_surcharge':'congestion_surcharge','improvement_surcharge':'x','mta_tax':'x','extra':'x','total_amount':'x','payment_type':'x','store_and_fwd_flag':'x','sr_flag':'x','vendor_id':'Hvfhs_license_num','dispatching_base_num':'Dispatching_base_num','affiliated_base_number':'originating_base_num'},
} %}
        {# https://docs.google.com/spreadsheets/d/1biUVIqKlQ21lhX4I1MI3BNupYKceTkhEK-SpwID3nlE/edit?usp=sharing #}

WITH union_all_tlc_trips as
(
{% for loop_tables, loop_columns in table_columns.items() %}
  SELECT
    {% for dest_column, src_column in loop_columns.items() %}
      {% if dest_column == 'vendor_id' and src_column == 'x' %}
          '' as {{ dest_column }},
      {% elif dest_column == 'vendor_id' and src_column != 'x' %}
          cast({{ src_column}} as string) as {{ dest_column }},
      {% elif src_column != 'x' %}
        {{src_column}} as {{dest_column}},
      {% else %}
        NULL as {{ dest_column }},
      {% endif %}
    {% endfor %}
  FROM {{target.name ~ '_' ~ source_dataset ~ '.' ~ loop_tables }}

  {% if not loop.last %}
    UNION ALL
  {% endif %}
{% endfor %}
)
, 

dim_locations as (
    select * 
    from {{ ref('LOCATION_ID_TO_NEIGHBORHOOD') }}
    where borough != 'Unknown'
)

select 
      union_all_tlc_trips.pickup_datetime
    , union_all_tlc_trips.dropoff_datetime
    , union_all_tlc_trips.pickup_location_id
    , pickup_locations.borough as pickup_borough
    , pickup_locations.neighborhood as pickup_neighborhood
    , union_all_tlc_trips.dropoff_location_id
    , dropoff_locations.borough as dropoff_borough
    , dropoff_locations.neighborhood as dropoff_neighborhood
    , union_all_tlc_trips.passenger_count
    , union_all_tlc_trips.trip_distance
    , union_all_tlc_trips.trip_type
    , union_all_tlc_trips.rate_code_id
    , union_all_tlc_trips.fare_amount
    , union_all_tlc_trips.tip_amount
    , union_all_tlc_trips.tolls_amount
    , union_all_tlc_trips.airport_fee
    , union_all_tlc_trips.ehail_fee
    , union_all_tlc_trips.congestion_surcharge
    , union_all_tlc_trips.improvement_surcharge
    , union_all_tlc_trips.mta_tax
    , union_all_tlc_trips.extra
    , union_all_tlc_trips.total_amount
    , {{ tlc_payment_type(('union_all_tlc_trips.payment_type')) }} as payment_type
    , union_all_tlc_trips.store_and_fwd_flag
    , union_all_tlc_trips.sr_flag
    , union_all_tlc_trips.vendor_id
    , union_all_tlc_trips.dispatching_base_num
    , union_all_tlc_trips.affiliated_base_number

FROM union_all_tlc_trips
left join dim_locations as pickup_locations
on union_all_tlc_trips.pickup_location_id = pickup_locations.location_id
left join dim_locations as dropoff_locations
on union_all_tlc_trips.dropoff_location_id = dropoff_locations.location_id
