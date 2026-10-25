"""
MkDocs build hook — regenerates llms.txt, llms-full.txt, and sitemap.xml from docs-src.

llms.txt      : concise overview + auto-generated page links (from frontmatter description)
llms-full.txt : static header + full markdown content of every page
llms/<page>.txt : raw markdown of each page, served at /llms/<page>.txt (blog posts at /llms/blog/<post>.txt)
sitemap.xml   : every doc page (docs are served from the site root) with its last git-commit date as lastmod
"""
import os
import re
import subprocess
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
                    meta[m.group(1)] = m.group(2).strip().strip('"')
            body = text[end + 4:].lstrip('\n')
            return meta, body
    return meta, text


def _clean_for_llm(body):
    """Drop HTML comments and attr_list suffixes (`{: .cls }`) — noise for LLM consumers."""
    body = re.sub(r'<!--.*?-->\n?', '', body, flags=re.S)
    body = re.sub(r'\{:\s*[^}]*\}', '', body)
    body = re.sub(r'<div class="video-embed">.*?</div>\n?', '', body, flags=re.S)
    return body


def _last_modified(path):
    try:
        out = subprocess.run(['git', 'log', '-1', '--format=%cs', '--', path],
                             capture_output=True, text=True, check=True,
                             cwd=os.path.dirname(os.path.abspath(path))).stdout.strip()
        if out:
            return out
    except Exception:
        pass
    return date.today().isoformat()


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


def _slugify(text):
    try:
        from markdown.extensions.toc import slugify
        return slugify(text, '-')
    except Exception:
        return re.sub(r'[-\s]+', '-', re.sub(r'[^\w\s-]', '', text).strip().lower())


def _blog_posts(docs_dir):
    """Published posts under blog/posts: skips drafts and future-dated posts (mirrors the blog plugin)."""
    posts_dir = os.path.join(docs_dir, 'blog', 'posts')
    posts = []
    if not os.path.isdir(posts_dir):
        return posts
    today = date.today().isoformat()
    for fname in sorted(os.listdir(posts_dir)):
        if not fname.endswith('.md'):
            continue
        path = os.path.join(posts_dir, fname)
        meta, body = _parse_frontmatter(_read(path))
        if meta.get('draft', '').lower() == 'true' or str(meta.get('date', ''))[:10] > today:
            continue
        h1 = re.search(r'^#\s+(.+)$', body, re.M)
        title = meta.get('title') or (h1.group(1).strip() if h1 else fname[:-3])
        slug = meta.get('slug') or _slugify(title)
        posts.append(dict(stem=fname[:-3], path=path, meta=meta, body=body, title=title, slug=slug,
                          date=str(meta.get('date', ''))[:10] or _last_modified(path)))
    posts.sort(key=lambda p: p['date'], reverse=True)
    return posts


def _read(path):
    with open(path, 'r') as f:
        return f.read()


