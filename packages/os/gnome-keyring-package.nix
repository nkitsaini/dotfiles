{ pkgs }:
# A Nixpkgs update that changes this source will fail patch application rather
# than silently dropping the crash guard, forcing an explicit review.
pkgs.gnome-keyring.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./gnome-keyring-open-session-failure.patch
  ];
})
