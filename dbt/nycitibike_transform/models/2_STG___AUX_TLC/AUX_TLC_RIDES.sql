{% set  source_dataset = '1_SRC___AUX_TLC'%}

{% set table_columns = {
    'RIDES_FHV': {'dropoff_datetime':'dropOff_datetime','pickup_location_id':'PUlocationID','dropoff_location_id':'DOlocationID','passenger_count':'x','trip_distance':'x','trip_type':'x','rate_code_id':'x','fare_amount':'x','tip_amount':'x','tolls_amount':'x','airport_fee':'x','ehail_fee':'x','congestion_surcharge':'x','improvement_surcharge':'x','mta_tax':'x','extra':'x','total_amount':'x','payment_type':'x','store_and_fwd_flag':'x','sr_flag':'SR_Flag','vendor_id':'x','dispatching_base_num':'dispatching_base_num','affiliated_base_number':'Affiliated_base_number'}, 
    'RIDES_YELLOW': {'dropoff_datetime':'tpep_dropoff_datetime','pickup_location_id':'PULocationID','dropoff_location_id':'DOLocationID','passenger_count':'passenger_count','trip_distance':'trip_distance','trip_type':'x','rate_code_id':'RatecodeID','fare_amount':'fare_amount','tip_amount':'tip_amount','tolls_amount':'tolls_amount','airport_fee':'Airport_fee','ehail_fee':'x','congestion_surcharge':'congestion_surcharge','improvement_surcharge':'improvement_surcharge','mta_tax':'mta_tax','extra':'extra','total_amount':'total_amount','payment_type':'payment_type','store_and_fwd_flag':'store_and_fwd_flag','sr_flag':'x','vendor_id':'VendorID','dispatching_base_num':'x','affiliated_base_number':'x'}, 
    'RIDES_GREEN': {'dropoff_datetime':'lpep_dropoff_datetime','pickup_location_id':'PULocationID','dropoff_location_id':'DOLocationID','passenger_count':'passenger_count','trip_distance':'trip_distance','trip_type':'trip_type','rate_code_id':'RatecodeID','fare_amount':'fare_amount','tip_amount':'tip_amount','tolls_amount':'tolls_amount','airport_fee':'x','ehail_fee':'ehail_fee','congestion_surcharge':'congestion_surcharge','improvement_surcharge':'improvement_surcharge','mta_tax':'mta_tax','extra':'extra','total_amount':'total_amount','payment_type':'payment_type','store_and_fwd_flag':'store_and_fwd_flag','sr_flag':'x','vendor_id':'VendorID','dispatching_base_num':'x','affiliated_base_number':'x'}, 
} %}
{# https://docs.google.com/spreadsheets/d/1biUVIqKlQ21lhX4I1MI3BNupYKceTkhEK-SpwID3nlE/edit?usp=sharing #}



{% for loop_tables, loop_columns in table_columns.items() %}
  SELECT
    {% for dest_column, src_column in loop_columns.items() %}
      {% if src_column != 'x' %}
        {{ src_column}} as {{ dest_column }},
      {% else %}
        NULL as {{ dest_column }},
      {% endif %}
    {% endfor %}
  FROM {{target.name ~ '_' ~ source_dataset ~ '.' ~ loop_tables }}

  {% if not loop.last %}
    UNION ALL
  {% endif %}
{% endfor %}
