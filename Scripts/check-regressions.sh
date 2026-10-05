#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
sources=()
while IFS= read -r -d '' source; do sources+=("$source"); done < <(find Sources -name '*.swift' ! -name App.swift -print0)
swiftc -swift-version 5 -parse-as-library "${sources[@]}" Scripts/RegressionChecks.swift -o .build/regression-checks
.build/regression-checks
