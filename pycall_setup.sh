#!/usr/bin/env bash
set -euo pipefail
py="$(julia -e 'using Pkg; Pkg.activate("."); Pkg.build("PyCall"); using PyCall; println(PyCall.pyprogramname)')"
"${py:?}" -m pip install Jinja2==3.1.4