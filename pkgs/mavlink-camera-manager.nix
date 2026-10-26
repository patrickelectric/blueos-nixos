# Release binary, dynamically linked against GStreamer 1.28
{ stdenv, fetchurl, autoPatchelfHook, glib, gst_all_1 }:
stdenv.mkDerivation {
  pname = "mavlink-camera-manager";
  version = "t3.26.3";
  src = fetchurl {
    url = "https://github.com/mavlink/mavlink-camera-manager/releases/download/t3.26.3/mavlink-camera-manager-aarch64";
    sha256 = "d9dc9d8c1321b2e8f3a73f03b17d34430793edc8aae1ca718d415daaab7634f3";
  };
  dontUnpack = true;
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    stdenv.cc.cc.lib
    glib
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-rtsp-server
  ];
  installPhase = ''
    install -Dm755 $src $out/bin/mavlink-camera-manager
  '';
}
