This derivation allows use of EXLlama in Poetry2Nix or similar, by producing a Python package for inclusion into an env.

To build, run one of the following:
When checked out:
```bash
nix build github:TheseusInstitute/nix-exllama#onCuda118.onPython310.env -L --impure

# Or, to build a derivation without the wrapping env:
nix build github:TheseusInstitute/nix-exllama#onCuda118.onPython310.derive -L --impure
```

Directly from the flake
```bash
nix build --file ./default.nix -L 'onPython3.onCuda118'`
```

From the repository, for use in a derivation:
```nix
fetchFromGitHub {
  owner = "TheseusInstitute";
  repo = "nix-exllama";
  rev = "<...commit hash...>";
  hash = ""; # Leave this blank, run your build, and add the hash shown in the outputs
}
```

You can build a python environment and delve into it:
```bash
nix develop --file ./default.nix 'onCuda118.onPython311.env' -L
```

Or use something like the following to run the WebUI directly, without needing to clone the repository:
```bash
nix develop github:TheseusInstitute/nix-exllama#onCuda118.onPython310.env -L --impure --command \
  python -m exllama.webui.app \
    -m /opt/models/theseus/wzh-5000-4bit-128g/gptq_model-4bit-128g.safetensors \
    -c /opt/models/theseus/wzh-5000-4bit-128g/config.json \
    -t /opt/models/hf/vicuna1.1-13B/tokenizer.model \
    --host 0.0.0.0:7862
```

Many variations of Cuda and Python are included, though only Python 3.10 and Cuda 11.8 have been tested.
