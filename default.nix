{
  nixpkgs ? import <nixpkgs> {},
  callPackage ? nixpkgs.callPackage,
  ...
}@args:
let
  pkgs = nixpkgs // args;
  pythonVersions = [
    "3"
    "3.10"
    "3.11"
  ];
  withPythonVersion = version: basePackage:
    let version_string_suffix = builtins.replaceStrings ["."] [""] version;
    in {
      name = "onPython${version_string_suffix}";
      value =
        let python = builtins.getAttr "python${version_string_suffix}" pkgs; in
        basePackage.override({
          pythonPackages = python.pkgs;
          inherit (python.pkgs) buildPythonPackage;
        });
    };
  withPythonVersions = pythonVersions: basePackage:
    builtins.listToAttrs (map (version: withPythonVersion version basePackage) pythonVersions);
  cudaVersions = [
    "10"
    "11.6"
    "11.7"
    "11.8"
    "12.0"
    "12.1"
    "12.2"
  ];
  withCudaVersion = version: basePackage:
    let version_string_suffix = builtins.replaceStrings ["."] ["_"] version;
    in {
      name = "onCuda${builtins.replaceStrings ["_"] [""] version_string_suffix}";
      value =
        let cudaPackages = builtins.getAttr "cudaPackages_${version_string_suffix}" pkgs; in
        basePackage.override({
          cudaPackages = cudaPackages;
        });
    };
  withCudaVersions = cudaVersions: basePackage:
    builtins.listToAttrs (map (version: withCudaVersion version basePackage) cudaVersions);

  defaultPythonVersion = "3.10";
  defaultCudaVersion = "11.8";

  argSmush = f: args: {
    derive = f args;
    env =
      nixpkgs.mkShell {
        packages = [
          (args.pythonPackages.python
            .buildEnv
            .override {
              extraLibs = [ (f args) ];
              ignoreCollisions = true;
            }
          )
        ];
      };
    override = modArgs: argSmush f (args // modArgs);
    outPath = f args;
  };

  basePackage = argSmush (callPackage ./exllama.nix) {
    pythonPackages = pkgs.python310.pkgs;
    buildPythonPackage = pkgs.python310.pkgs.buildPythonPackage;
    cudaPackages = pkgs.cudaPackages_11_8;
  };
  ctors = [
    (withPythonVersions pythonVersions)
    (withCudaVersions cudaVersions)
  ];

  permutations = xs:
    if xs == [] then [] else
      if (builtins.length xs) == 1 then [xs] else
        let
          head = builtins.head xs;
          tail = builtins.tail xs;
          center = (permutations tail);
        in
        (map (z: [head] ++ z) center) ++ (map (z: z ++ [head]) center);

  chainCtors = ctors: base:
    assert builtins.isList ctors;
    if ctors == []
    then base
    else
      let
        head = builtins.head ctors;
        tail = builtins.tail ctors;
        constructedSet = (head base);
      in
      builtins.mapAttrs (k: newBase: assert builtins.isString k; chainCtors tail newBase) constructedSet;

  ctorPerms = (permutations ctors);
in
{
  inherit basePackage defaultPythonVersion defaultCudaVersion withPythonVersion withCudaVersion;
  inherit ctorPerms;
} // (builtins.foldl'
  (memo: next: memo // next)
  {}
  (map (ctors: chainCtors ctors basePackage) ctorPerms)
)
