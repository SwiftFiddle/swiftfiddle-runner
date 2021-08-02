#!/bin/bash
set -e

CWD=$(cd $(dirname $0); pwd)
rm -f "$CWD/pod.yaml"

commit_sha=$(git rev-parse HEAD)
timestamp=$1

versions=($(cat $CWD/../versions.txt | tr "\n" " "))
for versionGroup in "${versions[@]}"; do
  read -r -a group <<< $(echo $versionGroup | sed "s/,/ /g")
  version=${group[${#group[@]}-1]}

  sed "s/%NAME%/$name/g;s/%IMAGE%/swiftfiddle\/runner:$version/g;s/%COMMIT_SHA%/$commit_sha/g;s/%TIMESTAMP%/$timestamp/g;" \
    "$CWD/pod_template.yaml" >> "$CWD/pod.yaml"
done
