# research/

Plans and notes for experiments that aren't built yet, or are only partly built. Each file has:
- a Status line;
- the question, and the expected answer;
- prerequisites;
- steps and verification;
- a "Resuming" section with the prompt to give Claude Code to pick it up.

Experiments that produce code live in their own directories (`../wayland/`, `../omarchy/`);
their READMEs record the results.

| File | Status |
|---|---|
| [intel-igpu-render-node.md](intel-igpu-render-node.md) | done: Omarchy (`../omarchy/` `o_render=1`, Hyprland nested in a headless labwc) and GNOME (`../wayland/`, headless + RDP) render on the iGPU's `renderD128`, several instances at once |
| [aquamarine-upstream-draft.md](aquamarine-upstream-draft.md) | draft, not submitted: the Wayland-backend bugs found nesting Hyprland. Two are fixed in v0.16.0; the version binds are #398, closed as not planned |
| [dgx-spark-gnome-vkms.md](dgx-spark-gnome-vkms.md) | planned, needs the DGX Spark: GNOME Shell KMS mode on its vkms `card1` (arm64; `card0` is the NVIDIA GPU) |
| [debian13-vkms-gemini.md](debian13-vkms-gemini.md) | reviewed, not tested: Gemini's "host compositor + socket" doesn't nest a desktop; GNOME headless already needs no vkms, Hyprland still needs a render node or vkms (two tests planned) |
| [omarchy-headless-setup-notes.md](omarchy-headless-setup-notes.md) | superseded by `../omarchy/`: the two starting notes merged, each suggestion checked against what was built |
