from typing import Any, List, Optional

from generated.context import GraphLinkContext
from generated.enums.gl_interceptor_tag import GlInterceptorTag


class InterceptorImpl:
    async def run_before(
        self, tag: Optional[GlInterceptorTag], operation: str, args: List[Any], context: GraphLinkContext
    ) -> None:
        if operation.startswith("rest") and args and args[0] == "deny":
            from generated.rest.core import RestError

            raise RestError(403, "Forbidden")

        if operation == "Team.members":
            role = args[0]
            if role != "auth":
                raise Exception(f'Access denied: role "{role}" is not permitted')
            return

        if (len(args) == 0 or isinstance(args[0], str)) and context is not None:
            context.marker = "(runBefore)"
