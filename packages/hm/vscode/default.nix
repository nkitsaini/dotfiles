{ pkgs, ... }: {
  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs; [
      vscode-extensions.vscodevim.vim
      vscode-extensions.ms-vsliveshare.vsliveshare
      vscode-extensions.ms-python.python
      vscode-extensions.svelte.svelte-vscode
    ];
    # userSettings = builtins.fromJSON (builtins.readFile ./settings.json);
    # keybindings = builtins.fromJSON (builtins.readFile ./keybindings.json);
  };
}
