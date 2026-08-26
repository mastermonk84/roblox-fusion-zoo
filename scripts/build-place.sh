#!/usr/bin/env bash
# Build the Studio artifact: string requires -> instance requires (darklua),
# then rojo build. Output: build/fusion-zoo.rbxl
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build .darklua-build
rojo sourcemap default.project.json -o sourcemap.json
darklua process src .darklua-build/src --config .darklua.json
# Rojo resolves paths relative to the project file, so an unmodified copy next
# to the processed tree points "src/..." at .darklua-build/src.
cp default.project.json .darklua-build/default.project.json
rojo build .darklua-build/default.project.json -o build/fusion-zoo.rbxl
echo "built build/fusion-zoo.rbxl"
