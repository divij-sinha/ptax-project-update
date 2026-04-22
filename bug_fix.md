# Bug Fixes

Batch generation of ~3.2M PTAX / TIF HTML reports via FastAPI + RQ + Redis with
60 concurrent Quarto renders. Fixes are ordered newest-first.

---

## 0. `sync` slower than rendering → local disk filling up

**Symptom.** `batch_generate.py sync` ran for 3+ hours and still had not
finished. Worse, workers kept producing new HTML on the local SSD faster
than sync could move files off to the NAS, so free space was *shrinking*
while sync ran.

**Root cause.** `_move_local_to_nas` processed every file serially: stat
destination → copy → verify size → delete local, one file at a time. NAS
I/O over SMB is latency-bound for small HTML files, so serial throughput
was a tiny fraction of what the network could actually carry.

**Fix.** Parallelize with a `ThreadPoolExecutor`:

- Phase 1 walks local once to enumerate `(src, dst, pair)` tuples.
- Phase 2 submits each to a worker pool (default 16, overridable via
  `SYNC_WORKERS` env var). Each worker does the copy/verify/delete for
  one file.
- Phase 3 prunes empty dirs bottom-up after the pool drains.
- Progress logs every 5000 files.

Threads (not processes) because the work is I/O-bound and releases the GIL
during the syscall — 16 threads is the sweet spot for most SMB mounts;
push higher via env var if the NAS can absorb more.

**To activate.** Kill the currently running sync and re-run with the new
code — restarting now will finish faster than letting the old serial run
grind out.

---

## 1. Quarto crossref INDEX corruption under concurrent renders

**Symptom.** After running fine for hours, every job started failing with:

```
ERROR: SyntaxError: Unexpected non-whitespace character after JSON at position 1508462
```

Thrown from Deno while Quarto was loading `.quarto/xref/INDEX`.

**Root cause.** Quarto maintains a single shared crossref index at
`<project>/.quarto/xref/INDEX` and mutates it with a read-modify-write cycle
that is **not** process-safe. Under 60 concurrent renders, two workers
eventually interleave their writes and leave trailing garbage behind the JSON
document, which then breaks every subsequent render.

The env var `QUARTO_CROSSREF_INDEX_PATH` can redirect the index to a unique
path *per render*, but it is only honored in Quarto's **single-file mode**.
Passing `--output-dir` forces Quarto into **project mode**, which ignores the
env var and falls back to the shared path. That is what the old code was
doing.

**Fix.** Each render now runs in its own isolated subdirectory. See
`app/main.py::run_quarto`:

- Copy the QMD into `_jobs/<mode>_<pin>/` and render it there (`cwd=job_dir`).
- Drop `--output-dir`; use `--output <filename>` only, so Quarto stays in
  single-file mode.
- Set `QUARTO_CROSSREF_INDEX_PATH=<job_dir>/xref.json` — unique per job.
- After the render, `shutil.move()` the HTML to the real output location and
  `rmtree()` the job dir.

Follow-on issues this introduced, and their fixes:

- **`_files/` not found by pandoc.** Using `--execute-dir` made the working
  directory diverge from where Quarto expected its sidecar files. Fix: drop
  `--execute-dir`, use `cwd=job_dir` instead, and have the QMD's setup chunk
  re-point R's working directory back to the project via
  `PTAX_PROJECT_ROOT` + `knitr::opts_knit$set(root.dir=...)` so relative
  `data/...` paths still resolve.
- **`there is no package called 'rmarkdown'`.** With `cwd=job_dir`, R's default
  `.Rprofile` discovery did not find the renv-activating `.Rprofile` at the
  project root. Fix: write a tiny per-job `.Rprofile` that
  `source()`s the project's `renv/activate.R` by absolute path.
- **renv using wrong library path.** renv resolved its library relative to
  `cwd` (`_jobs/.../renv/library/...`, which does not exist). Fix: set
  `RENV_PROJECT=<project_root>` in the subprocess env so renv's activate
  script anchors to the real project.

**Verification.** Single-PIN end-to-end render succeeds; output lands in
`outputs/v2.3/TIF/<pin>/<pin>.html`. Running workers must be restarted to
pick up the new code — the old workers still have the racy `run_quarto`
loaded in memory.

---

## 2. `check_pin_dt_str` intermittent failure for pin `03043071000000`

**Symptom.** Some PINs (always those with a leading zero) failed inside
`check_pin_dt_str` with a mismatch between a 14-digit string and what
actually came through.

**Root cause.** The PIN was being passed via `--execute-param pin_14=...`,
which Quarto feeds to R through YAML. YAML parsed `03043071000000` as an
integer, so by the time `str_pad(pin_14, width=14, pad="0", side="left")`
ran, R had already turned it into a numeric. `format()`'s default uses
scientific notation for large numbers (`3.043071e+13`), and `str_pad` on
that produced the wrong string — silently, until `check_pin_dt_str` caught
it.

**Fix.** In both `ptaxsim_explainer.qmd` and `ptaxsim_explainer_tif.qmd`,
coerce the parameter to a non-scientific string *before* padding:

```r
pin_14 <- format(params$pin_14, scientific = FALSE, trim = TRUE)
pin_14 <- str_pad(pin_14, width = 14, pad = "0", side = "left")
```

`scientific=FALSE` forces decimal form; `trim=TRUE` drops the leading space
that `format()` otherwise reserves for the sign.

---

## 3. NAS sync doubled disk usage

**Symptom.** `_copy_new_to_nas` left the local copy in place after copying
to the NAS, so every rendered HTML occupied space on both the local SSD and
the NAS. With 3.2M outputs, the local disk filled up.

**Fix.** Replaced with `_move_local_to_nas` in `batch_generate.py`:

- For each local HTML file: copy to NAS, then verify destination size
  matches source size, then `os.remove()` the local file.
- If destination already exists and sizes match, skip the copy but still
  remove the local.
- If sizes mismatch after copy, keep the local file and log a warning —
  retry on a later sync.
- Prune empty directories bottom-up after the walk so `_jobs`-style stubs
  do not accumulate.
- Returns a `set[(pin, mode)]` of completions so `cmd_sync` can mark rows
  done directly from the moved files (instead of a second walk).

---

## Summary of files touched

- `app/main.py` — `run_quarto` rewritten for per-job isolation.
- `ptaxsim_explainer.qmd` — pin coercion + `PTAX_PROJECT_ROOT` setup chunk.
- `ptaxsim_explainer_tif.qmd` — same as above.
- `batch_generate.py` — `_move_local_to_nas` replacing `_copy_new_to_nas`;
  `cmd_sync` uses the returned completion set.
