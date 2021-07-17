#!/bin/bash
set -e

rm pod.yaml

versions=($(cat ../versions.txt | tr "\n" " "))
for version in "${versions[@]}"; do
  name="runner-v$(sed 's/\.//g' <<<"$version")"
  commit_sha=$(git rev-parse HEAD)
  sed "s/%NAME%/$name/g;s/%IMAGE%/swiftfiddle\/runner:$version/g;s/%COMMIT_SHA%/$commit_sha/g;"  pod_template.yaml >> pod.yaml
done
