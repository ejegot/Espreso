#!/usr/bin/env bash
set -Eeuo pipefail

DO_HOST="${DO_HOST:-134.209.110.46}"
DO_SSH_USER="${DO_SSH_USER:-root}"
DO_REMOTE_BASE="${DO_REMOTE_BASE:-/opt/espreso}"
DO_HEALTH_URL="${DO_HEALTH_URL:-http://127.0.0.1:4000/login}"

fail() {
  printf 'Deploy failed: %s\n' "$*" >&2
  exit 1
}

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" ||
  fail "run this command from inside the Espreso repository"
cd "$repo_root"

branch="$(git branch --show-current)"
[[ "$branch" == "main" ]] || fail "switch to main before deploying (current branch: $branch)"
[[ -z "$(git status --porcelain)" ]] ||
  fail "commit or stash local changes before deploying"
[[ "$DO_REMOTE_BASE" =~ ^/[A-Za-z0-9._/-]+$ ]] ||
  fail "DO_REMOTE_BASE must be an absolute path containing only letters, numbers, dots, underscores, slashes, and hyphens"
[[ "$DO_HEALTH_URL" =~ ^https?://[A-Za-z0-9.:-]+(/[A-Za-z0-9._~/-]*)?$ ]] ||
  fail "DO_HEALTH_URL must be an HTTP(S) URL with a simple host and path"

git fetch origin main
git merge --ff-only origin/main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] ||
  fail "local main must match origin/main; refusing to deploy unpublished commits"
commit="$(git rev-parse --short=12 HEAD)"
target="${DO_SSH_USER}@${DO_HOST}"
release_dir="${DO_REMOTE_BASE}/releases/${commit}"

printf 'Preparing Espreso %s for %s\n' "$commit" "$target"
printf -v remote_release_dir '%q' "$release_dir"
git archive --format=tar HEAD |
  ssh "$target" "mkdir -p $remote_release_dir && tar -xf - -C $remote_release_dir"

printf -v remote_args '%q ' "$commit" "$release_dir" "$DO_HEALTH_URL"
ssh "$target" "bash -s -- $remote_args" <<'REMOTE'
set -Eeuo pipefail

commit="$1"
release_dir="$2"
health_url="$3"
image="espreso:${commit}"
backup="espreso-rollback-$(date -u +%Y%m%d%H%M%S)"
env_file="/run/espreso-deploy-${commit}.env"
cutover_started=0

rollback() {
  status=$?
  rm -f "$env_file"

  if (( status != 0 && cutover_started )); then
    echo "Deployment failed; restoring the previous container." >&2
    docker rm -f espreso >/dev/null 2>&1 || true
    if docker inspect "$backup" >/dev/null 2>&1; then
      docker rename "$backup" espreso
      docker start espreso >/dev/null
      echo "Rollback complete." >&2
    else
      echo "Rollback container $backup was not found; manual recovery is required." >&2
    fi
  fi
  exit "$status"
}
trap rollback EXIT

docker build -t "$image" "$release_dir"
docker inspect espreso >/dev/null
docker inspect espreso --format '{{range .Config.Env}}{{println .}}{{end}}' > "$env_file"
chmod 600 "$env_file"

docker rename espreso "$backup"
cutover_started=1
docker stop --time 30 "$backup" >/dev/null
docker run -d \
  --name espreso \
  --network host \
  --restart unless-stopped \
  --user 0:0 \
  --env-file "$env_file" \
  "$image" >/dev/null

for attempt in $(seq 1 30); do
  if curl --fail --silent "$health_url" >/dev/null; then
    rm -f "$env_file"
    cutover_started=0
    echo "Deployment successful: $commit ($image)."
    echo "Previous container retained as $backup for rollback."
    exit 0
  fi
  sleep 2
done

echo "Health check failed at $health_url." >&2
exit 1
REMOTE
