# TODO

Open issues, most important first. When one is done, delete it here and note the
outcome where it belongs (AGENTS.md, README.md, a commit message).

## `vnc-pkg`: local package files on Fedora (probably root for the user)

`container/vnc-pkg` checks names with `^[a-zA-Z0-9][a-zA-Z0-9.+_-]*(:[a-z0-9]+)?$`, which
allows dots, so `foo.rpm` gets through. dnf most likely treats an argument ending in
`.rpm` as a local package file even without a `/`. sudo keeps the caller's working
directory, and dnf doesn't check signatures on local packages by default
(`localpkg_gpgcheck`). So `cd ~; vnc-pkg install evil.rpm` would install a package the
user built, as root. Not confirmed yet: no Fedora image was available to test.

- Check: in a throwaway Fedora instance, `cd ~ && touch x.rpm && vnc-pkg install x.rpm`.
  An error about an invalid rpm file (not "No match for argument") confirms it.
- Fix: reject names ending in `.rpm` or `.deb`, and `cd /` before running the package
  manager. apt needs a `/` before it treats an argument as a file, so it is safe today,
  but the same rule covers it.
- While there: the pattern also allows a trailing `-` or `+`, and for apt
  `install foo-` means *remove* foo. Reject both.
- Add the bad names to the rejection list in `tests/test_env.sh`.

## `vnc-pkg` and the "no root for the user" decision

`vnc-pkg` lets the user install, remove and upgrade anything in the distro's repositories
as root (package scripts run as root). So the limit is now what the repositories contain,
not what the image contains. AGENTS.md says so, but it is a change to the earlier "no
root" design decision. Points to decide or document:

- Is repository-scoped root acceptable for every image, or should `vnc-pkg` be opt-in
  (a build arg, or only in some images)?
- `vnc-pkg remove` can remove packages the image depends on (`sudo`, `passt`, `podman`)
  and break the instance. A deny list of packages that can't be removed?
- Fedora's shared cache also holds repository metadata, and the user can write to it
  (it is the user's NFS directory), while root's dnf reads it. Packages are still
  signature-checked, so the risk is limited to holding back or downgrading packages.
  apt and pacman verify what they take from the cache.

## pasta: iperf3 can't reach the parent's port 5201

With `d_run_opts=("-d" "--network=pasta:-T,5201,--map-gw" "--cap-add=NET_RAW")` (`-T`
before `--map-gw` for podman 4.9, which otherwise drops the option after `--map-gw` and
adds its own `-T none`), `podman run` starts, but iperf3 in the instance still can't
reach a server on the parent's port 5201. The default `d_run_opts` no longer includes
the pasta options; the line above is in `env.rc`'s comment for `.env`. Not investigated:

- Is the server on the parent listening on 127.0.0.1 or only on another address?
  (`-T 5201` forwards the instance's 127.0.0.1:5201 to the parent's 127.0.0.1:5201.)
- Does `--map-gw` + `host.containers.internal:5201` work instead of `-T`?
- Try on a newer podman than 4.9, and nested as well as on the host.
