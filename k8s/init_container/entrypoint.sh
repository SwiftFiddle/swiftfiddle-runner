#!/bin/bash
set -ex

echo "$DOCKER_HUB_ACCESS_TOKEN" | docker login --username="$DOCKER_HUB_USERNAME" --password-stdin

for version in $RUNNER_VERSIONS; do
  if [[ "$version" == nightly-main || "$version" == nightly-5.8 || "$version" == nightly-5.9 ]] ;
  then
    docker pull "swiftlang/swift:$version-focal"
    docker tag "swiftlang/swift:$version-focal" "swiftlang/swift:$version"
  elif [[ "$version" == nightly* ]] ;
  then
    docker pull "swiftlang/swift:$version-bionic"
    docker tag "swiftlang/swift:$version-bionic" "swiftlang/swift:$version"
  elif [[ "$version" == 2.2 || "$version" == 2.2.1 || "$version" == 3.0 || "$version" == 3.0.1 || "$version" == 3.0.2 || "$version" == 3.1 || "$version" == 3.1.1 ]] ;
  then
    :
  else
    docker pull "swiftfiddle/swift:$version"
  fi
done

docker container prune --force --filter "until=1h"
docker image prune --force
docker images
