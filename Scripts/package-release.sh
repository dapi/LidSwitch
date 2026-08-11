#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"

"$repo_dir/Scripts/build-app.sh" release
"$repo_dir/Scripts/archive-app.sh"
