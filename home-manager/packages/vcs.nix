{ pkgs, ... }: {
  home.packages = [ pkgs.git-absorb ];
  programs.jujutsu = {
    enable = true;
    settings = { ui.paginate = "never"; };
  };

  programs.git = {
    # username and email are defined
    # by device specific config
    enable = true;

    delta = {
      enable = true;
      options = {
        navigate = true;
        syntax-theme = "Monokai Extended Light";
        features = "side-by-side line-numbers decorations"; # hyperlinks
        whitespace-error-style = "22 reverse";
        decorations = {
          commit-decoration-style = "bold yellow box ul";
          file-style = "bold yellow ul";
          file-decoration-style = "none";
        };
      };
    };
    extraConfig = {
      diff = {
        algorithm = "histogram";
        renames = "copies";
        mnemonicprefix = true;
        colormoved = "default";
      };
      url = { "git@github.com:" = { insteadOf = "gh:"; }; };
      url = { "git@github.com:nkitsaini/" = { insteadOf = "ghme:"; }; };
      init.defaultBranch = "main";
      help.autocorrect = 1;

      push = {
        default = "simple";
        autoSetupRemote = true;
      };
      merge = { conflictstyle = "zdiff3"; };
      rerere = { enabled = 1; };
      pull = { rebase = true; };
      rebase = { autostash = true; };
    };
    aliases = {
      l =
        "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset %C(yellow)%an%Creset' --all --abbrev-commit --date=relative";
      ls = "log --stat --oneline";
      pf = "push --force-with-lease";
      p = "push";
    };
  };
}
