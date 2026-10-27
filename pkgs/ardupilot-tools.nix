# The three ArduPilot scripts core/tools/ardupilot_tools/setup-python-libs.sh downloads at BlueOS 1.4.7
{
  runCommand,
  fetchurl,
  python,
}:
let
  script =
    commit: file: sha256:
    fetchurl {
      url = "https://raw.githubusercontent.com/ArduPilot/ardupilot/${commit}/Tools/scripts/${file}";
      inherit sha256;
    };
  uploader = script "f6544ca25ab232407ec102b7a5adf0adca0f2062" "uploader.py"
    "c13464f251474fe89da35412890377db8dbedbc47f4f081dff897a515da21061";
  decoder = script "89c2b4828662ece84f48bdf9aa24db688fea36cb" "firmware_version_decoder.py"
    "6d7518bf7d66c051f97edcd19fd967d2fabf4d26687dc659a1e8a9e6bf00c7e8";
  apjTool = script "b839ddcc00f4cb89d89aaa8cf0cb03298d2f00b4" "apj_tool.py"
    "b96e9a1fa7a3d3d84f2d763cdceecec76e4b9b8d4390a7cd78df4ebd72714924";
in
runCommand "ardupilot-tools" { } ''
  mkdir -p $out/bin $out/lib/python
  install -m755 ${uploader} $out/bin/ardupilot_fw_uploader.py
  install -m755 ${apjTool} $out/bin/apj_tool.py
  install -m644 ${decoder} $out/lib/python/ardupilot_fw_decoder.py
  # pyserial and pyelftools live in the venv, not in any system python
  sed -i "1s|.*|#!${python}/bin/python|" $out/bin/*.py
''
