{
  # Based on https://github.com/bobvanderlinden/templates/blob/master/ruby/flake.nix
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        ruby = pkgs.ruby_3_3;

        anodyne-userpage-drafter =
          pkgs.runCommand "anodyne-userpage-drafter-0.1.0"
            {
              nativeBuildInputs = [ pkgs.makeWrapper ];
              meta.mainProgram = "log-pref";
            }
            ''
              mkdir -p $out/bin
              makeWrapper ${ruby}/bin/ruby $out/bin/log-pref \
                --add-flags ${self}/log-pref.rb
              ln -s log-pref $out/bin/anodyne-userpage-drafter
            '';
      in
      {
        formatter = pkgs.nixfmt-tree;

        packages = {
          default = anodyne-userpage-drafter;
          anodyne-userpage-drafter = anodyne-userpage-drafter;
        };

        apps.default = flake-utils.lib.mkApp {
          drv = anodyne-userpage-drafter;
          exePath = "/bin/log-pref";
        };

        devShells.default = pkgs.mkShell {
          packages = [
            anodyne-userpage-drafter
            pkgs.ruby_3_3
            pkgs.bundler
            pkgs.bundix
          ];
          buildInputs = [
            pkgs.ruby_3_3
            pkgs.bundix
          ];
        };
      }
    )
    // {
      hydraJobs = {
        inherit (self) packages;
      };
    };
}
