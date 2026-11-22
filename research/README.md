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
| [intel-igpu-render-node.md](intel-igpu-render-node.md) | planned: Intel iGPU render node for Omarchy and GNOME on Wayland (needs `renderD128` in the instance) |
| [debian13-vkms-gemini.md](debian13-vkms-gemini.md) | reviewed, not tested: Gemini's "host compositor + socket" doesn't nest a desktop; GNOME headless already needs no vkms, Hyprland still needs a render node or vkms (two tests planned) |
| [omarchy-headless-setup-notes.md](omarchy-headless-setup-notes.md) | superseded by `../omarchy/`: the two starting notes merged, each suggestion checked against what was built |
