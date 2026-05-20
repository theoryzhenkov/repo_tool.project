default:
    @just --list

build:
    nix build .#default

check:
    nix flake check

smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    system="$(nix eval --impure --raw --expr 'builtins.currentSystem')"
    pkg="$(nix build ".#packages.$system.realm-fixture" --print-out-paths --no-link)"
    test ! -e "$pkg/bin/project"
    test ! -L "$pkg/bin/realm"
    test "$(readlink -f "$pkg/bin/realm")" = "$pkg/bin/realm"
    "$pkg/bin/realm" help | diff -u tests/golden/realm-fixture/help.txt -
    "$pkg/bin/realm" list | diff -u tests/golden/realm-fixture/list-tree.txt -
    "$pkg/bin/realm" list --flat | diff -u tests/golden/realm-fixture/list-flat.txt -
    "$pkg/bin/realm" list beta | diff -u <(printf 'beta\n') -
    "$pkg/bin/realm" list --flat beta | diff -u <(printf 'beta\n') -
    "$pkg/bin/realm" list -a | diff -u tests/golden/realm-fixture/list-all-tree.txt -
    "$pkg/bin/realm" list -a --flat | diff -u tests/golden/realm-fixture/list-all-flat.txt -
    "$pkg/bin/realm" list -r | diff -u tests/golden/realm-fixture/repo-list.txt -
    "$pkg/bin/realm" show -r repo.alpha --json | python -m json.tool | diff -u tests/golden/realm-fixture/repo-alpha.json -
    "$pkg/bin/realm" path -r alpha-repo | grep -qx /tmp/project-alpha-home/src
    mkdir -p /tmp/project-alpha-home/src
    (cd /tmp/project-alpha-home/src && "$pkg/bin/realm" list -r --here) | diff -u tests/golden/realm-fixture/repo-list.txt -
