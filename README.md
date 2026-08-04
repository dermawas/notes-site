# flowformlab-com-site

Source for **flowformlab.com** (GitHub Pages, custom domain via `CNAME`, Decap CMS admin at `/admin`).

> Renamed from `notes-site` on 2026-08-04 for naming clarity — the old name gave no indication this hosts flowformlab.com. GitHub redirects the old URL; `admin/config.yml`'s CMS backend `repo:` field was updated to match.

## Publishing Guide

### Quick Start
1. Create a **new public repository** (name it anything you like, e.g., `notes-site`).
2. Add these files to it.
3. Go to **Settings → Pages**.
- **Build and deployment**: Deploy from a branch.
- **Branch**: `main` (folder `/root`).
4. Wait for GitHub Pages to deploy — your site will be live at `https://your-username.github.io/notes-site`.
5. (Optional) Add a custom domain later if you want.


## Writing Notes
- Add new files under `_posts` in the format `YYYY-MM-DD-title.md`.
- Push your changes — GitHub Pages will auto-deploy.


## Local Preview
