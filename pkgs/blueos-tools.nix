# Release binaries, same versions as core/tools/*/bootstrap.sh at BlueOS 1.4.7
{ stdenv, fetchurl, autoPatchelfHook, udev }:
let
  bin = name: url: sha256: {
    inherit name;
    src = fetchurl { inherit url sha256; };
  };
  bins = [
    (bin "mavlink2rest" "https://github.com/mavlink/mavlink2rest/releases/download/0.11.28/mavlink2rest-aarch64-unknown-linux-musl"
      "d027ed044fe51b39df3be74286ca36dac0c5384ab9f709be1bcf7f8e8a27d1d1")
    (bin "mavlink-server" "https://github.com/bluerobotics/mavlink-server/releases/download/0.11.1/mavlink-server-aarch64-unknown-linux-musl"
      "e80d6113329e47ed73473c0cd0d793a711b5d60d13b3538532051be26941efcf")
    (bin "linux2rest" "https://github.com/patrickelectric/linux2rest/releases/download/v0.6.5/linux2rest-aarch64-unknown-linux-gnu"
      "d3576dcd1b1d124c4ad6e7463af166b0c3380ccc8ab8c74dd5afc6dac828e74a")
    (bin "bridges" "https://github.com/patrickelectric/bridges/releases/download/0.10.3/bridges-aarch64-unknown-linux-musl"
      "0e3595ca3cfa93d1d4a0a85ca1abe3218d469413e4215446cafbce36feba8ba2")
    (bin "machineid-cli" "https://github.com/patrickelectric/machineid-cli/releases/download/0.2.3/machineid-cli-aarch64-unknown-linux-musl"
      "531c512aee535b826155c9e1e2448eae902eb293048c7360eeaf981d948734d4")
  ];
in
stdenv.mkDerivation {
  pname = "blueos-tools";
  version = "1.4.7";
  dontUnpack = true;
  # linux2rest is glibc dynamic, the others are static
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib udev ];
  installPhase = ''
    mkdir -p $out/bin
    ${builtins.concatStringsSep "\n" (map (b: "install -m755 ${b.src} $out/bin/${b.name}") bins)}
  '';
}
