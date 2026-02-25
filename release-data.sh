#!/bin/bash
# Upload PMTiles file to a GitHub release.
# The file is in data/ (gitignored) and is uploaded as a release asset.
# Run from the project root directory.
#
# To update an existing release, first delete it:
#   gh release delete data-v2 --yes
# Then re-run this script.

gh release create data-v2 \
  data/hhi_tracts.pmtiles \
  --title "HHI tract map data v2" \
  --notes "PMTiles file with HHI values baked into census tract properties.

Download URL:
- https://github.com/vehicletrends/hhi-map/releases/download/data-v2/hhi_tracts.pmtiles"
