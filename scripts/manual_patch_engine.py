# ==============================================
#  MANUAL PATCH ENGINE — applies by reading source,
#  not by relying on external .patch files (robust
#  across kernel versions, defconfig differences,
#  and structural variations in 4.4 / 5.x / 6.x).
#  Skip firewall (UFW/Fail2ban) optional per user.
# ==============================================

PATCH_MANUAL_MAP = {
    "xt_qtaguid_panic": {
        "file": "net/netfilter/xt_qtaguid.c",
        "func_target": "iface_stat_fmt_proc_show",
        "edits": [
            ("replace_block", {
                "find": "\tstruct rtnl_link_stats64 dev_stats, *stats;\n\tstruct rtnl_link_stats64 no_dev_stats = {0};",
                "replace": "\tstruct rtnl_link_stats64 *stats;\n\tstruct rtnl_link_stats64 no_dev_stats = {0};",
            }),
            ("replace_block", {
                "find": "\tif (iface_entry->active) {\n\t\tstats = dev_get_stats(iface_entry->net_dev,\n\t\t\t\t      &dev_stats);\n\t} else {\n\t\tstats = &no_dev_stats;\n\t}\n",
                "replace": "\tstats = &no_dev_stats;\n\n",
            }),
        ],
        "check": lambda src_path: (src_path / "net/netfilter/xt_qtaguid.c").exists(),
    },
    "cgroup_noprefix_link": {
        # 4.x: kernel/cgroup.c ; 5.x+: kernel/cgroup/cgroup.c
        "file_candidates": ["kernel/cgroup/cgroup.c", "kernel/cgroup.c"],
        "func_target": "cgroup_add_file",
        "edits": [
            ("insert_after", {
                "find_anchor": "if (IS_ERR(kn))\n\t\treturn PTR_ERR(kn);\n",
                "insert": '\t// Droidspaces/LXC: restore cgroup file prefix handling for NOPREFIX roots\n\tif (cft->ss && (cgrp->root->flags & CGRP_ROOT_NOPREFIX) && !(cft->flags & CFTYPE_NO_PREFIX)) {\n\t\tchar pname[CGROUP_FILE_NAME_MAX];\n\t\tsnprintf(pname, CGROUP_FILE_NAME_MAX, "%s.%s", cft->ss->name, cft->name);\n\t\tkernfs_create_link(cgrp->kn, pname, kn);\n\t}\n',
            }),
        ],
        "check": lambda src_path: any((src_path / f).exists() for f in ("kernel/cgroup/cgroup.c", "kernel/cgroup.c")),
        "_resolved_file": None,  # cached after first resolution
    },
}


def _resolve_target_file(info, src_path):
    """Return absolute target file path, picking from file_candidates."""
    if "file_candidates" in info:
        cached = info.get("_resolved_file")
        if cached and (src_path / cached).exists():
            return src_path / cached
        for cand in info["file_candidates"]:
            if (src_path / cand).exists():
                info["_resolved_file"] = cand
                return src_path / cand
        # None exist
        return None
    return src_path / info["file"]


def manual_patch_edit(src_path, edit_key, dry_run=False):
    info = PATCH_MANUAL_MAP.get(edit_key)
    if not info:
        return {"applied": False, "skipped": False, "failed": True, "message": f"Unknown edit_key: {edit_key}"}
    if not info["check"](src_path):
        candidates = info.get("file_candidates") or [info["file"]]
        return {"applied": False, "skipped": True, "failed": False, "message": f"Source file missing for edit: tried {candidates} (skipped safely)"}
    target_file = _resolve_target_file(info, src_path)
    actual_relpath = str(target_file.relative_to(src_path)) if target_file else info["file"]
    if target_file is None:
        return {"applied": False, "skipped": True, "failed": False, "message": f"No candidate source file exists for {edit_key} (skipped safely)"}
    if dry_run:
        return {"applied": False, "skipped": False, "failed": False, "message": f"Dry-run: would edit {actual_relpath} for {edit_key}", "dry_run": True}
    try:
        text = target_file.read_text()
    except Exception as e:
        return {"applied": False, "skipped": False, "failed": True, "message": f"Read error {target_file}: {e}"}
    original = text
    changed = False
    for edit in info.get("edits", []):
        op, params = edit
        if op == "replace_block":
            find_s = params.get("find", "")
            replace_s = params.get("replace", "")
            if find_s not in text:
                continue
            text = text.replace(find_s, replace_s, 1)
            changed = True
        elif op == "insert_after":
            find_anchor = params.get("find_anchor", "")
            insert_s = params.get("insert", "")
            if find_anchor not in text:
                continue
            text = text.replace(find_anchor, find_anchor + insert_s, 1)
            changed = True
    if text == original:
        return {"applied": False, "skipped": True, "failed": False, "message": f"No changes needed for {edit_key} (already applied or different structure)"}
    try:
        target_file.write_text(text)
        return {"applied": True, "skipped": False, "failed": False, "message": f"Manual edit applied to {actual_relpath} ({edit_key})"}
    except Exception as e:
        return {"applied": False, "skipped": False, "failed": True, "message": f"Write error: {e}"}


def resolve_manual_patches(is_gki_flag):
    if is_gki_flag:
        return []
    return ["xt_qtaguid_panic", "cgroup_noprefix_link"]


def apply_all_manual_patches(src_path, is_gki_flag, dry_run, skip_patch):
    if skip_patch:
        return {"results": [], "applied": 0, "skipped": 0, "failed": 0}
    keys = resolve_manual_patches(is_gki_flag)
    results = []
    for k in keys:
        res = manual_patch_edit(src_path, k, dry_run=dry_run)
        res["file"] = k
        results.append(res)
    applied = sum(1 for r in results if r.get("applied"))
    skipped = sum(1 for r in results if r.get("skipped"))
    failed = sum(1 for r in results if r.get("failed"))
    return {"results": results, "applied": applied, "skipped": skipped, "failed": failed}

