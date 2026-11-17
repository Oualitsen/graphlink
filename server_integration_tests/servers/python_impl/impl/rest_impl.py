import hashlib
from typing import AsyncIterator, List, Optional

from generated.context import GraphLinkContext
from generated.enums.rest_color import RestColor
from generated.file_upload import FileUpload
from generated.inputs.rest_filter import RestFilter
from generated.inputs.rest_item_input import RestItemInput
from generated.inputs.rest_line import RestLine
from generated.inputs.rest_meta import RestMeta
from generated.inputs.rest_person import RestPerson
from generated.rest.download import GraphLinkDownload
from generated.types.rest_form_echo import RestFormEcho
from generated.types.rest_headers import RestHeaders
from generated.types.rest_item import RestItem
from generated.types.rest_keywords import RestKeywords
from generated.types.rest_marked import RestMarked
from generated.types.rest_nested import RestNested
from generated.types.rest_scalars import RestScalars
from generated.types.rest_search import RestSearch
from generated.types.rest_upload_info import RestUploadInfo
from generated.types.rest_wrap import RestWrap


def _item(id: str, name: str, qty: int, color: Optional[RestColor], tags: Optional[List[str]]) -> RestItem:
    return RestItem(id=id, name=name, qty=qty, color=color, tags=tags or [])


def _from_input(id: str, input: RestItemInput) -> RestItem:
    return _item(id, input.name, input.qty, input.color, input.tags)


class RestItemServiceImpl:
    async def rest_item(self, id: str, context) -> Optional[RestItem]:
        return None if id == "missing" else _item(id, f"item-{id}", 1, None, None)

    async def rest_item_by_color(self, color: RestColor, context) -> RestItem:
        lower = color.to_json().lower()
        return _item(lower, f"color-{color.to_json()}", 1, color, [lower])

    async def rest_item_graphql(self, id: str, context) -> Optional[RestItem]:
        return await self.rest_item(id, context)

    async def rest_create(self, input: RestItemInput, context) -> RestItem:
        return _from_input(f"new-{input.name}", input)

    async def rest_replace(self, id: str, input: RestItemInput, context) -> RestItem:
        return _from_input(id, input)

    async def rest_patch(self, id: str, name: Optional[str], context) -> RestItem:
        return _item(id, name if name is not None else f"item-{id}", 1, None, None)

    async def rest_bulk(self, items: List[RestItemInput], context) -> List[RestItem]:
        return [_from_input(f"bulk-{i}", item) for i, item in enumerate(items)]


class RestScalarsServiceImpl:
    async def rest_scalars(self, n: int, ratio: float, flag: bool, text: str, context) -> RestScalars:
        return RestScalars(n=n, ratio=ratio, flag=flag, text=text)

    async def rest_fail(self, code: int, context) -> RestScalars:
        raise Exception(f"boom {code}")


class RestSearchServiceImpl:
    async def rest_search(self, filter: Optional[RestFilter], limit: Optional[int], offset: Optional[int], order: Optional[RestColor], context) -> RestSearch:
        return RestSearch(
            tag=filter.tag if filter else None,
            min_qty=filter.min_qty if filter else None,
            max_price=filter.max_price if filter else None,
            colors=filter.colors if filter else None,
            in_stock=filter.in_stock if filter else None,
            limit=limit if limit is not None else 10,
            offset=offset,
            order=order,
        )


class RestTagsServiceImpl:
    async def rest_tags(self, tags: List[str], ids: Optional[List[int]], context) -> List[str]:
        return [*tags, *[f"#{i}" for i in (ids or [])]]


class RestGreetingServiceImpl:
    async def rest_greeting(self, name: str, context) -> str:
        return f"hello {name}"


class RestPlainServiceImpl:
    async def rest_plain(self, name: str, context) -> str:
        return f"plain {name}"


class RestCountServiceImpl:
    async def rest_count(self, context) -> int:
        return 42


class RestFlagServiceImpl:
    async def rest_flag(self, on: bool, context) -> bool:
        return not on


