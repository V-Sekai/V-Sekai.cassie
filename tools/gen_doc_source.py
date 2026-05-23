"""Wrapper around godot-cpp/doc_source_generator.py that takes a
positional output path followed by N input XML paths. Used by
CMakeLists.txt to bypass godot-cpp 4.4's broken target_doc_sources
helper (its inline `python -c` invocation eats the call line on
Windows, so doc_source.cpp is never written despite the build
reporting success)."""

import sys
import os

if len(sys.argv) < 3:
    sys.stderr.write("usage: gen_doc_source.py <godot-cpp-dir> <output.cpp> <xml> [xml ...]\n")
    sys.exit(2)

godot_cpp_dir = sys.argv[1]
output_path = sys.argv[2]
xml_files = sys.argv[3:]

sys.path.insert(0, godot_cpp_dir)
os.chdir(godot_cpp_dir)

from doc_source_generator import generate_doc_source

generate_doc_source(output_path, xml_files)
print(f"Generated {output_path} from {len(xml_files)} XML file(s)")
