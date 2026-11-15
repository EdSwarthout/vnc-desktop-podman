#!/bin/bash
# Nested rootless podman checks (REVIEW.md #26). Run inside an instance, from this dir.
set -x
cd "$(dirname "$0")"

# 1-2: user namespace mapping (root -> ed 1001, plus the two subid ranges)
podman info --format '{{json .Host.IDMappings}} {{.Store.GraphDriverName}}'
podman run --rm docker.io/library/alpine sh -c 'id; cat /proc/self/uid_map'

# 3: published port via pasta; nginx needs a moment to start listening
podman run --rm -d --replace -p 8080:80 --name nginx docker.io/library/nginx
for _ in $(seq 20); do curl -sf localhost:8080 >/dev/null && break; sleep 0.5; done
curl -sS localhost:8080 | grep -o '<title>.*</title>'
podman stop -t 2 nginx

# 4: build with a RUN step
podman build -t curl -f Containerfile .
