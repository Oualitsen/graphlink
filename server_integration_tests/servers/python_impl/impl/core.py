from typing import AsyncIterator, Dict, List, Optional

from generated.context import GraphLinkContext
from generated.enums.article_type import ArticleType
from generated.enums.color import Color
from generated.enums.keyword import Keyword
from generated.enums.priority import Priority
from generated.inputs.config_input import ConfigInput
from generated.inputs.create_article_input import CreateArticleInput
from generated.inputs.range_input import RangeInput
from generated.inputs.reserved_input import ReservedInput
from generated.inputs.update_article_input import UpdateArticleInput
from generated.interfaces.media import Media
from generated.interfaces.shape import Shape
from generated.types.article import Article
from generated.types.author import Author
from generated.types.box import Box
from generated.types.class_ import Class
from generated.types.circle import Circle
from generated.types.collide import Collide
from generated.types.config import Config
from generated.types.greeting import Greeting
from generated.types.member import Member
from generated.types.message import Message
from generated.types.photo import Photo
from generated.types.range import Range
from generated.types.reserved_fields import ReservedFields
from generated.types.secret import Secret_
from generated.types.square import Square
from generated.types.team import Team
from generated.types.video import Video

from .data import articles, authors, next_id
from .pubsub import SimplePubSub

article_created_pubsub: "SimplePubSub[Article]" = SimplePubSub()
article_updated_pubsub: "SimplePubSub[Article]" = SimplePubSub()
greeting_received_pubsub: "SimplePubSub[Greeting]" = SimplePubSub()


class ArticleServiceImpl:
    async def get_article(self, id: str, context: GraphLinkContext) -> Article:
        for article in articles:
            if article.id == id:
                return article
        raise Exception(f"Article not found: {id}")

    async def list_articles(self, context: GraphLinkContext) -> List[Article]:
        return articles

    async def create_article(self, input: CreateArticleInput, context: GraphLinkContext) -> Article:
        article = Article(
            id=next_id(),
            title=input.title,
            type=None,
            author_id=input.author_id,
            web_site=None,
            published=False,
        )
        articles.append(article)
        article_created_pubsub.publish(article)
        return article

    async def update_article(self, input: UpdateArticleInput, context: GraphLinkContext) -> Article:
        for index, article in enumerate(articles):
            if article.id == input.id:
                updated = article.model_copy(update={"title": input.title}) if input.title is not None else article
                articles[index] = updated
                article_updated_pubsub.publish(updated)
                return updated
        raise Exception(f"Article not found: {input.id}")

    def article_created(self, context: GraphLinkContext) -> AsyncIterator[Article]:
        return article_created_pubsub.iterate()

    def article_updated(self, id: str, context: GraphLinkContext) -> AsyncIterator[Article]:
        return article_updated_pubsub.iterate(lambda article: article.id == id)

    async def article_deleted(self, context: GraphLinkContext) -> AsyncIterator[str]:
        yield "deleted-1"
        yield "deleted-2"

    async def get_projected_article(self, context: GraphLinkContext) -> Article:
        return articles[0]

    async def get_article_info(self, context: GraphLinkContext) -> Optional[Article]:
        return articles[0] if articles else None

    async def get_article_with_count(self, context: GraphLinkContext) -> Optional[Article]:
        return articles[0] if articles else None

    async def get_article_types(self, context: GraphLinkContext) -> List[ArticleType]:
        return [ArticleType.NEWS, ArticleType.BLOG, ArticleType.REVIEW]


class ArticleSchemaMappingsServiceImpl:
    async def article_author(self, value: Article, context: GraphLinkContext) -> Author:
        for author in authors:
            if author.id == value.author_id:
                return author
        raise Exception(f"Author not found: {value.author_id}")

    async def article_author_list(self, value: Article, context: GraphLinkContext) -> Optional[List[Author]]:
        return [a for a in authors if a.id == value.author_id]

    async def article_with_count_count(self, value: Article, context: GraphLinkContext) -> int:
        for index, article in enumerate(articles):
            if article is value or article == value:
                return index + 1
        return 0


class AuthorServiceImpl:
    async def get_author(self, id: str, context: GraphLinkContext) -> Optional[Author]:
        return next((a for a in authors if a.id == id), None)

    async def list_authors(self, context: GraphLinkContext) -> List[Author]:
        return authors


class AuthorSchemaMappingsServiceImpl:
    async def author_articles(self, value: List[Author], context: GraphLinkContext) -> Dict[Author, Optional[List[Article]]]:
        return {author: [a for a in articles if a.author_id == author.id] for author in value}

    async def author_latest_articles(self, limit: int, value: Author, context: GraphLinkContext) -> List[Article]:
        return [a for a in articles if a.author_id == value.id][:limit]


class BulkCreateServiceImpl:
    async def bulk_create(self, matrix, context: GraphLinkContext) -> int:
        return len(_inputs(matrix))


class BulkCreateGuardImpl:
    async def validate_bulk_create(self, matrix, context: GraphLinkContext) -> None:
        if any(item.title == "invalid" for item in _inputs(matrix)):
            raise Exception("invalid title")


def _inputs(matrix) -> List[CreateArticleInput]:
    return [item for row in (matrix or []) for item in (row or [])]


class CollideServiceImpl:
    async def collide(self, context: GraphLinkContext) -> Collide:
        return Collide(id="1", class_2="A", class2="B")


