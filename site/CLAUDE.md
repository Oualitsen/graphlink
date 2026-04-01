# GraphLink Site

## What this is

This is the documentation and marketing website for **GraphLink** (`graphlink.dev`). It is a static site — no build step, no framework. All files are plain HTML, CSS, and JS served directly via nginx (see `nginx.conf` and `Dockerfile`).

## Structure

```
site/
  index.html              # Landing page (hero, features, quick-start, roadmap)
  docs/
    index.html            # Docs overview / navigation hub
    philosophy.html       # Design philosophy
    getting-started.html  # Installation and first schema
    dart-client.html      # Dart / Flutter client docs
    java-client.html      # Java client docs
    spring-server.html    # Spring Boot server docs
    caching.html          # @glCache / @glCacheInvalidate docs
    directives.html       # All directives reference
    configuration.html    # config.json reference (all options)
  css/
    styles.css            # Global styles (landing + docs shared)
    docs.css              # Docs-specific layout and components
  js/
    main.js               # Landing page JS (tabs, copy buttons, nav scroll)
    docs.js               # Docs page JS (sidebar, tab groups)
  llms.txt                # Machine-readable summary for LLMs (concise)
  llms-full.txt           # Machine-readable full docs for LLMs (complete)
  robots.txt
  sitemap.xml
```

## IMPORTANT — Keep these files in sync

**Every time any doc page is updated, you MUST also update:**

### 1. `llms.txt`
Concise machine-readable overview for LLMs and AI tools. Contains:
- What GraphLink generates (brief bullets per target)
- Key differentiators
- Supported targets with version
- Config example
- Doc page links with accurate descriptions

### 2. `llms-full.txt`
Full machine-readable docs for LLMs. Contains one section per doc page with code examples. Mirrors the actual content of the HTML pages. When you update a doc page, find its corresponding section in this file (e.g. `# Dart / Flutter Client`, `# Java Client`) and update it to match.

### 3. SEO meta tags in the updated HTML file(s)
Every doc page has three meta tags that must reflect its actual content:
```html
<meta name="description" content="...">
<meta property="og:description" content="...">
<meta name="twitter:description" content="...">
```

Update these whenever the page content changes significantly (new features, removed sections, changed API).

### 4. `sitemap.xml`
If a new page is added, add it to `sitemap.xml` with the current date as `<lastmod>`.

---

## Versioning

The current released version is referenced in:
- `llms.txt` — `## Supported targets (as of vX.Y.Z)`
- `llms-full.txt` — same line
- CSS/JS query strings — `styles.css?v=X.Y.Z`, `main.js?v=X.Y.Z`, `docs.js?v=X.Y.Z`

Update all of these when cutting a new release.

## JS tab systems

There are three tab systems in the site JS:
- `.hero-lang-tab` / `.lang-pane` — hero code panel on index.html (Dart / Java toggle)
- `.doc-tab` / `.doc-tab-content` inside `.doc-tabgroup` — inline tab groups in doc pages
- `.qs-tab` / `.qs-content` — Quick Start tabs on index.html
- `.compare-tab` / `.compare-group` — Before/After comparison on index.html

When adding tabs in a doc page, always wrap them in a `.doc-tabgroup` div — the JS scopes tab switching per group.