def on_post_build(config):
    docs_dir = config['docs_dir']
    out_dir = config['site_dir']   # dist/ — goes into the Docker image
    site_url = config.get('site_url', 'https://graphlink.dev').rstrip('/')
    pages = [p for p in _flatten_nav(config.get('nav', [])) if p.endswith('.md') and not p.startswith(('_', 'blog/'))]

    # --- llms-full.txt ---
    header_full = _read(os.path.join(docs_dir, '_llms_header.txt')).rstrip('\n') \
        if os.path.exists(os.path.join(docs_dir, '_llms_header.txt')) else ''

    full_parts = [header_full, '\n\n---\n\n']
    for path in pages:
        filepath = os.path.join(docs_dir, path)
        if not os.path.exists(filepath):
            continue
        _, body = _parse_frontmatter(_read(filepath))
        full_parts.append(_clean_for_llm(body).strip())
        full_parts.append('\n\n---\n\n')

    posts = _blog_posts(docs_dir)
    for post in posts:
        full_parts.append(_clean_for_llm(post['body']).strip())
        full_parts.append('\n\n---\n\n')

    full_output = ''.join(full_parts)
    with open(os.path.join(out_dir, 'llms-full.txt'), 'w') as f:
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
        slug = path.replace('.md', '')
        llms_url = f"{site_url}/llms/{slug}.txt"
        desc = meta.get('description', '')
        title = meta.get('title', slug)
        # strip site suffix from title for brevity
        title = re.sub(r'\s*—\s*GraphLink\s*(Docs)?', '', title).strip()
        links.append(f"- [{title}]({llms_url}): {desc}")

    blog_section = ''
    if posts:
        blog_links = [f"- [{p['title']}]({site_url}/llms/blog/{p['stem']}.txt): {p['meta'].get('description', '')}" for p in posts]
        blog_section = '\n\n## Blog\n\n' + '\n'.join(blog_links)

    concise_output = header_concise + '\n\n## Documentation pages\n\n' + '\n'.join(links) + blog_section + '\n\n## Links\n\n' \
        '- Website: https://graphlink.dev/\n' \
        '- Docs: https://graphlink.dev/\n' \
        '- GitHub: https://github.com/Oualitsen/graphlink\n' \
        '- pub.dev: https://pub.dev/packages/graphlink\n' \
        '- Issues: https://github.com/Oualitsen/graphlink/issues\n' \
        '- Releases: https://github.com/Oualitsen/graphlink/releases\n'

    with open(os.path.join(out_dir, 'llms.txt'), 'w') as f:
        f.write(concise_output)

    # --- llms/<page>.txt ---
    llms_dir = os.path.join(out_dir, 'llms')
    os.makedirs(llms_dir, exist_ok=True)
    per_page = sorted(f for f in os.listdir(docs_dir) if f.endswith('.md') and not f.startswith('_'))
    for fname in per_page:
        with open(os.path.join(llms_dir, fname[:-3] + '.txt'), 'w') as f:
            f.write(_read(os.path.join(docs_dir, fname)))

    if posts:
        os.makedirs(os.path.join(llms_dir, 'blog'), exist_ok=True)
        for post in posts:
            with open(os.path.join(llms_dir, 'blog', post['stem'] + '.txt'), 'w') as f:
                f.write(_read(post['path']))

    # --- sitemap.xml --- (URLs match each page's <link rel="canonical">)
    sitemap_entries = []
    for path in pages:
        filepath = os.path.join(docs_dir, path)
        if not os.path.exists(filepath):
            continue
        url = f"{site_url}/{path.replace('.md', '.html')}"
        priority = '1.0' if path == 'index.md' else '0.8'
        sitemap_entries.append(
            f'  <url>\n    <loc>{url}</loc>\n    <lastmod>{_last_modified(filepath)}</lastmod>\n    <priority>{priority}</priority>\n  </url>'
        )

    if os.path.exists(os.path.join(docs_dir, 'blog', 'index.md')):
        sitemap_entries.append(
            f'  <url>\n    <loc>{site_url}/blog/index.html</loc>\n    <lastmod>{posts[0]["date"] if posts else _last_modified(os.path.join(docs_dir, "blog", "index.md"))}</lastmod>\n    <priority>0.7</priority>\n  </url>'
        )
    for post in posts:
        sitemap_entries.append(
            f'  <url>\n    <loc>{site_url}/blog/{post["slug"]}.html</loc>\n    <lastmod>{post["date"]}</lastmod>\n    <priority>0.8</priority>\n  </url>'
        )

    sitemap = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    sitemap += '\n'.join(sitemap_entries)
    sitemap += '\n</urlset>\n'

    with open(os.path.join(out_dir, 'sitemap.xml'), 'w') as f:
        f.write(sitemap)

    print(f"  [llms hook] llms-full.txt — {len(pages)} pages, {len(full_output):,} chars")
    print(f"  [llms hook] llms.txt      — {len(links)} page links")
    print(f"  [llms hook] llms/*.txt    — {len(per_page)} per-page files")
    print(f"  [llms hook] blog posts    — {len(posts)} published")
    print(f"  [llms hook] sitemap.xml   — {len(sitemap_entries)} URLs")
