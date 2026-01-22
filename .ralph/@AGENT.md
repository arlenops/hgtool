# Build & Test Instructions

To verify the current progress, run the tool directly:

```bash
# Make sure main script is executable
chmod +x hgtool.sh

# Run the tool (It should auto-download deps on first run)
./hgtool.sh
Testing Notes:

Since gum and fzf are downloaded to ./bin/, ensure the script adds ./bin to PATH or calls them explicitly.

If testing "Disk Mount" or "Docker" logic, mock the commands if you are not running as root, or check for root privileges at the start of those specific functions.


---

### 4. 📋 `specs/requirements.md`
> **作用**：详细的业务逻辑说明书，供 Ralph 查阅具体实现的细节。

```markdown
# hgtool Technical Specifications

## 1. Dependency Management (Critical)
The tool must be portable.
- On launch, check if `bin/gum` and `bin/fzf` exist.
- If not, `curl` download them from a reliable GitHub release mirror.
- Handle `aarch64` vs `x86_64` detection automatically.

## 2. UI Standardization
All scripts must use `lib/ui.sh`.
- `hg_banner`: Shows "Heiguo Cloud" logo.
- `hg_input "$PROMPT" "$PLACEHOLDER" "$IS_PASSWORD"`: Wraps `gum input`.
- `hg_confirm "$QUESTION"`: Wraps `gum confirm`. Returns 0 for Yes, 1 for No.
- `hg_spinner "$TEXT" "$COMMAND"`: Wraps `gum spin`. Hides stdout of the command.

## 3. Storage Module Logic
- **Mount Disk**:
  1. List disks with `lsblk -rno NAME,SIZE,TYPE,MOUNTPOINT | awk '$3=="disk" && $4==""'`.
  2. User selects disk via `fzf`.
  3. WARNING: "This will format $DISK!".
  4. `mkfs.ext4 -F /dev/$DISK`.
  5. `mkdir -p $MOUNTPOINT` && `mount ...`.
  6. Add to `/etc/fstab` using UUID.

## 4. Docker Migration Logic
- **Migrate Data**:
  1. Ask for new path (e.g., `/data/docker`).
  2. `systemctl stop docker`.
  3. `rsync -avzP /var/lib/docker/ $NEW_PATH/`.
  4. Write `{"data-root": "$NEW_PATH"}` to `/etc/docker/daemon.json`.
  5. `systemctl start docker`.