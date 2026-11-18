#!/bin/bash
# Extract the installed Omarchy system from the ISO's omarchy-root.img.zst (a raw btrfs
# filesystem) into omarchy/rootfs.tar, without root on the host: a throwaway archcc:base
# container (root in the user namespace) decompresses it and runs `btrfs restore`, which
# reads the image file directly (no loop mount). Owners, modes, xattrs (file caps) and
# symlinks are kept. Runs on the host or nested in an instance.
#   omarchy/extract.sh [WORKDIR]   (default ~/Containers/omarchy-work; needs ~12 GB)
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd)
ISO=${OMARCHY_ISO:-$D/OMARCHY_202611}
IMG=$ISO/arch/x86_64/omarchy-root.img.zst
W=${1:-$HOME/Containers/omarchy-work}
OUT=$D/rootfs.tar
IMAGE=${OMARCHY_EXTRACT_IMAGE:-localhost/archcc:base}
CACHE=/var/cache/apt-archlinux

[ -r "$IMG" ] || { echo "no $IMG (is the ISO mounted?)" >&2; exit 1; }
mkdir -p "$W"
avail=$(df -B1G --output=avail "$W" | tail -1)
[ "$avail" -ge 12 ] || { echo "$W: only ${avail} GB free, need ~12" >&2; exit 1; }

cache=()
[ -d "$CACHE" ] && cache=(-v "$CACHE:$CACHE")
cmd=(podman run --rm --user root --security-opt label=disable
     -v "$ISO:/iso:ro" -v "$W:/work" -v "$D:/out" "${cache[@]}"
     "$IMAGE" bash -euc '
pacman -Syu --noconfirm --needed btrfs-progs zstd >/dev/null
cd /work
[ -s root.img ] || zstd -d -f -o root.img /iso/arch/x86_64/omarchy-root.img.zst
# subvolume "omarchy-root" (256) is the whole system; 257/258 are the empty systemd
# var/lib/portables and var/lib/machines
id=$(btrfs inspect-internal dump-tree -t root root.img \
     | grep -B1 "name omarchy-root\$" | sed -n "s/.*ROOT_REF \([0-9]*\)).*/\1/p")
[ -n "$id" ] || { echo "no omarchy-root subvolume" >&2; exit 1; }
rm -rf tree; mkdir tree
btrfs restore -x -m -S -i -r "$id" root.img tree >restore.log 2>&1 || { tail restore.log; exit 1; }
tar --xattrs --xattrs-include="*" --numeric-owner -C tree -cf /out/rootfs.tar.part \
    --exclude=./dev --exclude=./proc --exclude=./sys --exclude=./run --exclude=./tmp \
    --exclude=./boot --exclude=./var/cache/pacman/pkg/* \
    --exclude=./usr/lib/modules --exclude=./usr/lib/firmware .
mv /out/rootfs.tar.part /out/rootfs.tar
echo "== checks"
getcap tree/usr/bin/newuidmap tree/usr/bin/ping || true
stat -c "%u:%g %A %n" tree/etc/shadow tree/usr/bin/sudo tree/usr/bin/Hyprland 2>&1 || true
ls tree/home tree/etc/skel -a; du -sh tree /out/rootfs.tar
rm -rf tree root.img
')
echo "${cmd[*]}"; "${cmd[@]}"
ls -l "$OUT"
