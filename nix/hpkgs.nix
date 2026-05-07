{ pkgs ? import ./pkgs.nix { }
,
}:
# you can pin a specific ghc version with
# pkgs.haskell.packages.ghc984 for example.
# this allows you to create multiple compiler targets via nix.
pkgs.haskellPackages.override {
  overrides = hnew: hold: {
    # NB this is a bit silly because nix files are now considered for the build
    # bigger projects should consider putting haskell stuff in a subfolder
    yesod-admin = hnew.callCabal2nix "yesod-admin" ../. { };
    # yesod-form tests need network access, disable them
    yesod-form = pkgs.haskell.lib.dontCheck hold.yesod-form;
  };
}
