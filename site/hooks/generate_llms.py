"""
MkDocs build hook — regenerates llms.txt, llms-full.txt, and sitemap.xml from docs-src.

llms.txt      : concise overview + auto-generated page links (from frontmatter description)
llms-full.txt : static header + full markdown content of every page
sitemap.xml   : landing page + all doc pages with today's date as lastmod
"""
import os
import re
from datetime import date


def _parse_frontmatter(text):
    """Return (meta_dict, body) — meta keys are title and description."""
    meta = {}
    if text.startswith('---'):
        end = text.find('\n---', 3)
        if end != -1:
            block = text[4:end]
            for line in block.splitlines():
                m = re.match(r'^(\w+):\s*(.+)', line)
                if m:
                    meta[m.group(1)] = m.group(2).strip()
            body = text[end + 4:].lstrip('\n')
            return meta, body
    return meta, text


def _flatten_nav(nav):
    """Recursively extract md file paths from the nav list."""
    result = []
    if not nav:
        return result
    for item in nav:
        if isinstance(item, str):
            result.append(item)
        elif isinstance(item, dict):
            for val in item.values():
                if isinstance(val, str):
                    result.append(val)
                elif isinstance(val, list):
                    result.extend(_flatten_nav(val))
    return result


def _read(path):
    with open(path, 'r') as f:
        return f.read()


def on_post_build(config):
    docs_dir = config['docs_dir']
    root_dir = os.path.dirname(os.path.abspath(docs_dir))
    site_url = config.get('site_url', 'https://graphlink.dev').rstrip('/')
    pages = [p for p in _flatten_nav(config.get('nav', [])) if p.endswith('.md') and not p.startswith('_')]

    # --- llms-full.txt ---
    header_full = _read(os.path.join(docs_dir, '_llms_header.txt')).rstrip('\n') \
        if os.path.exists(os.path.join(docs_dir, '_llms_header.txt')) else ''

    full_parts = [header_full, '\n\n---\n\n']
    for path in pages:
        filepath = os.path.join(docs_dir, path)
        if not os.path.exists(filepath):
            continue
        _, body = _parse_frontmatter(_read(filepath))
        full_parts.append(body.strip())
        full_parts.append('\n\n---\n\n')

    full_output = ''.join(full_parts)
    with open(os.path.join(root_dir, 'llms-full.txt'), 'w') as f:
        f.write(full_output)

    # --- llms.txt ---
    header_concise = _read(os.path.join(docs_dir, '_llms_concise_header.txt')).rstrip('\n') \
        if os.path.exists(os.path.join(docs_dir, '_llms_concise_header.txt')) else ''

    links = []
    for path in pages:
        filepath = os.path.join(docs_dir, path)
        if not os.path.exists(filepath):
            continue
        meta, _ = _parse_frontmatter(_read(filepath))
        html_path = path.replace('.md', '.html')
        url = f"{site_url}/docs/{html_path}"
        desc = meta.get('description', '')
        title = meta.get('title', html_path)
        # strip site suffix from title for brevity
        title = re.sub(r'\s*—\s*GraphLink\s*(Docs)?', '', title).strip()
        links.append(f"- {title} ({desc}): {url}")

    concise_output = header_concise + '\n\n## Documentation pages\n\n' + '\n'.join(links) + '\n\n## Links\n\n' \
        '- Website: https://graphlink.dev/\n' \
        '- Docs: https://graphlink.dev/docs/index.html\n' \
        '- GitHub: https://github.com/Oualitsen/graphlink\n' \
        '- pub.dev: https://pub.dev/packages/retrofit_graphql\n' \
        '- Issues: https://github.com/Oualitsen/graphlink/issues\n' \
        '- Releases: https://github.com/Oualitsen/graphlink/releases\n'

    with open(os.path.join(root_dir, 'llms.txt'), 'w') as f:
        f.write(concise_output)

    # --- sitemap.xml ---
    today = date.today().isoformat()
    site_url = site_url  # already stripped of trailing slash

    sitemap_entries = [
        f'  <url>\n    <loc>{site_url}/</loc>\n    <lastmod>{today}</lastmod>\n    <changefreq>weekly</changefreq>\n    <priority>1.0</priority>\n  </url>',
        f'  <url>\n    <loc>{site_url}/docs/index.html</loc>\n    <lastmod>{today}</lastmod>\n    <changefreq>weekly</changefreq>\n    <priority>0.9</priority>\n  </url>',
    ]
    for path in pages:
        if path == 'index.md':
            continue  # already added above
        filepath = os.path.join(docs_dir, path)
        if not os.path.exists(filepath):
            continue
        html_path = path.replace('.md', '.html')
        url = f"{site_url}/docs/{html_path}"
        sitemap_entries.append(
            f'  <url>\n    <loc>{url}</loc>\n    <lastmod>{today}</lastmod>\n    <changefreq>weekly</changefreq>\n    <priority>0.8</priority>\n  </url>'
        )

    sitemap = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    sitemap += '\n'.join(sitemap_entries)
    sitemap += '\n</urlset>\n'

    with open(os.path.join(root_dir, 'sitemap.xml'), 'w') as f:
        f.write(sitemap)

    print(f"  [llms hook] llms-full.txt — {len(pages)} pages, {len(full_output):,} chars")
    print(f"  [llms hook] llms.txt      — {len(links)} page links")
    print(f"  [llms hook] sitemap.xml   — {len(sitemap_entries)} URLs, lastmod {today}")
