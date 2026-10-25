# BlueOS releases ship no frontend bundle, only the docker image that contains it.
{ stdenvNoCC, fetchurl, jq }:
stdenvNoCC.mkDerivation {
  pname = "blueos-frontend";
  version = "1.4.7";

  src = fetchurl {
    url = "https://github.com/bluerobotics/BlueOS/releases/download/1.4.7/BlueOs-core-docker-image-2b918ed7-arm64-v8.tar";
    sha256 = "015d8e50f831fcdf2457031507bd1613063d04363be352e91afce413e7b59462";
  };

  nativeBuildInputs = [ jq ];
  dontUnpack = true;

  buildPhase = ''
    mkdir image
    tar -xf $src -C image
    # layers are applied in order, most of them do not contain the frontend
    for layer in $(jq -r '.[0].Layers[]' image/manifest.json); do
      tar -xf image/$layer home/pi/frontend 2>/dev/null || true
    done
  '';

  installPhase = ''
    cp -r home/pi/frontend $out
  '';
}
