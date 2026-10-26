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
  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = /. + "${blueos}/core"; };

  overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  # uv.lock has no wheel for these, so they build from sdist
  setuptools =
    final: name:
    final.${name}.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ final.resolveBuildSystem { setuptools = [ ]; };
    });

  overrides = final: prev: {
    aiohttp = setuptools final "aiohttp";
    psutil = setuptools final "psutil";
    pyrsistent = setuptools final "pyrsistent";
    python-multipart = setuptools final "python-multipart";
    smbus2 = setuptools final "smbus2";
    pydantic = setuptools final "pydantic";
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
