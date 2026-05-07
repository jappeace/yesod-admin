{ pkgs ? import ./pkgs.nix {}
, hpkgs ? import ./hpkgs.nix {}
}:
# Extract the two Haskell code blocks from Readme.md and verify they match
# the actual example/ source files. This ensures the README stays in sync.
let
  readme = ../Readme.md;
  exampleModel = ../example/Model.hs;
  exampleMain = ../example/Main.hs;
in
pkgs.runCommand "test-readme-example" {} ''
  # Extract haskell code blocks from README (there are exactly two)
  ${pkgs.gawk}/bin/awk '
    /^```haskell/ { capture=1; block++; next }
    /^```/        { capture=0; next }
    capture && block==1 { print >> "readme-model.hs" }
    capture && block==2 { print >> "readme-main.hs" }
  ' ${readme}

  echo "Checking Model.hs matches README..."
  diff readme-model.hs ${exampleModel}

  echo "Checking Main.hs matches README..."
  diff readme-main.hs ${exampleMain}

  echo "README examples match example/ source files."
  mkdir -p $out
  echo "ok" > $out/result
''
