# serve.R
# Serves the hhi-map directory locally with range request support (needed for PMTiles).
# Run from the hhi-map directory: Rscript serve.R

servr::httd(".", port = 8080, browser = TRUE)

# Stop
servr::daemon_stop(1)
