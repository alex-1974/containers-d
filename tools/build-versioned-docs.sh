#!/usr/bin/env bash
set -euo pipefail

root="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
)"
cd "$root"

version="${1:-}"
compiler="${DC:-dmd}"

if [[ -z "$version" ]]; then
    echo "usage: $0 <vMAJOR.MINOR.PATCH>" >&2
    exit 2
fi

case "$version" in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *)
        echo "error: documentation version must be vMAJOR.MINOR.PATCH: $version" >&2
        exit 2
        ;;
esac

git rev-parse --verify --quiet "$version^{commit}" >/dev/null || {
    echo "error: missing release tag: $version" >&2
    exit 1
}

work_dir="$root/build/versioned-docs"
source_dir="$work_dir/source/$version"
site_dir="$work_dir/site"
version_site="$site_dir/$version"

rm -rf "$work_dir"
mkdir -p "$source_dir" "$version_site"

echo "=== Extract qualified release $version ==="
git archive "$version" | tar -x -C "$source_dir"

echo
echo "=== Build DDox documentation from $version ==="
(
    cd "$source_dir"
    dub build -b ddox --compiler="$compiler" --force
)

generated_dir="$source_dir/docs"

test -f "$generated_dir/index.html" || {
    echo "error: DDox did not generate docs/index.html" >&2
    exit 1
}

for symbol in     StaticRingBuffer     RingBuffer     StaticVector     ScratchBuffer     WorkStealingDeque     BlockingQueue

do
    if ! grep -Rql --include='*.html' "$symbol" "$generated_dir"; then
        echo "error: DDox output is missing public family: $symbol" >&2
        exit 1
    fi
done

echo
echo "=== Assemble stable and versioned site ==="
cp -a "$generated_dir/." "$version_site/"
cp -a "$version_site/." "$site_dir/"

cat > "$site_dir/versions.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>containers-d API documentation versions</title>
</head>
<body>
  <h1>containers-d API documentation</h1>
  <p>The root documentation follows the current stable release: <strong>$version</strong>.</p>
  <ul>
    <li><a href="./index.html">$version — latest stable</a></li>
    <li><a href="./$version/index.html">$version — versioned documentation</a></li>
  </ul>
</body>
</html>
EOF

touch "$site_dir/.nojekyll"

test -f "$site_dir/index.html"
test -f "$version_site/index.html"
test -f "$site_dir/versions.html"

echo
echo "PASS: stable DDox site built from $version"
echo "site: $site_dir"
