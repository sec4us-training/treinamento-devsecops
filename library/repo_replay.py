#!/usr/bin/python
# -*- coding: utf-8 -*-

DOCUMENTATION = r'''
---
module: repo_replay
short_description: Extract a git repo's history into per-commit ZIPs + JSON, or rebuild a repo from that dump.
description:
  - Lab utility that captures a repository's commit history into a portable format
    (per-commit ZIPs plus a C(commits.json) manifest) and can replay it into a
    fresh repository, preserving author/committer identities and dates.
  - Useful for staging "from scratch" exercises where each commit needs to be
    reviewable individually.
options:
  action:
    description: Operation to perform.
    type: str
    choices: [extract, rebuild]
    required: true
  source:
    description: Git URL or local path. Required when O(action=extract).
    type: str
  output:
    description: Output directory that will hold C(repo/), C(zips/) and C(commits.json). Required when O(action=extract).
    type: path
  input:
    description: Directory produced by a prior extract run. Required when O(action=rebuild).
    type: path
  target:
    description: Empty directory that will receive the rebuilt repository. Required when O(action=rebuild).
    type: path
  force:
    description:
      - When O(action=extract), wipe an existing C(repo/) clone before re-cloning (always done).
      - When O(action=rebuild), allow rebuilding into a non-empty O(target) by deleting its contents first.
    type: bool
    default: false
requirements:
  - git available on PATH
author:
  - Helvio Junior - Sec4US
'''

EXAMPLES = r'''
- name: Dump bank repo history
  repo_replay:
    action: extract
    source: "https://{{ gitlab_host }}/sec4us/bank.git"
    output: /tmp/bank-dump

- name: Rebuild bank repo from dump
  repo_replay:
    action: rebuild
    input: /tmp/bank-dump
    target: /tmp/bank-new
'''

RETURN = r'''
commits:
  description: Number of commits processed.
  type: int
  returned: success
path:
  description: Resolved output (extract) or target (rebuild) directory.
  type: str
  returned: success
'''

import json
import os
import shutil
import zipfile
from pathlib import Path

from ansible.module_utils.basic import AnsibleModule


SEP = "\x1f"  # unit separator — safe delimiter for git format fields


def _run(module, cmd, cwd=None, environ_update=None):
    rc, out, err = module.run_command(cmd, cwd=cwd, environ_update=environ_update)
    if rc != 0:
        module.fail_json(
            msg="command failed: %s" % " ".join(cmd),
            rc=rc, stdout=out, stderr=err, cwd=str(cwd) if cwd else None,
        )
    return out


def _git(module, args, cwd, environ_update=None):
    return _run(module, ["git", *args], cwd=cwd, environ_update=environ_update)


def do_extract(module, source, output):
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)

    clone_dir = output / "repo"
    zips_dir = output / "zips"
    zips_dir.mkdir(exist_ok=True)
    metadata_path = output / "commits.json"

    if clone_dir.exists():
        shutil.rmtree(clone_dir)

    _run(module, ["git", "clone", source, str(clone_dir)])

    log_out = _git(module, ["log", "--reverse", "--pretty=format:%H"], cwd=clone_dir)
    shas = log_out.strip().splitlines()

    commits = []
    for idx, sha in enumerate(shas, 1):
        fmt = SEP.join(["%H", "%an", "%ae", "%aI", "%cn", "%ce", "%cI", "%P", "%s"])
        info = _git(module, ["show", "-s", "--format=" + fmt, sha], cwd=clone_dir)
        full_hash, an, ae, ad, cn, ce, cd, parents, subject = info.split(SEP, 8)
        body = _git(module, ["show", "-s", "--format=%b", sha], cwd=clone_dir).rstrip("\n")
        message = subject if not body else subject + "\n\n" + body

        name_status = _git(
            module,
            ["show", "--no-renames", "--pretty=format:", "--name-status", sha],
            cwd=clone_dir,
        ).strip().splitlines()

        files = []
        for line in name_status:
            line = line.strip()
            if not line:
                continue
            bits = line.split("\t")
            files.append({"status": bits[0], "path": bits[1]})

        # Checkout commit so the working tree reflects added/modified file contents.
        _git(module, ["checkout", "--quiet", "--detach", sha], cwd=clone_dir)

        zip_name = "%05d_%s.zip" % (idx, sha[:12])
        zip_path = zips_dir / zip_name
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for f in files:
                if f["status"].startswith("D"):
                    continue
                fs_path = clone_dir / f["path"]
                if not fs_path.exists() or not fs_path.is_file():
                    continue
                zf.write(fs_path, arcname=f["path"])

        commits.append({
            "index": idx,
            "hash": full_hash,
            "parents": parents.split() if parents else [],
            "author_name": an,
            "author_email": ae,
            "author_date": ad,
            "committer_name": cn,
            "committer_email": ce,
            "committer_date": cd,
            "subject": subject,
            "message": message,
            "files": files,
            "zip": str(zip_path.relative_to(output)),
        })

    metadata_path.write_text(json.dumps(commits, indent=2, ensure_ascii=False))
    return len(commits), str(output)


