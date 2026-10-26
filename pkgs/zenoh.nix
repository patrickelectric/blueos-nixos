# zenohd 1.0.0 with its plugins, as core/tools/zenoh/bootstrap.sh at BlueOS 1.4.7
{ stdenv, fetchurl, unzip, autoPatchelfHook }:
stdenv.mkDerivation {
  pname = "zenoh";
  version = "1.0.0";
  src = fetchurl {
    url = "https://download.eclipse.org/zenoh/zenoh/1.0.0/zenoh-1.0.0-aarch64-unknown-linux-gnu-standalone.zip";
    sha256 = "e3b213e38dcf7b3298e7dd78b18f0ce8866f5b43fb008b7aa44efb4c74959006";
  };
  nativeBuildInputs = [ unzip autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  sourceRoot = ".";
  installPhase = ''
    install -Dm755 zenohd $out/bin/zenohd
    install -Dm644 -t $out/lib *.so
  '';
}
