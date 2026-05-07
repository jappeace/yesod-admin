{ pkgs ? import ./pkgs.nix {}
, hpkgs ? import ./hpkgs.nix {}
}:
let
  buildTargets = {
    library = hpkgs.template-project;
  };
in
buildTargets // {
  all-builds = pkgs.runCommand "all-builds" {} (
    ''
      mkdir -p $out
    '' +
    builtins.concatStringsSep "\n" (
      builtins.attrValues (
        builtins.mapAttrs (name: drv: ''
          ln -s ${drv} $out/${name}
        '') buildTargets
      )
    )
  );
}
