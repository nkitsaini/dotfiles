{ pkgs, ... }:
(let
  name = "Oogway The Survivor";
  email = "oogway@example.com";
  username = "oogway";
  homeDirectory = "/home/${username}";
  notesDirectory = "${homeDirectory}/code/notes";
  notesGitPush = (pkgs.writeShellApplication {
    name = "notes-git-push";
    text = ''
      cd ${notesDirectory}
      nix develop . --command python3 scripts/auto-commit.py
    '';
  });
in {
  home.username = username;
  home.homeDirectory = homeDirectory;
  imports = [ ../../packages/hm/setup-full.nix ];

  # programs.git.userName = name;
  # programs.git.userEmail = email;
  programs.jujutsu.settings.user.name = name;
  programs.jujutsu.settings.user.email = email;
  programs.fish.shellAliases.rebuild-system =
    "sudo nixos-rebuild switch --flake ${homeDirectory}/code/dotfiles/#oogway"

  systemd.user.enable = true;
  systemd.user.services.notes-git-push = {
    Unit = { Description = "Periodically pushes notes to git"; };
    Install = { WantedBy = [ "default.target" ]; };
    Service = { ExecStart = "${notesGitPush}/bin/notes-git-push"; };
  };
})

