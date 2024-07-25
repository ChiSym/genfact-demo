#!/usr/bin/env bash
set -euxo pipefail
repo_root=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
if [[ "$(hostname)" = "genfact-server" ]]; then
  export JULIA_DEPOT_PATH=/srv/julia/.julia
  export JULIA_LOAD_PATH=/srv/genfactdemo:
  julia_preamble='DEPOT_PATH[1] = "'"$JULIA_DEPOT_PATH"'"'
else
  julia_preammble=""
fi

julia_setup=${julia_preamble:+"${julia_preamble}"}'; using Pkg; Pkg.instantiate(); Pkg.add(PackageSpec(url="https://github.com/probcomp/PClean.git", rev="ian/update"))'
printf '%s\n' "JULIA_DEPOT_PATH is "${JULIA_DEPOT_PATH+"$JULIA_DEPOT_PATH"}
export -p | grep JULIA || true
export JULIA_DEBUG=app,GenFactDemo
if [[ "$(hostname)" = "genfact-server" ]]; then
  logfile="$repo_root"/output.log
  cmd=nohup julia --project="${repo_root:?}" -e ${julia_preamble:+"${julia_preamble}"}'; include("app.jl")' > "$logfile"
  if [[ $- == *i* ]]; then
    sudo touch "$logfile"
    sudo chmod o+w "$logfile"
    sudo -u genfact-demo julia --project="${repo_root:?}" -e "${julia_setup:?}"
    sudo -u genfact-demo sh -c "$cmd" &
  else
    sh -c "$cmd" &
  fi
else
  julia --project="${repo_root:?}" -e "${julia_setup:?}"
  julia --project="${repo_root:?}" -e ${julia_preamble:+"${julia_preamble}"}'; include("app.jl")'
fi
