#!/bin/bash
# Nested rootless podman checks. Run inside an instance; prints ok/FAIL per check and
# exits non-zero if any failed. Command output goes to stderr.
cd "$(dirname "$0")" || exit 1
alpine=docker.io/library/alpine
fails=0
check() {   # check NAME COMMAND...
    local name=$1; shift
    if "$@" >&2; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}

# 1: user namespace mapping (root -> the user, plus the subid ranges) and storage driver
check "podman info" podman info --format '{{json .Host.IDMappings}} {{.Store.GraphDriverName}}'

# 2: run a container
check "podman run" podman run --rm "$alpine" sh -c 'id; cat /proc/self/uid_map'

# 3: published port via pasta; nginx needs a moment to start listening
port() {
    podman run --rm -d --replace -p 8080:80 --name tests-nginx docker.io/library/nginx || return
    local rc=1
    for _ in $(seq 20); do curl -sf 127.0.0.1:8080 >/dev/null && break; sleep 0.5; done
    curl -sS 127.0.0.1:8080 | grep -o '<title>.*</title>' && rc=0
    podman stop -t 2 tests-nginx >/dev/null
    return $rc
}
check "published port" port

# 4: build with a RUN step (network from a build), then remove the image
check "podman build" podman build -t tests-curl -f Containerfile .
podman rmi tests-curl >/dev/null 2>&1

echo "$fails failed"
[ "$fails" -eq 0 ]
