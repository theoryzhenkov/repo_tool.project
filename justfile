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
    pkg="$(nix build ".#packages.$system.project-fixture" --print-out-paths --no-link)"
    test ! -L "$pkg/bin/project"
    test "$(readlink -f "$pkg/bin/project")" = "$pkg/bin/project"
    "$pkg/bin/project" help | diff -u tests/golden/project-fixture/help.txt -
    "$pkg/bin/project" list | diff -u tests/golden/project-fixture/list.txt -
    "$pkg/bin/project" repo list | diff -u tests/golden/project-fixture/repo-list.txt -
    "$pkg/bin/project" repo show repo.alpha --json | python -m json.tool | diff -u tests/golden/project-fixture/repo-alpha.json -
    "$pkg/bin/project" repo path alpha-repo | grep -qx '/tmp/project-alpha-home/src'
