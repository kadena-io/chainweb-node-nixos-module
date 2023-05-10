# A NixOS module for chainweb-node

This flake purposefully does NOT export a chainweb-node binary;
That must be supplied into `pkgs` by the user, e.g. via an overlay.

There is a single output: `nixosModules.chainweb-node`. You can use it like
this:
```nix
# flake.nix
{
  inputs.chainwebModule.url = "github:kadena-io/chainweb-node-nixos-module";

  outputs =
    { nixpkgs,
      chainwebModule,
      ...
    }:
    
    {
      nixosConfigurations = {
        chainweb-node = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules =
            let
              main = import ./configuration.nix;
              chainwebPackage = {
                nixpkgs.overlays = [ yourCoolChainwebOverlay ];
              };
              chainwebService = chainwebModule.nixosModules.chainweb-node;
            in
            [ 
              main
              chainwebPackage
              chainwebService
            ];
        };
      };
    };
}
```
