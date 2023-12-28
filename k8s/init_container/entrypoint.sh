#!/bin/bash
set -ex

echo "$DOCKER_HUB_ACCESS_TOKEN" | docker login --username="$DOCKER_HUB_USERNAME" --password-stdin

for version in $RUNNER_VERSIONS; do
  if [[ "$version" == nightly-main || "$version" == nightly-5.7 || "$version" == nightly-5.8 || "$version" == nightly-5.9 || "$version" == nightly-5.10 ]] ;
  then
    docker pull "swiftlang/swift:$version-jammy"
    docker tag "swiftlang/swift:$version-jammy" "swiftlang/swift:$version"
  elif [[ "$version" == nightly* ]] ;
  then
    :
  elif [[ "$version" == 2.2 || "$version" == 2.2.1 || "$version" == 3.0 || "$version" == 3.0.1 || "$version" == 3.0.2 || "$version" == 3.1 || "$version" == 3.1.1 || "$version" == 4.0 || "$version" == 4.0.2 || "$version" == 4.0.3 || "$version" == 4.1 || "$version" == 4.1.1 || "$version" == 4.1.2 || "$version" == 4.1.3 || "$version" == 4.2 || "$version" == 4.2.1 || "$version" == 4.2.2 || "$version" == 4.2.3 || "$version" == 4.2.4 || "$version" == 5.0 || "$version" == 5.0.1 || "$version" == 5.0.2 || "$version" == 5.0.3 || "$version" == 5.1 || "$version" == 5.1.1 || "$version" == 5.1.2 || "$version" == 5.1.3 || "$version" == 5.1.4 || "$version" == 5.1.5 ]] ;
  then
    :
  else
    docker pull "swiftfiddle/swift:$version"
  fi
done

docker container prune --force --filter "until=1h"
docker image prune --force
docker images
