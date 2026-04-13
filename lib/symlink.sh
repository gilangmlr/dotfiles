#!/usr/bin/env bash
# File-level stow-lite: link every file under a source package directory
# into the corresponding path under a target root, backing up any existing
# non-matching file. Must be sourced after lib/common.sh.

# prune_stale_links <source_pkg_dir> <target_root>
#
# Remove dangling symlinks under <target_root> that point into <source_pkg_dir>
# but whose source file no longer exists (e.g. after a rename in the repo).
# Only touches symlinks we previously created — never real files or links
# owned by anything else.
prune_stale_links() {
  local src="$1" dst="$2"
  [[ -d "$dst" ]] || return 0
  local link target
  while IFS= read -r -d '' link; do
    target="$(readlink "$link")"
    if [[ "$target" == "$src"/* && ! -e "$target" ]]; then
      log_warn "prune $link (target gone: $target)"
      rm -f "$link"
    fi
  done < <(find "$dst" -xtype l -print0 2>/dev/null)
}

# link_tree <source_pkg_dir> <target_root>
link_tree() {
  local src="$1" dst="$2"
  if [[ ! -d "$src" ]]; then
    log_warn "source dir not found: $src"
    return 0
  fi
  local src_file rel
  while IFS= read -r -d '' src_file; do
    rel="${src_file#"$src"/}"
    link_one "$src_file" "$dst/$rel"
  done < <(find "$src" -type f -print0)
}

# link_one <absolute_source_file> <absolute_target_path>
link_one() {
  local src_file="$1" target="$2"
  mkdir -p "$(dirname "$target")"

  if [[ -L "$target" ]]; then
    local current
    current="$(readlink "$target")"
    if [[ "$current" == "$src_file" ]]; then
      log_info "ok    $target"
      return 0
    fi
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    local backup
    backup="$target.backup.$(date +%Y%m%d%H%M%S)"
    log_warn "backup $target -> $backup"
    mv "$target" "$backup"
  fi

  ln -s "$src_file" "$target"
  log_info "link  $target -> $src_file"
}
