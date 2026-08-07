from __future__ import annotations

import os
import re
import unittest
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAGES = {
    "privacy": ROOT / "public" / "privacy" / "index.html",
    "support": ROOT / "public" / "support" / "index.html",
}
APPROVED_HREFS = frozenset(
    {
        "/privacy/",
        "/support/",
        "https://ai.google.dev/gemini-api/terms",
        "https://ai.google.dev/gemini-api/docs/usage-policies",
        "https://ai.google.dev/gemini-api/docs/logs-policy",
        "https://ai.google.dev/gemini-api/docs/zdr",
        "https://github.com/zll6796096/Kalories/issues/new",
    }
)
FORBIDDEN_TAGS = frozenset(
    {
        "audio",
        "base",
        "button",
        "embed",
        "form",
        "iframe",
        "img",
        "input",
        "link",
        "object",
        "option",
        "script",
        "select",
        "source",
        "textarea",
        "video",
    }
)
URL_BEARING_ATTRIBUTES = frozenset(
    {
        "action",
        "background",
        "cite",
        "data",
        "formaction",
        "href",
        "longdesc",
        "manifest",
        "ping",
        "poster",
        "profile",
        "src",
        "srcdoc",
        "srcset",
        "usemap",
        "xlink:href",
    }
)


class DocumentProbe(HTMLParser):
    """Collect document structure and visible text without executing anything."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.declarations: list[str] = []
        self.tags: list[str] = []
        self.attributes: list[tuple[str, dict[str, str | None]]] = []
        self.attribute_pairs: list[
            tuple[str, tuple[tuple[str, str | None], ...]]
        ] = []
        self._suppressed_depth = 0
        self._title_depth = 0
        self._title_parts: list[str] = []
        self._text_parts: list[str] = []

    def handle_decl(self, decl: str) -> None:
        self.declarations.append(decl)

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        self.tags.append(tag)
        pairs = tuple(attrs)
        self.attribute_pairs.append((tag, pairs))
        self.attributes.append((tag, dict(pairs)))
        if tag in {"script", "style"}:
            self._suppressed_depth += 1
        if tag == "title":
            self._title_depth += 1

    def handle_startendtag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        self.tags.append(tag)
        pairs = tuple(attrs)
        self.attribute_pairs.append((tag, pairs))
        self.attributes.append((tag, dict(pairs)))

    def handle_endtag(self, tag: str) -> None:
        if tag == "title" and self._title_depth:
            self._title_depth -= 1
        if tag in {"script", "style"} and self._suppressed_depth:
            self._suppressed_depth -= 1

    def handle_data(self, data: str) -> None:
        if self._title_depth:
            self._title_parts.append(data)
        if not self._suppressed_depth:
            self._text_parts.append(data)

    @property
    def title(self) -> str:
        return " ".join(" ".join(self._title_parts).split())

    @property
    def text(self) -> str:
        return " ".join(" ".join(self._text_parts).split())


def read_page(page_name: str) -> tuple[str, DocumentProbe]:
    path = PAGES[page_name]
    if not path.is_file():
        raise AssertionError(f"required public page is missing: {path.relative_to(ROOT)}")
    raw = path.read_text(encoding="utf-8")
    parser = DocumentProbe()
    parser.feed(raw)
    parser.close()
    return raw, parser


def relative_luminance(hex_color: str) -> float:
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", hex_color):
        raise ValueError(f"invalid six-digit hex color: {hex_color}")

    channels = [int(hex_color[index : index + 2], 16) / 255 for index in (1, 3, 5)]
    linear = [
        value / 12.92
        if value <= 0.04045
        else ((value + 0.055) / 1.055) ** 2.4
        for value in channels
    ]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(first: str, second: str) -> float:
    light, dark = sorted(
        (relative_luminance(first), relative_luminance(second)), reverse=True
    )
    return (light + 0.05) / (dark + 0.05)


def focus_outline_color(raw: str) -> str:
    block = re.search(r"a:focus-visible\s*\{([^}]*)\}", raw)
    if block is None:
        raise AssertionError("a:focus-visible CSS rule is required")
    declarations = block.group(1)
    outline = re.search(
        r"outline\s*:\s*3px\s+solid\s+(#[0-9a-fA-F]{6})\s*;", declarations
    )
    if outline is None:
        raise AssertionError("focus outline must be a 3px solid six-digit hex color")
    if re.search(r"outline-offset\s*:\s*3px\s*;", declarations) is None:
        raise AssertionError("focus outline offset must be 3px")
    return outline.group(1).lower()


class PublicPageTests(unittest.TestCase):
    def test_pages_have_static_japanese_first_document_structure(self) -> None:
        expected_titles = {
            "privacy": "Kalories プライバシーポリシー",
            "support": "Kalories サポート",
        }
        for page_name in PAGES:
            with self.subTest(page=page_name):
                raw, page = read_page(page_name)
                self.assertTrue(
                    raw.lstrip().lower().startswith("<!doctype html>"),
                    "document must start with an HTML5 doctype",
                )
                self.assertIn("doctype html", [item.lower() for item in page.declarations])
                html_nodes = [attrs for tag, attrs in page.attributes if tag == "html"]
                self.assertEqual(len(html_nodes), 1)
                self.assertEqual(html_nodes[0].get("lang"), "ja")
                metas = [attrs for tag, attrs in page.attributes if tag == "meta"]
                self.assertTrue(
                    any((attrs.get("charset") or "").lower() == "utf-8" for attrs in metas)
                )
                self.assertTrue(
                    any(
                        (attrs.get("name") or "").lower() == "viewport"
                        and "width=device-width" in (attrs.get("content") or "")
                        for attrs in metas
                    )
                )
                self.assertEqual(page.tags.count("title"), 1)
                self.assertEqual(page.title, expected_titles[page_name])
                self.assertEqual(page.tags.count("main"), 1)
                self.assertGreaterEqual(page.tags.count("h1"), 1)

    def test_pages_have_no_javascript_tracking_or_external_assets(self) -> None:
        forbidden_markers = ("todo", "tbd", "placeholder", "要確認")
        forbidden_tracker_tokens = (
            "googletagmanager",
            "google-analytics",
            "gtag(",
            "segment.com",
            "mixpanel",
            "hotjar",
            "document.cookie",
            "set-cookie",
        )
        for page_name in PAGES:
            with self.subTest(page=page_name):
                raw, page = read_page(page_name)
                lower_raw = raw.lower()
                for marker in forbidden_markers:
                    self.assertNotIn(marker, lower_raw)
                for token in forbidden_tracker_tokens:
                    self.assertNotIn(token, lower_raw)
                self.assertIsNone(re.search(r"@import\b", lower_raw))
                self.assertIsNone(re.search(r"\burl\s*\(", lower_raw))
                self.assertTrue(FORBIDDEN_TAGS.isdisjoint(page.tags))

                for tag, pairs in page.attribute_pairs:
                    names = [name.lower() for name, _value in pairs]
                    self.assertEqual(
                        len(names),
                        len(set(names)),
                        f"duplicate attribute name found on <{tag}>",
                    )
                    hrefs = []
                    for name, value in pairs:
                        normalized_name = name.lower()
                        self.assertFalse(
                            normalized_name.startswith("on"),
                            f"inline event handler found on <{tag}>",
                        )
                        if value is not None:
                            self.assertIsNone(
                                re.match(r"\s*(?:data|javascript)\s*:", value, re.I),
                                f"active URL scheme found on <{tag} {name}>",
                            )
                        if normalized_name in URL_BEARING_ATTRIBUTES:
                            self.assertEqual(
                                (tag, normalized_name),
                                ("a", "href"),
                                f"unapproved URL-bearing attribute <{tag} {name}>",
                            )
                            self.assertIn(value, APPROVED_HREFS)
                            hrefs.append(value)
                    if tag == "a":
                        self.assertEqual(len(hrefs), 1, "every link needs one approved href")

                metas = [attrs for tag, attrs in page.attributes if tag == "meta"]
                self.assertTrue(
                    all(
                        (attrs.get("http-equiv") or "").strip().lower() != "refresh"
                        for attrs in metas
                    ),
                    "meta refresh is forbidden",
                )

    def test_pages_use_only_the_exact_approved_links(self) -> None:
        observed_hrefs: set[str] = set()
        for page_name in PAGES:
            with self.subTest(page=page_name):
                _raw, page = read_page(page_name)
                observed_hrefs.update(
                    attrs["href"]
                    for tag, attrs in page.attributes
                    if tag == "a" and attrs.get("href")
                )
        self.assertEqual(observed_hrefs, APPROVED_HREFS)

    def test_focus_outline_has_three_to_one_contrast_on_page_backgrounds(self) -> None:
        for page_name in PAGES:
            with self.subTest(page=page_name):
                raw, _page = read_page(page_name)
                focus_color = focus_outline_color(raw)
                self.assertEqual(focus_color, "#265f49")
                for background in ("#ffffff", "#f5f7f5"):
                    with self.subTest(page=page_name, background=background):
                        self.assertGreaterEqual(
                            contrast_ratio(focus_color, background), 3.0
                        )

    def test_privacy_page_states_the_complete_conservative_provider_contract(self) -> None:
        raw, page = read_page("privacy")
        text = page.text
        required_terms = (
            "最終更新日：2026年8月8日",
            "分析する",
            "HTTPS",
            "Kaloriesのバックエンド",
            "Google Gemini",
            "利用目的",
            "保存期間",
            "第三者提供",
            "同意の撤回",
            "削除",
            "問い合わせ",
            "画像バイト",
            "Base64",
            "モデル出力",
            "Cloud Run",
            "運用メタデータ",
            "プロンプト",
            "コンテキスト情報",
            "出力",
            "55日間",
            "不正使用の検出および防止",
            "ゼロデータ保持",
            "Google AI Studio",
            "開発者ログ",
            "データセット共有",
            "オプトイン",
            "有料サービス",
            "Google製品の改善",
            "TestFlight",
            "18歳以上",
            "iOSの「設定」",
            "医療診断",
            "医療助言",
            "臨床用途",
        )
        for term in required_terms:
            with self.subTest(term=term):
                self.assertIn(term, text)

        self.assertRegex(text, r"写真.+分析する.+タップ.+送信")
        self.assertRegex(text, r"アプリ.+バックエンド.+保存しません")
        self.assertRegex(text, r"クラウド上.+食事履歴.+ありません")
        self.assertRegex(text, r"アカウント.+広告.+追跡.+解析SDK")
        self.assertRegex(text, r"再撮影.+破棄")
        self.assertRegex(text, r"有料サービス.+必須条件")
        self.assertRegex(
            text,
            r"Google.+不正使用の検出および防止.+プロンプト.+コンテキスト情報.+出力.+55日間保持します",
        )
        self.assertRegex(text, r"55日間.+写真入力.+分析出力")
        self.assertRegex(text, r"承認.+確認できていません")
        self.assertRegex(
            text,
            r"Googleによる不正使用監視のログとは別に.+Google AI Studio.+開発者が所有する開発者ログ",
        )
        self.assertRegex(text, r"データセット共有.+別.+オプトイン")
        self.assertIn(
            "開発者ログが無効であることは、TestFlight配布の必須条件です",
            text,
        )
        self.assertIn(
            "データセット共有を選択しないことも、TestFlight配布の必須条件です",
            text,
        )
        self.assertIn(
            "現在のCloudプロジェクトを通じたGemini API利用が有料サービスとして扱われることは、まだ確認済みではありません",
            text,
        )
        self.assertIn(
            "現在のCloudプロジェクトで開発者ログが無効であることは、まだ確認済みではありません",
            text,
        )
        self.assertIn(
            "データセット共有が選択されていないことも、まだ確認済みではありません",
            text,
        )
        self.assertRegex(text, r"条件.+満たせない.+配布しません")
        self.assertRegex(text, r"送信済み.+保持期間")
        self.assertRegex(text, r"削除する.+履歴.+ありません")
        self.assertNotRegex(text, r"保持しません|保存期間は0|ゼロ保持を適用")
        self.assertNotIn("自動的に期限切れ", text)

        retention_start = raw.index("<h2>保存期間</h2>")
        retention_end = raw.index("</section>", retention_start)
        retention_page = DocumentProbe()
        retention_page.feed(raw[retention_start:retention_end])
        retention_page.close()
        self.assertNotRegex(
            retention_page.text,
            r"(?:自動(?:的)?に|55日(?:間)?後に|保持期間後に).{0,80}(?:期限切れ|削除|消去)",
        )

        self.assertRegex(text, r"管理されたTestFlight.+招待された18歳以上")
        self.assertIn(
            "一般公開のApp Store配布には別途審査と確認が必要で、現時点では未完了です",
            text,
        )
        self.assertNotIn("未解決の別のリリース門禁", text)
        self.assertNotIn("現在のCloudプロジェクトが有料サービスである", text)

        hrefs = [
            attrs["href"]
            for tag, attrs in page.attributes
            if tag == "a" and attrs.get("href")
        ]
        self.assertIn("/support/", hrefs)
        self.assertIn("https://ai.google.dev/gemini-api/terms", hrefs)
        self.assertIn("https://ai.google.dev/gemini-api/docs/usage-policies", hrefs)
        self.assertIn("https://ai.google.dev/gemini-api/docs/logs-policy", hrefs)
        self.assertIn("https://ai.google.dev/gemini-api/docs/zdr", hrefs)

    def test_support_page_is_japanese_first_and_covers_safe_manual_help(self) -> None:
        _raw, page = read_page("support")
        text = page.text
        localized_sections = [
            attrs
            for tag, attrs in page.attributes
            if tag == "section" and attrs.get("lang") is not None
        ]
        expected_heading_ids = ["support-ja", "support-zh", "support-en"]
        self.assertEqual(
            [attrs.get("lang") for attrs in localized_sections],
            ["ja", "zh-CN", "en"],
        )
        self.assertEqual(
            [attrs.get("aria-labelledby") for attrs in localized_sections],
            expected_heading_ids,
        )
        self.assertEqual(
            [
                attrs["id"]
                for tag, attrs in page.attributes
                if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}
                and attrs.get("id")
            ],
            expected_heading_ids,
        )

        required_terms = (
            "カメラ",
            "設定",
            "食べ物が写っていない",
            "再撮影",
            "ネットワーク",
            "タイムアウト",
            "RATE_LIMITED",
            "手動で",
            "自動再試行しません",
            "TestFlight",
            "18歳以上",
            "医療診断",
            "プライバシー",
            "相片",
            "凭据",
            "API 密钥",
            "秘密信息",
            "meal photos",
            "credentials",
            "API keys",
            "secrets",
        )
        for term in required_terms:
            with self.subTest(term=term):
                self.assertIn(term, text)

        self.assertRegex(text, r"公開Issue.+個人的な食事写真.+認証情報.+APIキー.+秘密情報")
        self.assertRegex(text, r"公开 Issue.+个人餐食照片.+凭据.+API 密钥.+秘密信息")
        self.assertRegex(text, r"public issue.+personal meal photos.+credentials.+API keys.+secrets")

        hrefs = [
            attrs["href"]
            for tag, attrs in page.attributes
            if tag == "a" and attrs.get("href")
        ]
        self.assertIn("/privacy/", hrefs)
        self.assertIn("https://github.com/zll6796096/Kalories/issues/new", hrefs)


if os.environ.get("KALORIES_REQUIRE_DIST") == "1":

    class BuiltPublicPageTests(unittest.TestCase):
        def test_dist_pages_match_public_sources_byte_for_byte(self) -> None:
            for page_name, source_path in PAGES.items():
                with self.subTest(page=page_name):
                    dist_path = ROOT / "dist" / page_name / "index.html"
                    self.assertTrue(
                        dist_path.is_file(), f"built page is missing: {dist_path}"
                    )
                    self.assertEqual(dist_path.read_bytes(), source_path.read_bytes())

        def test_actual_dist_mount_serves_both_public_pages(self) -> None:
            import asyncio

            from fastapi import FastAPI
            from httpx import ASGITransport, AsyncClient

            from api.analyze import mount_frontend

            application = FastAPI()
            self.assertTrue(mount_frontend(application, ROOT / "dist"))

            async def fetch_routes() -> dict[str, tuple[int, str]]:
                transport = ASGITransport(app=application)
                async with AsyncClient(
                    transport=transport, base_url="http://testserver"
                ) as client:
                    routes = ("/privacy/", "/support/")
                    responses = {route: await client.get(route) for route in routes}
                    return {
                        route: (response.status_code, response.text)
                        for route, response in responses.items()
                    }

            responses = asyncio.run(fetch_routes())
            expected = {
                "/privacy/": "Kalories プライバシーポリシー",
                "/support/": "Kalories サポート",
            }
            for route, heading in expected.items():
                with self.subTest(route=route):
                    status_code, body = responses[route]
                    self.assertEqual(status_code, 200)
                    self.assertIn(heading, body)


if __name__ == "__main__":
    unittest.main()
