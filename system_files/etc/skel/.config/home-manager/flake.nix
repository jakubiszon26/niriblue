{
  # niriblue home-manager starter (standalone, flakes).
  #
  # This file is seeded from /etc/skel, so it only lands in the home directories of
  # accounts created AFTER it shipped. An existing account (e.g. one created on an
  # earlier image) will NOT have it -- see LAYERING.md for the one-liner to drop it
  # into an existing home.
  #
  # First use:
  #   1) edit home.nix (set home.username / home.homeDirectory to your account)
  #   2) home-manager switch --flake ~/.config/home-manager#niriblue
  description = "niriblue home-manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      # Selector name is arbitrary; reference it as `#niriblue` in the switch command.
      # The actual account is set via home.username/homeDirectory in home.nix.
      homeConfigurations."niriblue" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
      };
    };
}
