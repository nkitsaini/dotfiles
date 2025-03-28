{ config, pkgs, ... }:
{
  home.packages = [
    pkgs.git-absorb
    pkgs.meld
  ];
  programs.jujutsu = {
    enable = true;
    settings = {
      ui = {
        paginate = "never";
        default-command = "log";
      };
    };
  };

  programs.git = {
    # username and email are defined
    # by device specific config
    enable = true;
    lfs.enable = true;

    delta = {
      enable = true;
      options = {
        navigate = true;
        syntax-theme = "Monokai Extended Light";
        features = "side-by-side line-numbers decorations"; # hyperlinks
        whitespace-error-style = "22 reverse";
        decorations = {
          commit-decoration-style = "bold yellow box ul";
          # plus-style = ''syntax "#c4ffc4"'';
          # minos-style = ''syntax "#ffebe8"'';
          file-style = "bold yellow ul";
          file-decoration-style = "none";
        };
      };
    };
    extraConfig = {
      include.path = builtins.fetchurl {
        url = "https://raw.githubusercontent.com/dandavison/delta/2f76c56d91d3d49feb170b89d7526e0272634998/themes.gitconfig";
        sha256 = "06d6a1dafb5df353b2de52558bc17cf78b0fbd31da7186f41eb0489b2bcd6e26";
      };
      diff = {
        algorithm = "histogram";
        renames = "copies";
        mnemonicprefix = true;
        colormoved = "default";
      };
      url = {
        "git@github.com:" = {
          insteadOf = "gh:";
        };
        "git@github.com:nkitsaini/" = {
          insteadOf = "ghme:";
        };
      };

      transfer.fsckobjects = true;
      fetch.fsckobjects = true;
      receive.fsckObjects = true;

      branch = {
        sort = "-committerdate";
      };
      init.defaultBranch = "main";
      help.autocorrect = 10;
      merge.tool = "meld";

      push = {
        default = "simple";
        autoSetupRemote = true;
      };
      merge = {
        conflictstyle = "zdiff3";
      };
      rerere = {
        enabled = 1;
      };
      pull = {
        rebase = true;
      };
      rebase = {
        autostash = true;
      };
      commit = {
        verbose = true;
      };
      core = {
        excludeFiles = "${config.home.homeDirectory}/.gitignore";
      };
    };
    attributes = [ "*.lockb binary diff=lockb" ];
    aliases = {
      l = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset %C(yellow)%an%Creset' --abbrev-commit --date=relative";
      ls = "log --stat --oneline";
      pf = "push --force-with-lease";
      p = "push";
      wa = "worktree add";
      wl = "worktree list";
      wp = "worktree prune";
      wr = "worktree remove";
    };
  };
}
