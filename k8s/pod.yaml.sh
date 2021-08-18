#!/bin/bash
set -e

CWD=$(cd $(dirname $0); pwd)

commit_sha=$(git rev-parse HEAD)
version=$1
name=$2
timestamp=$3
image="us.gcr.io\/swift-playground-fbe87\/runner:$version"

sed "s/%NAME%/$name/g;s/%IMAGE%/$image/g;s/%VERSION%/$version/g;s/%COMMIT_SHA%/$commit_sha/g;s/%TIMESTAMP%/$timestamp/g;" \
  "$CWD/pod_template.yaml" >> "$CWD/pod.yaml"
