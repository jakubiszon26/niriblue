{ pkgs, ... }:
{
  # `ujust setup-home-manager` fills in the CHANGEME placeholder with your account on the
  # first run, so you normally do not touch these. On bootc, homes live under /var/home.
  home.username = "CHANGEME";
  home.homeDirectory = "/var/home/CHANGEME";

  # Bump to the home-manager release you are tracking; do not change it later just to
  # silence the prompt -- it pins state-migration behaviour.
  home.stateVersion = "25.05";

  # Per-user CLI / dev tooling goes here. This is the layer that replaces distrobox and
  # Homebrew on niriblue: declarative, per-user, no image rebuild. Example:
  #
  #   home.packages = with pkgs; [ ripgrep fd bat eza jq gh fzf direnv ];
  home.packages = with pkgs; [ ];

  programs.home-manager.enable = true;
}
