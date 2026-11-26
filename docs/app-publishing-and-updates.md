# App publishing and update behaviour

## Publishing

The live app is hosted on GitHub Pages at https://coeeeuer.github.io/equipment-tracker/.

For branch-based GitHub Pages publishing, the repository's Pages setting must point to:
- Branch: `main`
- Folder: `/(root)`

With that source configured, every commit merged into `main` is published automatically by GitHub Pages. The app's GitHub Actions validation workflow checks application JavaScript and the service worker; it is not itself the Pages publisher.

Verify the source under **Repository → Settings → Pages → Build and deployment**. Do not change the Pages source to GitHub Actions unless a separate Pages deployment workflow is added and tested.

## Staff app update experience

- The service worker caches the app shell for offline use and checks the network for the latest page.
- A new service worker waits while the current app is open.
- When an update is ready, the app shows **A new version is ready** and an **Update now** button.
- Selecting the button activates the waiting worker and reloads the app once it takes control.
- The app checks for updates on startup, when it returns to the foreground, and hourly while open.
- Existing legacy QR routes remain unchanged. No Supabase schema, records, or database migrations are modified by this update feature.

If a staff member does not see an update immediately, they can close and reopen the app while connected to the internet.
