#!/bin/bash
set -ex

echo "$DOCKER_HUB_ACCESS_TOKEN" | docker login --username="$DOCKER_HUB_USERNAME" --password-stdin

if [[ $RUNNER_VERSION == nightly* ]] ;
then
  docker pull "swiftlang/swift:$RUNNER_VERSION"
else
  for version in $(echo $RUNNER_VERSION | sed "s/,/ /g"); do
    docker pull "swiftfiddle/swift:$version"
  done
fi

./Run serve --env production --hostname "0.0.0.0" --port 8080
