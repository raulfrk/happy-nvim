# scripts/ssh-z.zsh
# Source from ~/.zshrc:
#   source /path/to/happy-nvim/scripts/ssh-z.zsh
# Wraps ssh and mosh to log every connection to happy-nvim's frecency DB.

_happy_host_db="${XDG_DATA_HOME:-$HOME/.local/share}/happy-nvim/hosts.json"

_happy_log_host() {
  local host="$1"
  [[ -z "$host" ]] && return
  mkdir -p "$(dirname "$_happy_host_db")"
  [[ -f "$_happy_host_db" ]] || echo '{}' > "$_happy_host_db"
  local now=$(date +%s)
  # jq -e ensures we fail gracefully if the file is malformed
  local updated=$(jq --arg host "$host" --argjson now "$now" \
    '.[$host] = { visits: ((.[$host].visits // 0) + 1), last_used: $now }' \
    "$_happy_host_db" 2>/dev/null)
  if [[ -n "$updated" ]]; then
    printf '%s' "$updated" > "$_happy_host_db"
  fi
}

ssh() {
  # Extract host argument (first non-flag positional)
  local host=""
  for arg in "$@"; do
    case "$arg" in
      -*) ;;
      *) host="$arg"; break ;;
    esac
  done
  _happy_log_host "$host"
  command ssh "$@"
}

mosh() {
  local host=""
  for arg in "$@"; do
    case "$arg" in
      -*|--*) ;;
      *) host="$arg"; break ;;
    esac
  done
  _happy_log_host "$host"
  command mosh "$@"
}
