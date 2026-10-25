#!/usr/bin/env python3
"""Scaffold a blog post from templates/post.md.

usage: python3 scripts/new_post.py <slug> "<title>" <topic> <id>
"""
import datetime
import os
import sys

if len(sys.argv) != 5:
    sys.exit(__doc__)
slug, title, topic, pid = sys.argv[1:]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
dest = os.path.join(root, 'docs-src', 'blog', 'posts', f'{slug}.md')
if os.path.exists(dest):
    sys.exit(f'{dest} already exists')
text = open(os.path.join(root, 'templates', 'post.md')).read()
for key, val in {'__DATE__': datetime.date.today().isoformat(), '__SLUG__': slug,
                 '__TITLE__': title, '__TOPIC__': topic, '__ID__': pid}.items():
    text = text.replace(key, val)
open(dest, 'w').write(text)
print(f'created {dest}\n(draft: true — it is excluded from `make build` until you remove that line)')
