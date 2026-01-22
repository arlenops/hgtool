# Phase 1: Foundation & Dependencies
- [ ] Create directory structure (`bin`, `lib`, `plugins`, `logs`) and empty `hgtool.sh`.
- [ ] Implement `lib/deps.sh`: Add logic to detect OS/Arch (x86/arm) and download `gum`/`fzf` binaries to `bin/` if missing.
- [ ] Implement `lib/ui.sh`: Encapsulate `gum` commands (banner, confirm, input, spinner) into standardized functions (e.g., `hg_input`, `hg_confirm`).
- [ ] Implement `hgtool.sh` (Entry Point): Load libs, run dependency check, and verify `gum` works by showing the Banner.

# Phase 2: Core Plugins (System & Storage)
- [ ] Implement `plugins/00_system.sh`: System update, Timezone fix, and Swap manager.
- [ ] Implement `plugins/01_storage.sh`: "Mount New Disk" feature. Must use `lsblk` to find disks and `gum confirm` (Red) before formatting.
- [ ] Implement `plugins/01_storage.sh`: "Resize Partition" feature (growpart/resize2fs).

# Phase 3: Advanced Plugins (Docker & Network)
- [ ] Implement `plugins/02_network.sh`: SSH Port change (with input validation) and basic Firewall allow logic.
- [ ] Implement `plugins/03_docker.sh`: Docker installation check + One-click install.
- [ ] Implement `plugins/03_docker.sh`: **Data Migration** feature. Stop docker -> rsync data -> update daemon.json -> start docker.

# Phase 4: Integration & Polish
- [ ] Implement Main Menu logic in `hgtool.sh`: Auto-discover scripts in `plugins/` and verify `fzf` menu selection works.
- [ ] Verify error handling: Ensure script doesn't crash if user presses ESC in menus.
- [ ] Final Cleanup: Add comments and remove debug echos.