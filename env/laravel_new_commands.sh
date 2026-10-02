#!/usr/bin/env bash
set -Eeuo pipefail

version="${LARAVEL_VERSION:-}"

if [[ -n "$version" ]]; then
  composer create-project laravel/laravel . "$version" --prefer-dist --no-interaction
else
  composer create-project laravel/laravel . --prefer-dist --no-interaction
fi
