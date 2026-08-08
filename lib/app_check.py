"""Fail-closed Firebase App Check verification boundary."""

from __future__ import annotations

import os
from collections.abc import Callable, Mapping
from threading import Lock
from typing import Any, Protocol

import anyio
from jwt import PyJWKClientConnectionError, PyJWKClientError
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send


FIREBASE_APP_NAME = "kalories-app-check"


class AppCheckRejected(Exception):
    """The caller did not present a valid token for the exact iOS app."""

    def __init__(self) -> None:
        super().__init__("app check rejected")


class AppCheckUnavailable(Exception):
    """The verifier cannot safely decide whether the token is valid."""

    def __init__(self) -> None:
        super().__init__("app check unavailable")


class AppCheckVerifier(Protocol):
    def verify(self, token: str) -> None:
        """Accept a valid exact-app token or raise an owned exception."""


def _initialize_firebase_app(*, options: dict[str, str], name: str) -> object:
    import firebase_admin

    return firebase_admin.initialize_app(options=options, name=name)


def _verify_firebase_token(token: str, *, app: object) -> Mapping[str, Any]:
    from firebase_admin import app_check

    return app_check.verify_token(token, app=app)


class FirebaseAppCheckVerifier:
    """Lazily initialize Firebase Admin and allow only one configured iOS app."""

    def __init__(
        self,
        *,
        initialize_app: Callable[..., object] = _initialize_firebase_app,
        verify_token: Callable[..., Mapping[str, Any]] = _verify_firebase_token,
    ) -> None:
        self._initialize_app = initialize_app
        self._verify_token = verify_token
        self._app: object | None = None
        self._project_id: str | None = None
        self._lock = Lock()

    @staticmethod
    def _configuration() -> tuple[str, str]:
        enforcement = os.environ.get("APP_CHECK_ENFORCEMENT", "").strip()
        project_id = os.environ.get("FIREBASE_PROJECT_ID", "").strip()
        ios_app_id = os.environ.get("FIREBASE_IOS_APP_ID", "").strip()
        if enforcement != "required" or not project_id or not ios_app_id:
            raise AppCheckUnavailable()
        return project_id, ios_app_id

    def _firebase_app(self, project_id: str) -> object:
        with self._lock:
            if self._app is None:
                try:
                    app = self._initialize_app(
                        options={"projectId": project_id},
                        name=FIREBASE_APP_NAME,
                    )
                except Exception:
                    raise AppCheckUnavailable() from None
                if getattr(app, "project_id", None) != project_id:
                    raise AppCheckUnavailable()
                self._app = app
                self._project_id = project_id
            elif self._project_id != project_id:
                raise AppCheckUnavailable()
            return self._app

    def verify(self, token: str) -> None:
        if not token.strip():
            raise AppCheckRejected()

        project_id, ios_app_id = self._configuration()
        app = self._firebase_app(project_id)
        try:
            claims = self._verify_token(token, app=app)
        except ValueError:
            raise AppCheckRejected() from None
        except PyJWKClientConnectionError:
            raise AppCheckUnavailable() from None
        except PyJWKClientError:
            raise AppCheckRejected() from None
        except Exception:
            raise AppCheckUnavailable() from None

        if not isinstance(claims, Mapping) or claims.get("sub") != ios_app_id:
            raise AppCheckRejected()


class AppCheckASGIMiddleware:
    """Verify paid POST routes before Starlette reads or validates the body."""

    _protected_paths = frozenset({"/", "/api/analyze"})
    _header_name = b"x-firebase-appcheck"

    def __init__(
        self,
        app: ASGIApp,
        *,
        verifier_getter: Callable[[], AppCheckVerifier],
    ) -> None:
        self._app = app
        self._verifier_getter = verifier_getter

    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        if not self._is_protected(scope):
            await self._app(scope, receive, send)
            return

        tokens = [
            value.decode("latin-1").strip()
            for name, value in scope.get("headers", [])
            if name.lower() == self._header_name
        ]
        if len(tokens) != 1 or not tokens[0]:
            await self._send_error(scope, receive, send, 401, "APP_CHECK_FAILED")
            return

        try:
            verifier = self._verifier_getter()
            await anyio.to_thread.run_sync(
                verifier.verify,
                tokens[0],
                abandon_on_cancel=True,
            )
        except AppCheckRejected:
            await self._send_error(scope, receive, send, 401, "APP_CHECK_FAILED")
            return
        except AppCheckUnavailable:
            await self._send_error(
                scope,
                receive,
                send,
                503,
                "APP_CHECK_UNAVAILABLE",
            )
            return
        except Exception:
            await self._send_error(
                scope,
                receive,
                send,
                503,
                "APP_CHECK_UNAVAILABLE",
            )
            return

        await self._app(scope, receive, send)

    @classmethod
    def _is_protected(cls, scope: Scope) -> bool:
        return (
            scope.get("type") == "http"
            and scope.get("method") == "POST"
            and scope.get("path") in cls._protected_paths
        )

    @staticmethod
    async def _send_error(
        scope: Scope,
        receive: Receive,
        send: Send,
        status_code: int,
        code: str,
    ) -> None:
        response = JSONResponse(
            status_code=status_code,
            content={"detail": {"code": code}},
        )
        await response(scope, receive, send)
