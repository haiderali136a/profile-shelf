#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
exec swift "$project_dir/scripts/render-brand.swift"
