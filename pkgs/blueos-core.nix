# Python virtualenv for the BlueOS services from core/uv.lock
{
  lib,
  callPackage,
  python311,
  systemd,
  blueos,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:
let
  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = blueos + "/core"; };

  overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  # uv.lock has no wheel for these, so they build from sdist
  setuptools =
    final: prev: name:
    prev.${name}.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ final.resolveBuildSystem { setuptools = [ ]; };
    });

  overrides = final: prev: {
    aiohttp = setuptools final prev "aiohttp";
    psutil = setuptools final prev "psutil";
    pyrsistent = setuptools final prev "pyrsistent";
    python-multipart = setuptools final prev "python-multipart";
    smbus2 = setuptools final prev "smbus2";
    pydantic = setuptools final prev "pydantic";
    sdbus = prev.sdbus.overrideAttrs (old: {
      buildInputs = (old.buildInputs or [ ]) ++ [ systemd ];
    });
  };

  pythonSet =
    (callPackage pyproject-nix.build.packages { python = python311; }).overrideScope
      (
        lib.composeManyExtensions [
          pyproject-build-systems.overlays.default
          overlay
          overrides
        ]
      );
in
pythonSet.mkVirtualEnv "blueos-core-env" workspace.deps.default