class RestColorsServiceImpl:
    async def rest_colors(self, context) -> List[RestColor]:
        return [RestColor.RED, RestColor.GREEN, RestColor.BLUE]


class RestHeadersServiceImpl:
    async def rest_headers(self, token: str, trace: Optional[str], meta: Optional[RestMeta], context) -> RestHeaders:
        return RestHeaders(
            token=token,
            trace=trace,
            trace_id=meta.trace_id if meta else None,
            version=meta.version if meta else None,
        )


class RestDeleteServiceImpl:
    async def rest_delete(self, id: str, context) -> None:
        return None


class RestOptionalBodyServiceImpl:
    async def rest_optional_body(self, input: Optional[RestItemInput], context) -> int:
        return input.qty if input is not None else -1


class RestValidatedServiceImpl:
    async def rest_validated(self, name: str, context) -> bool:
        return True


class RestValidatedGuardImpl:
    async def validate_rest_validated(self, name: str, context: GraphLinkContext) -> None:
        if name == "invalid":
            raise Exception("invalid name")


class RestKeywordsServiceImpl:
    async def rest_keywords(self, switch: str, class_: str, return_: Optional[str], if_: int, context) -> RestKeywords:
        return RestKeywords(class_=class_, return_=return_, if_=if_, switch=switch)


async def _upload_info(file: FileUpload, label: Optional[str], kind: Optional[RestColor], times: Optional[int]) -> RestUploadInfo:
    digest = hashlib.sha256()
    size = 0
    async for chunk in file.create_read_stream():
        digest.update(chunk)
        size += len(chunk)
    return RestUploadInfo(
        filename=file.filename or None,
        content_type=file.mimetype,
        size=size,
        sha256=digest.hexdigest(),
        label=label,
        kind=kind,
        times=times,
    )


class RestUploadInfoServiceImpl:
    async def rest_upload(self, file: FileUpload, label: Optional[str], kind: Optional[RestColor], times: Optional[int], context) -> RestUploadInfo:
        return await _upload_info(file, label, kind, times)

    async def rest_upload_many(self, files: List[FileUpload], label: Optional[str], context) -> List[RestUploadInfo]:
        return [await _upload_info(f, label, None, None) for f in files]

    async def rest_upload_raw(self, id: str, file: FileUpload, name: Optional[str], context) -> RestUploadInfo:
        return await _upload_info(file, name, None, None)


class RestUploadOptionalServiceImpl:
    async def rest_upload_optional(self, file: Optional[FileUpload], context) -> int:
        if file is None:
            return -1
        return (await _upload_info(file, None, None, None)).size


class RestFormEchoServiceImpl:
    async def rest_form(self, name: str, qty: int, color: Optional[RestColor], flag: Optional[bool], tags: Optional[List[str]], note: Optional[str], context) -> RestFormEcho:
        return RestFormEcho(id=None, name=name, qty=qty, color=color, flag=flag if flag is not None else False, tags=tags or [], note=note)

    async def rest_form_update(self, id: str, name: str, qty: Optional[int], context) -> RestFormEcho:
        return RestFormEcho(id=id, name=name, qty=qty if qty is not None else 1, color=None, flag=False, tags=[], note=None)


class RestFormOptionalServiceImpl:
    async def rest_form_optional(self, note: Optional[str], context) -> int:
        return -1 if note is None else len(note)


def _marked(name: str, context: Optional[GraphLinkContext]) -> RestMarked:
    return RestMarked(
        name=name,
        marker=getattr(context, "marker", None) if context is not None else None,
        has_context=context is not None,
    )


class RestMarkedServiceImpl:
    async def rest_intercepted(self, name: str, context: GraphLinkContext) -> RestMarked:
        return _marked(name, context)

    async def rest_injected(self, name: str, context: GraphLinkContext) -> RestMarked:
        return _marked(name, context)

    async def rest_unguarded(self, name: str, context: GraphLinkContext) -> RestMarked:
        return _marked(name, None)

    async def rest_block_guarded(self, name: str, context: GraphLinkContext) -> RestMarked:
        return _marked(name, context)

    async def rest_intercepted_body(self, input: RestItemInput, context: GraphLinkContext) -> RestMarked:
        return _marked(input.name, context)


