import json
import os
from typing import List

from generated.types.article import Article
from generated.types.author import Author

_fixtures_path = os.environ.get("FIXTURES_PATH", "../../fixtures.json")
with open(_fixtures_path, encoding="utf-8") as _file:
    _fixtures = json.load(_file)

authors: List[Author] = [Author.from_json(a) for a in _fixtures["authors"]]
articles: List[Article] = [Article.from_json(a) for a in _fixtures["articles"]]
_next_article_id = _fixtures["nextId"]


def next_id() -> str:
    global _next_article_id
    value = str(_next_article_id)
    _next_article_id += 1
    return value
