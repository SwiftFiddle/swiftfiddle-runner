#!/bin/bash
set -ex

if [[ $RUNNER_VERSION == nightly* ]] ;
then
  docker pull "swiftlang/swift:$RUNNER_VERSION"
else
  docker pull "swiftfiddle/swift:$RUNNER_VERSION"
fi

./Run serve --env production --hostname "0.0.0.0" --port 8080
