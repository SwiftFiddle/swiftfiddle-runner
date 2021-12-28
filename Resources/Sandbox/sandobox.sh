#!/bin/bash

to=$1
shift

if type timeout > /dev/null 2>&1; then
  timeoutCommand='timeout'
else
  timeoutCommand='gtimeout'
fi

# 10MB file size limit
# 20 processes limit
# 256 MB memory limit
# 20% CPU usage
containerId=$(docker run --pull never --env _COLOR=$_COLOR --rm --detach --ulimit fsize=10000000:10000000 --pids-limit 20 --memory 256m --cpus="0.2" "$@")
status=$($timeoutCommand "$to" docker wait "$containerId" || true)
docker kill $containerId &> /dev/null
docker rm -f $containerId &> /dev/null

statusFile="${2%:/\[REDACTED]}/status"
/bin/echo -n "status: " > "$statusFile"
if [ -z "$status" ]; then
  /bin/echo 'timeout' >> "$statusFile"
else
  /bin/echo "exited($status)" >> "$statusFile"
fi

docker logs $containerId | sed 's/^/\t/'
docker rm $containerId &> /dev/null
