# jbagnoli_DM

Static pages for table projects. The site is plain HTML and CSS: no build step, no server, and no analytics.

Links are relative, so the files work locally and under the GitHub Pages project base `/jbagnoli_DM/`. The shelf is the root `index.html`. The Eternal Concord chronicle is `eternal-concord/index.html`, with its printable PDF beside it.

These files do not turn Pages on, and they do not change who can see the repository.

## Publish with GitHub Pages

After this change is on `main`:

1. Open **Settings → Pages**.
2. Under **Build and deployment**, set **Source** to **GitHub Actions**.
3. The workflow **Deploy GitHub Pages** runs on every push to `main`. If it does not start, open **Actions → Deploy GitHub Pages → Run workflow**.
4. A successful run prints the deployed URL in the log. The shelf should be `https://jbagnoli.github.io/jbagnoli_DM/` and the chronicle `https://jbagnoli.github.io/jbagnoli_DM/eternal-concord/`.

Until step 2 is done, the workflow cannot publish. Do not treat those addresses as live until a deploy log shows them.

To publish from the branch instead of Actions, set **Source** to **Deploy from a branch**, branch **main**, folder **/ (root)**. `.nojekyll` is included so GitHub serves the HTML as written.

## Preview locally

From the repository root:

```bash
python3 -m http.server 8000
```

Open `http://127.0.0.1:8000/`. To mimic the project base, serve a parent folder that contains this repository as `jbagnoli_DM` and open `/jbagnoli_DM/`.

## Update the chronicle

Edit `eternal-concord/index.html`. The session prose, 24 quotes, and 13 achievement descriptions are the player recap. The eight SessionKeeper links stay as they are.

Replace `eternal-concord/eternal-concord-session-chronicle.pdf` when you have a new printable file, and keep the download link on that filename.

Push to `main`. Pages publishes those files directly.

Before pushing, confirm the recap is intact:

```bash
python3 scripts/verify_site.py
```

An intentional recap edit has to be recorded in `scripts/chronicle_lock.json` as well, or that check fails.

## Add a project later

Put it in its own folder next to `eternal-concord/` and add one link on the root `index.html`. Add the link only after the project is there.
