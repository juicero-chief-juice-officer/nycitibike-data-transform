-- {% macro generate_schema_name(custom_schema_name, node) -%}

--     {%- set environment = env_var('__DBT_ENV__', 'CORE') -%}
--                             -- {{env_var('VAR','OPTIONAL_DEFAULT')}}
--     {%- set default_schema = target.schema -%}
--     {%- set prod_schema_prefix = 'CORE' -%}
--     {%- set dev_schema_prefix = 'DEV' -%}

--     -- {%- if custom_schema_name is none -%}
    
--     --     {{ default_schema }}
--     -- {%- else -%}

--     {%- if environment == 'CORE' -%}

--         {{ prod_schema_prefix }}_{{ default_schema | trim }}

--     {%- else -%}

--         {{ dev_schema_prefix }}_{{ default_schema | trim }}
    
--     {%- endif -%}

--     -- {%- endif -%}

-- {%- endmacro %} 