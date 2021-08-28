#!/bin/env python3
from pathlib import Path
import subprocess
from typing import *
import sys
from typing import TextIO

def x(command: str) -> str:
	p = subprocess.Popen(["bash", "-c", command], stdout=subprocess.PIPE)
	p.wait()
	assert p.stdout is not None
	return p.stdout.read().decode().strip()

HOME = Path(f"/home/{x('id -un')}")

if len(sys.argv) == 2:
	HOME = Path(sys.argv[1])

DF_PATH = Path(__file__).parent # DOT_FILE_PATH


def copy_xdg_config(config_path: Union[str, Path]):
	config_path = Path(config_path)
	DEST = HOME/'.config'/config_path
	SRC = DF_PATH/config_path
	DEST.parent.mkdir(exist_ok=True, parents=True)
	DEST.write_text(SRC.read_text())

def copy_home_config(config_path: Union[str, Path]):
	config_path = Path(config_path)
	DEST = HOME/config_path.name
	SRC = DF_PATH/config_path
	DEST.write_text(SRC.read_text())

FISH_STARTER = """
if [[ $(ps --no-header --pid=$PPID --format=cmd) != "fish" ]]
then
		exec fish
fi
"""

copy_xdg_config("i3/config")
copy_xdg_config("alacritty/alacritty.yml")
copy_xdg_config("fish/config.fish")
copy_xdg_config("fish/fish_variables")
copy_home_config("tmux/.tmux.conf")
copy_home_config("bash/.bashrc")