class DefaultsServiceImpl:
    async def resolve_config(self, input: ConfigInput, context: GraphLinkContext) -> Config:
        return Config(
            page_size=input.page_size,
            ratio=input.ratio,
            sort=input.sort,
            verbose=input.verbose,
            priority=input.priority,
            tags=input.tags,
            empties=input.empties,
            note=input.note,
        )

    async def resolve_range(self, input: Optional[RangeInput], context: GraphLinkContext) -> Range:
        return Range(
            min=input.min if input is not None and input.min is not None else 0,
            max=input.max if input is not None and input.max is not None else 100,
        )

    async def greet(self, name: Optional[str], times: Optional[int], context: GraphLinkContext) -> str:
        return f"Hi {'null' if name is None else name}!" * (times if times is not None else 1)

    async def echo_priority(self, level: Optional[Priority], context: GraphLinkContext) -> Priority:
        return level if level is not None else Priority.HIGH

    async def ack_priority(self, level: Priority, context: GraphLinkContext) -> str:
        return "OK"


class DeleteArticleServiceImpl:
    async def delete_article(self, id: str, context: GraphLinkContext) -> bool:
        before = len(articles)
        articles[:] = [a for a in articles if a.id != id]
        return len(articles) < before


class GreetingServiceImpl:
    def _build(self, name: str, marker: Optional[str] = None) -> Greeting:
        return Greeting(id="1", message=f"Hello, {name}{marker or ''}")

    async def greet_intercepted(self, name: str, context: GraphLinkContext) -> Greeting:
        return self._build(name, getattr(context, "marker", None))

    async def greet_plain(self, name: str, context: GraphLinkContext) -> Greeting:
        return self._build(name)

    async def send_greeting(self, name: str, context: GraphLinkContext) -> Greeting:
        greeting = self._build(name)
        greeting_received_pubsub.publish(greeting)
        return greeting

    async def greeting_received(self, context: GraphLinkContext) -> AsyncIterator[Greeting]:
        marker = getattr(context, "marker", None)
        async for greeting in greeting_received_pubsub.iterate():
            yield greeting.model_copy(update={"message": f"{greeting.message}{marker}"}) if marker else greeting


class MessageServiceImpl:
    async def get_message_read_list(self, context: GraphLinkContext) -> Optional[List[Optional[Message]]]:
        return [Message(id="m1", content="hello"), Message(id="m2", content="world")]

    async def message_read_read(self, value: List[Message], context: GraphLinkContext) -> Dict[Message, bool]:
        return {m: m.id.endswith("1") for m in value}


class NestingServiceImpl:
    def _box(self, id: str) -> Box:
        return Box(id=id, label=f"label-{id}")

    def _circle(self, id: str) -> Circle:
        return Circle(id=id, kind="circle", radius=1)

    def _square(self, id: str) -> Square:
        return Square(id=id, kind="square", side=2)

    def _photo(self, id: str) -> Photo:
        return Photo(id=id, url=f"https://x/{id}.jpg", width=640)

    def _video(self, id: str) -> Video:
        return Video(id=id, url=f"https://x/{id}.mp4", duration_sec=30)

    async def colors1(self, context):
        return [Color.RED, Color.GREEN, Color.BLUE]

    async def colors2(self, context):
        return [[Color.RED], [Color.GREEN, Color.BLUE]]

    async def colors3(self, context):
        return [[[Color.RED]]]

    async def boxes1(self, context):
        return [self._box("b1"), self._box("b2")]

    async def boxes2(self, context):
        return [[self._box("b1")], [self._box("b2")]]

    async def boxes3(self, context):
        return [[[self._box("b1")]]]

    async def shapes1(self, context):
        return [self._circle("c1"), self._square("s1")]

    async def shapes2(self, context):
        return [[self._circle("c1")], [self._square("s1")]]

    async def shapes3(self, context):
        return [[[self._circle("c1"), self._square("s1")]]]

    async def media1(self, context):
        return [self._photo("p1"), self._video("v1")]

    async def media2(self, context):
        return [[self._photo("p1")], [self._video("v1")]]

    async def media3(self, context):
        return [[[self._photo("p1"), self._video("v1")]]]


class ReservedFieldsServiceImpl:
    def _base(self) -> ReservedFields:
        return ReservedFields(
            id="r1",
            class_="cls",
            return_=42,
            new=True,
            default="def",
            is_="yes",
            in_="inside",
            with_="w",
            int=7,
            synchronized=False,
            native="n",
            kind=Keyword.CLASS,
            nested=Class(id="c1", value="v"),
            secret=Secret_(id="s1", token="tok"),
        )

    async def reserved(self, context: GraphLinkContext) -> ReservedFields:
        return self._base()

    async def switch(self, class_: str, return_: Optional[int], context: GraphLinkContext) -> ReservedFields:
        return self._base().model_copy(update={"class_": class_, "return_": return_ if return_ is not None else 0})

    async def echo_reserved(self, input: ReservedInput, context: GraphLinkContext) -> ReservedFields:
        return self._base().model_copy(
            update={
                "class_": input.class_,
                "return_": input.return_ if input.return_ is not None else -1,
                "default": input.default if input.default is not None else "none",
            }
        )


class StatusServiceImpl:
    async def status(self, context: GraphLinkContext) -> str:
        return "ok"


_teams = [Team(id="1", name="Core")]
_members_by_team = {"1": [Member(id="1", name="Ada"), Member(id="2", name="Grace")]}


class TeamServiceImpl:
    async def list_teams(self, context: GraphLinkContext) -> List[Team]:
        return _teams


class TeamSchemaMappingsServiceImpl:
    async def team_members(self, role: str, value: Team, context: GraphLinkContext) -> List[Member]:
        return _members_by_team.get(value.id, [])
