# Documentation and GitHub Pages

<link-summary>Writerside, API docs and the one GitHub Pages site assembled from every part.</link-summary>

## Writerside

`writerside.yml` builds every instance of every `writerside.cfg` (or `writerside.instances`, such
as `[docs/d]`) in a job of its own:

1. JetBrains' builder image `jetbrains/writerside-builder` runs `helpbuilderinspect`, the build
   the official action runs, without that action's JavaScript runtime. `writerside.builder:
   action` uses JetBrains/writerside-github-action instead.
2. JetBrains/writerside-checker-action fails on broken links, unknown topics and the other errors
   of the build report.
3. The web help becomes the part `docs` of the Pages site; the archive, `report.json` and an
   optional PDF stay as the artifact `writerside-<id>`.

`writerside.builder-version` pins the image; `self-update-pins.yml` of this repository moves it to
each new release. `writerside.algolia` publishes the search index with the secret `ALGOLIA_KEY`.

## API documentation

`dartdoc.yml` runs `dart doc` for every published package (`dartdoc.publishable-only`). On pull
requests it only checks that the documentation builds. One package is the part `api`; several are
subdirectories with an index page. `dartdoc.validate-links` reports broken links and
`dartdoc.fail-on-warnings` fails on them.

## The Pages site

A repository has one Pages site, so only `pages.yml` deploys. Every other workflow uploads its
part as an artifact `davils-pages-<part>-<id>`, and `pages.yml` places each at its path:

```yaml
pages:
  layout:
    docs: /
    api: /api
    web: /app/{id}
    coverage: /coverage/{id}
    inspectra: /quality
```

| Part | From | `{id}` |
|---|---|---|
| `docs` | writerside.yml | the instance id |
| `api` | dartdoc.yml | `api` |
| `web` | flutter-build.yml | the app's package name |
| `coverage` | dart-ci.yml, flutter-ci.yml (`pages.parts.coverage`) | `dart`, `flutter` |
| `inspectra` | inspectra.yml (`pages.parts.inspectra`) | `report` |

- Two parts writing the same file fail the run; a part may sit inside another (`docs` at `/` and
  `api` at `/api`).
- A Flutter web build gets the `<base href>` of its final path, with the base path of the site
  (`/<repository>` for a project site).
- Without a part at `/`, a landing page links every part.
- `pages.cname` writes `CNAME`, `pages.spa-fallback: <app>` copies that app's `index.html` to
  `404.html` for client side routing, `pages.extra-path` copies a directory of the repository
  into the root.

The deployment runs on pushes to `main` and manual runs (`pages.when`), in the environment
`github-pages`, one at a time per repository. Every deployment replaces the whole site, so the run
rebuilds every active part.
