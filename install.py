#!/bin/env python3
import hashlib
from pathlib import Path
import datetime as dt
import shutil
import subprocess
from typing import *
import sys
import time
from typing import TextIO

def x(command: str) -> str:
	p = subprocess.Popen(["bash", "-c", command], stdout=subprocess.PIPE)
	p.wait()
	assert p.stdout is not None
	return p.stdout.read().decode().strip()

HOME = Path(f"/home/{x('id -un')}")
BACKUP_PATH = Path(f".bak/{dt.datetime.now().strftime('%Y-%m-%d')}-{int(time.time()*1000)}")
BACKUP_PATH.mkdir(exist_ok=True, parents=True)

if len(sys.argv) == 2:
	HOME = Path(sys.argv[1])

DF_PATH = Path(__file__).parent # DOT_FILE_PATH

def copy_config(src: Path, dest: Path, mkdir: bool = True):
	if mkdir:
		dest.parent.mkdir(exist_ok=True, parents=True)
	if dest.exists():
		print(dest, "already exists. skipping")
		return
		sha = hashlib.sha256(dest.read_bytes()).hexdigest()
		shutil.copy(dest, BACKUP_PATH/(sha + '_' + dest.name))
	dest.write_text(src.read_text())


def copy_xdg_config(config_path: Union[str, Path], flatten: bool = False):
	config_path = Path(config_path)
	PARENT = HOME/'.config'
	if flatten:
		DEST = PARENT/config_path.name
	else:
		DEST = PARENT/config_path
	SRC = DF_PATH/config_path
	copy_config(SRC, DEST)

def copy_home_config(config_path: Union[str, Path], flatten: bool = False):
	config_path = Path(config_path)
	if flatten:
		DEST = HOME/config_path.name
	else:
		DEST = HOME/config_path
	SRC = DF_PATH/config_path
	copy_config(SRC, DEST)

# CONFIGS
copy_xdg_config("i3/config")
copy_xdg_config("starship/starship.toml")
copy_xdg_config("alacritty/alacritty.yml")
copy_xdg_config("fish/config.fish")
copy_xdg_config("fish/fish_variables")
copy_xdg_config("poetry/config.toml")
copy_xdg_config("starship/starship.toml", True)
copy_xdg_config("code/keybindings.json", True)

copy_config(DF_PATH/"code/keybindings.json", HOME/".config/Code/User/keybindings.json")
copy_config(DF_PATH/"code/settings.json", HOME/".config/Code/User/settings.json")

copy_home_config("tmux/.tmux.conf", True)
copy_home_config("bash/.bashrc", True)
copy_home_config("git/.gitconfig", True)
