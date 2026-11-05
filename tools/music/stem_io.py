"""Shared by the music scripts: tell Godot how a stem loops and what its tempo is."""

import os


def write_import(path, loop, bpm, beats):
    """Write the stem's .import params, so AudioStreamInteractive can cut on its bars.
    Keeps the uid and paths of an existing .import file; Godot fills them in otherwise
    (run godot --headless --import after)."""
    params = {"loop": "true" if loop else "false", "loop_offset": "0", "bpm": str(bpm),
              "beat_count": str(beats), "bar_beats": "4"}
    imp = path + ".import"
    if os.path.exists(imp):
        lines = open(imp).read().split("\n")
        lines = [f"{l.split('=')[0]}={params[l.split('=')[0]]}" if l.split("=")[0] in params else l
                 for l in lines]
        text = "\n".join(lines)
    else:
        text = '[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n[params]\n\n'
        text += "".join(f"{k}={v}\n" for k, v in params.items())
    with open(imp, "w") as f:
        f.write(text)