class RestInterceptedVoidServiceImpl:
    async def rest_intercepted_void(self, name: str, context) -> None:
        return None


def _pattern(size: int) -> bytes:
    return bytes(i % 251 for i in range(size))


def _download(name: str, kind: Optional[str]) -> GraphLinkDownload:
    if kind == "bin":
        return GraphLinkDownload(data=_pattern(1000), filename="data.bin")
    if kind == "nofile":
        return GraphLinkDownload(data="x")
    if kind == "type":
        return GraphLinkDownload(data='{"a":1}', content_type="application/json")
    return GraphLinkDownload(data=f"hello {name}", filename=f"{name}.txt", content_type="text/plain")


class RestDownloadServiceImpl:
    async def rest_download(self, name: str, kind: Optional[str], context) -> GraphLinkDownload:
        return _download(name, kind)


class RestDownloadOptionalServiceImpl:
    async def rest_download_optional(self, name: Optional[str], context) -> Optional[GraphLinkDownload]:
        return None if name is None else _download(name, None)


class RestDownloadLargeServiceImpl:
    async def rest_download_large(self, size: int, context) -> GraphLinkDownload:
        async def chunks() -> AsyncIterator[bytes]:
            position = 0
            while position < size:
                count = min(64 * 1024, size - position)
                yield bytes((position + i) % 251 for i in range(count))
                position += count

        return GraphLinkDownload(data=chunks(), filename="large.bin")


class RestWrapServiceImpl:
    async def rest_wrap_deep(self, v: str, context) -> RestWrap:
        return RestWrap(value=v)

    async def rest_wrap_list(self, n: int, context) -> List[RestWrap]:
        return [RestWrap(value=f"item-{i}") for i in range(n)]

    async def rest_wrap_nullable(self, on: bool, context) -> Optional[RestWrap]:
        return RestWrap(value="on") if on else None


class RestWrapColorServiceImpl:
    async def rest_wrap_color(self, context) -> RestColor:
        return RestColor.BLUE


class RestWrapTextServiceImpl:
    async def rest_wrap_text(self, v: str, context) -> str:
        return f"text:{v}"


def _person_summary(person: Optional[RestPerson]) -> str:
    if person is None:
        return "none"
    return "|".join(
        [
            person.name,
            str(person.age) if person.age is not None else "-",
            person.address.city if person.address is not None else "-",
            str(person.address.zip) if person.address is not None and person.address.zip is not None else "-",
            ",".join(person.tags) if person.tags is not None else "-",
            person.kind.to_json() if person.kind is not None else "-",
        ]
    )


def _lines_summary(lines: Optional[List[RestLine]]) -> str:
    return "-" if lines is None else ";".join(f"{line.sku}:{line.qty}" for line in lines)


class RestNestedServiceImpl:
    async def rest_nested_spread(self, person: RestPerson, context) -> RestNested:
        return RestNested(summary=_person_summary(person))

    async def rest_nested_spread_optional(self, person: Optional[RestPerson], context) -> RestNested:
        return RestNested(summary=_person_summary(person))

    async def rest_nested_flat(self, person: RestPerson, context) -> RestNested:
        return RestNested(summary=_person_summary(person))

    async def rest_nested_lines(self, lines: List[RestLine], context) -> RestNested:
        return RestNested(summary=_lines_summary(lines))

    async def rest_nested_json(self, person: Optional[RestPerson], context) -> RestNested:
        return RestNested(summary=_person_summary(person))

    async def rest_nested_form(self, person: RestPerson, lines: Optional[List[RestLine]], note: Optional[str], context) -> RestNested:
        return RestNested(summary=f"{_person_summary(person)}/{_lines_summary(lines)}/{note if note is not None else '-'}")

    async def rest_nested_form_json(self, person: RestPerson, context) -> RestNested:
        return RestNested(summary=_person_summary(person))
