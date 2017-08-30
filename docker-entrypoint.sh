!/bin/bash

# set sensible defaults if not provided by docker run
: "${GF_SECURITY_ADMIN_USER:=admin}"
: "${GF_SECURITY_ADMIN_PASSWORD:=secret}"

# Variables
GRAFANA_BASIC_AUTH="${GF_SECURITY_ADMIN_USER}:${GF_SECURITY_ADMIN_PASSWORD}"
GRAFANA_URL="localhost:3000"
GRAFANA_SOURCES_PATH="/etc/grafana"

function kill_container {
    # Exit with error
    exit 1;
}

function create_dashboard_from_template {
    # A json file exported from grafana as a template
    grafana_template=$(cat "$1");

    # Wrap the dashboard json format into the shape that the API expects
    dashboard="{\"dashboard\": $grafana_template,\"overwrite\":true, \"inputs\":[]}"
    echo "$dashboard"
}

function bootstrap_grafana {
    # Timeout after 1 min
    local readonly LOOP_TIMEOUT_SECONDS=20
    local readonly LOOP_INCREMENT_SECONDS=3
    local LOOP_COUNT_SECONDS=0

    # Wait until grafana is up
    until $(curl --silent --fail --show-error --output /dev/null -u admin:admin http://localhost:3000/api/datasources); do
        # If we've tried too many times
        if (( ${LOOP_COUNT_SECONDS} >= ${LOOP_TIMEOUT_SECONDS} )); then
            echo "Error: Server never started."
            kill_container
        fi

        # tick
        printf '.'

        # Increment loop counter
        (( LOOP_COUNT_SECONDS+=1 ))

        sleep ${LOOP_INCREMENT_SECONDS}
    done ;

    # Loop over datasources, and add each via API
    for file in $(find /etc/grafana/datasources/ -name '*.json') ; do
        if [ -e "$file" ] ; then
            echo "Importing datasource: $file" &&
            curl -v \
                -u admin:admin \
                --request POST http://localhost:3000/api/datasources \
                --header "Content-Type: application/json" \
                --data-binary "@$file" ;
            echo "Tried to import datasource: $file" ;
        fi
    done ;

    # Loop over dashboards, and add each via API
    # Dashboards use a nested version of the dashboard templates
    for file in $(find $ /etc/grafana/dashboards/ -name '*.json') ; do
        if [ -e "$file" ] ; then
            # Pre-process the dashboard json format to what the API expects
            dashboard=$(create_dashboard_from_template $file)
            echo "Importing dashboard: $file" &&
            curl -v \
                -u admin:admin \
                --request POST http://localhost:3000/api/dashboards/db \
                --header "Content-Type: application/json" \
                --data "$dashboard" ;
            echo "Tried to import the dashboard: $file" ;
        fi
    done ;
}

# Turn on monitor mode so we can send job to background
set -m

# Run Grafana's default startup script https://github.com/grafana/grafana-docker
echo "Start Grafana in Background"
/run.sh &

# Bootstrap Grafana with datasources and dashboards
echo "Init Grafana"
bootstrap_grafana

echo "Bring Grafana Back to Foreground"
jobs
fg %1
