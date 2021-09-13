#!/bin/bash
set -e

CWD=$(cd $(dirname $0); pwd)

commit_sha=$(git rev-parse HEAD)
version=$1
name=$2
image="swiftfiddle.azurecr.io\/swiftfiddle\/runner:$version"
replicas=$3

sed "s/%NAME%/$name/g;s/%IMAGE%/$image/g;s/%VERSION%/$version/g;s/%MIN_REPLICAS%/$replicas/g;s/%COMMIT_SHA%/$commit_sha/g;" \
  "$CWD/pod_template.yaml"
