#!/bin/bash
set -ex

echo "$DOCKER_HUB_ACCESS_TOKEN" | docker login --username="$DOCKER_HUB_USERNAME" --password-stdin

for version in $RUNNER_VERSIONS; do
  if [[ "$version" == nightly* ]] ;
  then
    docker pull "swiftlang/swift:$version"
  else
    docker pull "swiftfiddle/swift:$version"
  fi
done

docker image prune --force
