import asyncio
from typing import AsyncIterator, Callable, Generic, List, Optional, TypeVar

T = TypeVar("T")


class SimplePubSub(Generic[T]):
    def __init__(self) -> None:
        self._queues: List["asyncio.Queue[T]"] = []

    def publish(self, payload: T) -> None:
        for queue in list(self._queues):
            queue.put_nowait(payload)

    async def iterate(self, accept: Optional[Callable[[T], bool]] = None) -> AsyncIterator[T]:
        queue: "asyncio.Queue[T]" = asyncio.Queue()
        self._queues.append(queue)
        try:
            while True:
                payload = await queue.get()
                if accept is None or accept(payload):
                    yield payload
        finally:
            self._queues.remove(queue)
