#!/bin/bash
# Builds and pushes all service images to ghcr.io
# Run this from the gitops-demo root: ./services/build.sh
# Usage: ./services/build.sh [service-name]  (or no arg to build all)

set -e

REGISTRY="ghcr.io/jasvithchand"
TAG="${1:-latest}"
SERVICES=("auth-service" "shortener-service" "redirect-service" "analytics-service")

build_and_push() {
  local svc=$1
  echo "──────────────────────────────────────────"
  echo "Building $svc..."
  docker build -t "${REGISTRY}/${svc}:${TAG}" "./services/${svc}/app"
  echo "Pushing ${REGISTRY}/${svc}:${TAG}..."
  docker push "${REGISTRY}/${svc}:${TAG}"
  echo "✓ ${svc} done"
}

if [ -n "$2" ]; then
  build_and_push "$2"
else
  for svc in "${SERVICES[@]}"; do
    build_and_push "$svc"
  done
fi

echo ""
echo "All images pushed to ghcr.io/jasvithchand"
echo "Run 'argocd app sync --all' to deploy"
