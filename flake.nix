{
  description = ''
    A NixOS module for chainweb-node.

    This flake purosefully does NOT export a chainweb-node binary;
    that must be supplied into `pkgs` by the user, e.g. via an overlay.
  '';

  inputs = {
    std.url = "github:chessai/nix-std";
  };

  outputs = {
    std,
    self,
  }: {
    nixosModules.chainweb-node = import ./module.nix std.lib;
  };
}