def do_rebuild(module, input_dir, target_dir, force):
    input_dir = Path(input_dir).resolve()
    target_dir = Path(target_dir).resolve()
    metadata_path = input_dir / "commits.json"
    if not metadata_path.exists():
        module.fail_json(msg="commits.json not found in %s" % input_dir)
    commits = json.loads(metadata_path.read_text())

    if target_dir.exists() and any(target_dir.iterdir()):
        if not force:
            module.fail_json(msg="%s is not empty — pass force=true to wipe" % target_dir)
        shutil.rmtree(target_dir)

    target_dir.mkdir(parents=True, exist_ok=True)

    _run(module, ["git", "init", "--quiet", str(target_dir)])

    for c in commits:
        zip_path = input_dir / c["zip"]

        # Apply deletions first.
        for f in c["files"]:
            if f["status"].startswith("D"):
                victim = target_dir / f["path"]
                if victim.exists():
                    victim.unlink()

        if zip_path.exists():
            with zipfile.ZipFile(zip_path) as zf:
                zf.extractall(target_dir)

        _git(module, ["add", "-A"], cwd=target_dir)

        staged = _git(module, ["diff", "--cached", "--name-only"], cwd=target_dir).strip()
        extra = ["--allow-empty"] if not staged else []

        env_update = {
            "GIT_AUTHOR_NAME": c["author_name"],
            "GIT_AUTHOR_EMAIL": c["author_email"],
            "GIT_AUTHOR_DATE": c["author_date"],
            "GIT_COMMITTER_NAME": c["committer_name"],
            "GIT_COMMITTER_EMAIL": c["committer_email"],
            "GIT_COMMITTER_DATE": c["committer_date"],
        }

        _git(
            module,
            ["commit", "--quiet", *extra, "-m", c["message"]],
            cwd=target_dir,
            environ_update=env_update,
        )

    return len(commits), str(target_dir)


def main():
    module = AnsibleModule(
        argument_spec=dict(
            action=dict(type='str', required=True, choices=['extract', 'rebuild']),
            source=dict(type='str'),
            output=dict(type='path'),
            input=dict(type='path'),
            target=dict(type='path'),
            force=dict(type='bool', default=False),
        ),
        required_if=[
            ('action', 'extract', ['source', 'output']),
            ('action', 'rebuild', ['input', 'target']),
        ],
        supports_check_mode=False,
    )

    action = module.params['action']
    try:
        if action == 'extract':
            count, where = do_extract(module, module.params['source'], module.params['output'])
        else:
            count, where = do_rebuild(
                module, module.params['input'], module.params['target'], module.params['force']
            )
    except Exception as e:
        module.fail_json(msg="unexpected error: %s" % e)

    module.exit_json(changed=True, commits=count, path=where)


if __name__ == "__main__":
    main()
