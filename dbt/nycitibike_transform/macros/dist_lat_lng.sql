{% macro dist_lat_lng(lat1, lng1, lat2, lng2, unit) %}
{# Uses the Haversine formula #}
    {# Check unit input #}
    {% if unit not in ['km','mi'] %}
        {{ exceptions.raise_compiler_error('Invalid input for `unit`, it should be either "km" or "mi".') }}
    {% else %}
    {# Set radius constant, then calc #}
        {% if unit == 'mi'%}
            {% set radius = 3959 %}
        {% else %}
            {% set radius = 6371 %}
        ( radius * 
            acos(
            cos(radians({{ lat1 }})) 
            * cos(radians({{ lat2 }})) 
            * cos(radians({{ lng2 }}) - radians({{ lng1 }})) 
            + sin(radians({{ lat1 }})) 
            * sin(radians({{ lat2 }}))
            )
        )
        {% endif %}
{% endif %}
{% endmacro %}
