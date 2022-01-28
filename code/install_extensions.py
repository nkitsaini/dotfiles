#!/bin/env python3

import os
from concurrent.futures import ProcessPoolExecutor, process

extensions = [
	"vscodevim.vim",
	"eamodio.gitlens",
	"ms-kubernetes-tools.vscode-kubernetes-tools",
	"shd101wyy.markdown-preview-enhanced",
	"redhat.vscode-yaml",
	"foxundermoon.shell-format",
	"ms-azuretools.vscode-docker",
	"github.github-vscode-theme",
	"ms-python.python",
	"ms-vscode-remote.remote-containers",
	"ms-vscode-remote.remote-ssh",
	"matklad.rust-analyzer",
	"svelte.svelte-vscode",
	"bradlc.vscode-tailwindcss",
]


def installation_command(extension_id: str) -> str:
	return f"code --install-extension {extension_id}"


def install_extension(extension_id: str):
	os.system(installation_command(extension_id))


if __name__ == "__main__":
	with ProcessPoolExecutor() as p:
		p.map(install_extension, extensions)
