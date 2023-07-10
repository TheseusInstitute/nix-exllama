{
  lib,
  config,
  autoPatchelfHook,
  fetchFromGitHub,
  buildPythonPackage,
  pythonPackages,
  cudaPackages,
  blas,
  ninja,
  pkg-config,
  gnused,
  which,
  writeTextFile,

  noWebUI ? false,
  __contentAddressed ? false,
}:

let
  inherit (lib.attrsets) optionalAttrs;
  inherit (cudaPackages) cudatoolkit;
  inherit (cudatoolkit) cc;

  contentAddressingSpecifier = optionalAttrs (__contentAddressed == true) {
    inherit __contentAddressed;
  };

in
assert config.cudaSupport;
assert config.allowUnfree;
(buildPythonPackage (contentAddressingSpecifier // rec {
  pname = "exllama";
  version = "0.0.1.dev20230710";

  outputs = ["dev" "lib" "out"];

  format = "setuptools";

  src = fetchFromGitHub {
    owner = "turboderp";
    repo = "exllama";
    rev = "e61d4d31d44bd4dd3380fc773509c870ba74cb9f";
    hash = "sha256-cx5M15WiyrSV8X29nufZU+JC8gRJAhdoeN2sJuIEFkg=";
  };

  buildInputs = [
    pythonPackages.setuptools
  ];

  propagatedBuildInputs = (with pythonPackages; [
    torch
    bitsandbytes
    safetensors
    sentencepiece
  ]) ++ [
    blas
  ] ++ (lib.optionals (!noWebUI) passthru.optional-dependencies.complete);

  nativeBuildInputs = [
    pkg-config
    autoPatchelfHook
    pythonPackages.pythonRelaxDepsHook
    ninja
    which
    cudaPackages.cudatoolkit.cc
    cudaPackages.cudatoolkit
  ];

  sourceRoot = ".";

  postUnpack = ''
    # Nest the directory so we can make an outer package "project"
    mv source exllama
    mkdir source
    mv exllama source/
    cd source
    # Now we're in `source/` with an `./exllama/*` child directory
    mv exllama/requirements*.txt .
    # Add init files to each directory we want to be a (sub)package
    touch "__init__.py"
    touch "exllama/__init__.py"
    touch "exllama/webui/__init__.py"

    substituteInPlace exllama/cuda_ext.py  \
      --replace "exllama_ext = load" "import exllama_ext #"

    substituteInPlace exllama/*.py exllama/webui/*.py  \
      ${builtins.concatStringsSep ""
        (map
          (mod:
            ''
            --replace "import ${mod}." "Zmport exllama.${mod}." \
            --replace "import ${mod}" "from exllama Zmport ${mod}" \
            --replace "from ${mod} import" "from exllama.${mod} Zmport" \
            '')
          [
            "cuda_ext"
            "example_basic"
            "example_batch"
            "example_chatbot"
            "example_flask"
            "example_lora"
            "generator"
            "lora"
            "model_init"
            "model"
            "perplexity"
            "test_benchmark_inference"
            "tokenizer"
            "webui"
          ]
        )} --replace "Zmport" "import" 2>/dev/null
    substituteInPlace exllama/webui/*.py  \
      ${builtins.concatStringsSep ""
        (map
          (mod:
            ''
            --replace "import ${mod}." "Zmport exllama.webui.${mod}." \
            --replace "import ${mod}" "from exllama.webui Zmport ${mod}" \
            --replace "from ${mod} import" "from exllama.webui.${mod} Zmport" \
            '')
          [
            "app"
            "session"
          ]
        )} --replace "Zmport" "import" 2>/dev/null

    # Wipe the bit that compiles the cuda extension at runtime out entirely
    "${lib.getBin gnused}/bin/sed" \
      '/^# another kludge/,/^\(# \|\)from exllama_ext/{/^import /!{/^from /!d;};}' \
      exllama/cuda_ext.py -i

    cp "${writeTextFile {
      name = "${pname}-setup.py";
      executable = true;
      text = ''
        #!/usr/bin/env python
        from setuptools import setup, find_packages
        from pathlib import Path
        import os
        import platform
        import sys



        with open("requirements.txt") as f:
          install_requires = f.read().splitlines()


        library_dir = Path("./exllama")

        common = {
          "name":"${pname}",
          "packages":["${pname}", "${pname}.webui"],
          "version":"${version}",
          "author":"${src.owner}",
          "install_requires":install_requires,
          "package_data": {
            "${pname}.webui": ["${pname}/webui/templates/*", "${pname}/webui/static/*"],
          },
          "include_package_data": True,
        }

        if os.getenv("CUDA_HOME") is not None:
          import torch
          from torch.cuda.amp import custom_bwd, custom_fwd
          from torch.utils import cpp_extension

          extension_dir = library_dir / "exllama_ext"

          extension_name = "exllama_ext"
          extensions = [
            cpp_extension.CUDAExtension(
              name = extension_name,
              sources = [str(extension_dir / x) for x in (
                "exllama_ext.cpp",
                "cpu_func/rep_penalty.cpp",
                "cuda_buffers.cu",
                "cuda_func/column_remap.cu",
                "cuda_func/half_matmul.cu",
                "cuda_func/q4_attn.cu",
                "cuda_func/q4_matmul.cu",
                "cuda_func/q4_matrix.cu",
                "cuda_func/q4_mlp.cu",
                "cuda_func/rms_norm.cu",
                "cuda_func/rope.cu",
              )],
              extra_include_paths = [library_dir / "exllama_ext"],
              verbose = True,
              extra_ldflags = [],
              extra_cuda_cflags = ["-lineinfo"] + (["-U__HIP_NO_HALF_CONVERSIONS__", "-O3"] if torch.version.hip else []),
            )
          ]

          common.update({
            "ext_modules": extensions,
            "cmdclass": {
              "build_ext": cpp_extension.BuildExtension,
            }
          })

        setup(
          include_dirs=["exllama_ext"],
          **common
        )
      '';
    }}" "setup.py"
  '';

  preConfigure = ''
    export CC="${lib.getBin cc}/bin/cc";
    export CXX="${lib.getBin cc}/bin/c++";
    export NIX_LDFLAGS="-L${lib.getLib cudatoolkit}/lib"
  '';

  postInstall = let inherit (pythonPackages) python; sitePkgs = python.sitePackages; in ''
    ls -al .
    shopt -s nullglob
    mkdir -p "$lib/lib"
    for i in $out/${sitePkgs}/exllama/lib/*.so; do
      filename="''${i${"##"}*/}"
      mv $i "$lib/lib/$filename"
      ln -s "$lib/lib/$filename" "$out/${sitePkgs}/exllama/lib/$filename"
    done
    for i in $out/${sitePkgs}/exllama/*.so; do
      filename="''${i${"##"}*/}"
      mv $i "$lib/lib/$filename"
      ln -s "$lib/lib/$filename" "$out/${sitePkgs}/exllama/$filename"
    done
    for i in $out/${sitePkgs}/*.so; do
      filename="''${i${"##"}*/}"
      mv $i "$lib/lib/$filename"
      ln -s "$lib/lib/$filename" "$out/${sitePkgs}/$filename"
    done
    ln -s "$lib/lib" "$out/${sitePkgs}/exllama/lib"
    ln -s "$out/${sitePkgs}/exllama" "$dev"
    echo "curdir is $(pwd)"
    ls -al .
    cp -R "exllama/webui/static" "$dev/webui/"
    cp -R "exllama/webui/templates" "$dev/webui/"
    ls -al "$dev/webui"
    echo "Copied webui resources"
  '';

  pythonImportsCheck = [
    "${pname}"
    "${pname}.model"
    "${pname}.generator"
    "${pname}.lora"
    "${pname}.cuda_ext"
  ];

  pythonRemoveDeps = [
    "ninja" # Used during torch cpp_extension build, which is only needed at build-time in Nix
  ];

  CUDA_HOME = "${cudatoolkit}";
  NVCC_PREPEND_FLAGS="-Wno-deprecated-declarations --verbose";
  TORCH_CUDA_ARCH_LIST=
    let torchFlags = pythonPackages.torch.passthru; in
    if (torchFlags ? gpuTargetString)
      then torchFlags.gpuTargetString
      else "${toString cudaPackages.cudaFlags.cudaCapabilities}";

  passthru = {
    optional-dependencies = rec {
      webui = with pythonPackages; [
        flask
        waitress
      ];
      complete = webui;
    };
  };

  dontUseSetuptoolsCheck = true;
  preferWheel = false;

})).overrideAttrs(self: super: {
  pythonImportsCheck = super.pythonImportsCheck ++ lib.optionals (builtins.elem pythonPackages.flask self.propagatedBuildInputs) [
    "${self.pname}.webui"
    "${self.pname}.webui.session"
    "${self.pname}.webui.app" # Requires cuda to actually run
  ];
})
