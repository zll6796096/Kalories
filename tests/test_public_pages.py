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
        "https://firebase.google.com/support/privacy/",
        "https://developer.apple.com/documentation/devicecheck",
        "https://github.com/zll6796096/Kalories/issues/new",
        "mailto:zll6796096@gmail.com",
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


def css_hex_declaration(raw: str, selector: str, property_name: str) -> str:
    block = re.search(rf"{re.escape(selector)}\s*\{{([^}}]*)\}}", raw)
    if block is None:
        raise AssertionError(f"CSS selector is required: {selector}")
    declaration = re.search(
        rf"(?:^|;)\s*{re.escape(property_name)}\s*:\s*(#[0-9a-fA-F]{{6}})\s*;",
        block.group(1),
    )
    if declaration is None:
        raise AssertionError(
            f"{selector} must declare {property_name} as a six-digit hex color"
        )
    return declaration.group(1).lower()


def localized_section_text(raw: str, lang: str) -> str:
    match = re.search(
        rf'<section\b[^>]*\blang="{re.escape(lang)}"[^>]*>(.*?)</section>',
        raw,
        re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"localized section is required: {lang}")
    section = DocumentProbe()
    section.feed(match.group(0))
    section.close()
    return section.text


class PublicPageTests(unittest.TestCase):
    def test_pages_have_static_japanese_first_document_structure(self) -> None:
        expected_titles = {
            "privacy": "カロスキャン プライバシーポリシー",
            "support": "カロスキャン サポート",
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
                icon_links = [
                    attrs
                    for tag, attrs in page.attributes
                    if tag == "link" and attrs.get("rel") == "icon"
                ]
                self.assertEqual(
                    icon_links,
                    [
                        {
                            "rel": "icon",
                            "href": "/favicon.svg",
                            "type": "image/svg+xml",
                        }
                    ],
                )

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
                            approved_anchor = (
                                (tag, normalized_name) == ("a", "href")
                                and value in APPROVED_HREFS
                            )
                            approved_favicon = (
                                (tag, normalized_name) == ("link", "href")
                                and value == "/favicon.svg"
                            )
                            self.assertTrue(
                                approved_anchor or approved_favicon,
                                f"unapproved URL-bearing attribute <{tag} {name}>",
                            )
                            if approved_anchor:
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

    def test_declared_text_colors_meet_wcag_aa_on_actual_backgrounds(self) -> None:
        expected = {
            "privacy": {
                "root_text": (":root", "color", "#18201d"),
                "page": (":root", "background", "#f5f7f5"),
                "card": ("header, section, aside", "background", "#ffffff"),
                "notice": (".notice", "background", "#f1f6f3"),
                "warning": (".warning", "background", "#fff8ec"),
                "heading": ("h1, h2", "color", "#16251f"),
                "secondary": (".updated", "color", "#59645f"),
                "link": ("a", "color", "#265f49"),
            },
            "support": {
                "root_text": (":root", "color", "#18201d"),
                "page": (":root", "background", "#f5f7f5"),
                "card": ("header, section, aside", "background", "#ffffff"),
                "warning": (".warning", "background", "#fff8ec"),
                "heading": ("h1, h2, h3", "color", "#16251f"),
                "secondary": (".lede", "color", "#4f5c56"),
                "link": ("a", "color", "#265f49"),
                "warning_strong": (".warning strong", "color", "#6d4310"),
            },
        }
        combinations = {
            "privacy": (
                ("root_text", "page"),
                ("root_text", "card"),
                ("root_text", "notice"),
                ("root_text", "warning"),
                ("heading", "card"),
                ("heading", "notice"),
                ("heading", "warning"),
                ("secondary", "card"),
                ("link", "card"),
            ),
            "support": (
                ("root_text", "page"),
                ("root_text", "card"),
                ("root_text", "warning"),
                ("heading", "card"),
                ("heading", "warning"),
                ("secondary", "card"),
                ("link", "card"),
                ("warning_strong", "warning"),
            ),
        }

        for page_name, declarations in expected.items():
            raw, _page = read_page(page_name)
            colors: dict[str, str] = {}
            for name, (selector, property_name, expected_color) in declarations.items():
                with self.subTest(page=page_name, declaration=name):
                    color = css_hex_declaration(raw, selector, property_name)
                    self.assertEqual(color, expected_color)
                    colors[name] = color
            for foreground, background in combinations[page_name]:
                with self.subTest(
                    page=page_name, foreground=foreground, background=background
                ):
                    self.assertGreaterEqual(
                        contrast_ratio(colors[foreground], colors[background]), 4.5
                    )

    def test_privacy_page_states_the_complete_conservative_provider_contract(self) -> None:
        raw, page = read_page("privacy")
        text = page.text
        required_terms = (
            "最終更新日：2026年8月11日",
            "この写真を分析",
            "HTTPS",
            "カロスキャンのバックエンド",
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
            "iOSの「設定」",
            "医療診断",
            "医療助言",
            "臨床用途",
            "Firebase App Check",
            "Apple App Attest",
            "IPアドレス",
            "アプリID",
            "バンドルID",
            "技術・運用情報",
            "アテステーション資料",
            "App Checkトークン",
            "行動分析",
            "追跡",
            "Firebase App Check 和 Apple App Attest",
            "IP 地址",
            "应用 ID",
            "软件包 ID",
            "Firebase App Check and Apple App Attest",
            "IP addresses",
            "app IDs",
            "bundle IDs",
        )
        for term in required_terms:
            with self.subTest(term=term):
                self.assertIn(term, text)

        for forbidden_public_pattern in (
            r"testflight",
            r"\binvited\s+testers?\b",
            r"一般公開のApp Store配布には別途審査と確認が必要",
            r"まだ確認済みではありません",
        ):
            with self.subTest(
                contract="forbidden public-release wording",
                pattern=forbidden_public_pattern,
            ):
                self.assertIsNone(
                    re.search(forbidden_public_pattern, text, re.IGNORECASE),
                    f"public privacy page must not contain: {forbidden_public_pattern}",
                )

        for required_public_term in (
            "カロスキャン",
            "日本のApp Storeで公開",
            "zll6796096@gmail.com",
            "Google Gemini",
            "Firebase App Check",
            "Apple App Attest",
            "55日間",
            "開発者ログを無効",
            "データセット共有を利用しません",
            "医療診断",
            "医療助言",
        ):
            with self.subTest(
                contract="required public privacy wording", term=required_public_term
            ):
                self.assertIn(required_public_term, text)

        self.assertRegex(text, r"写真[^。]*この写真を分析[^。]*送信")
        self.assertRegex(text, r"アカウント[^。]*広告[^。]*行動追跡[^。]*ありません")
        self.assertRegex(text, r"アプリ.+バックエンド.+保存しません")
        self.assertRegex(text, r"クラウド上.+食事履歴.+ありません")
        self.assertRegex(text, r"アカウント.+広告.+追跡.+解析SDK")
        self.assertRegex(text, r"再撮影.+破棄")
        self.assertRegex(text, r"有料サービス条件.+前提")
        self.assertRegex(
            text,
            r"Google.+不正使用の検出および防止.+プロンプト.+コンテキスト情報.+出力を55日間保持します",
        )
        self.assertEqual(text.count("出力を55日間保持します"), 1)
        self.assertNotIn("最大55日間保持する場合があります", text)
        self.assertRegex(text, r"前記「保存期間」.+55日間の保持")
        self.assertRegex(text, r"55日間.+写真入力.+分析出力")
        self.assertIn("ゼロデータ保持の適用を主張しません", text)
        self.assertRegex(
            text,
            r"Googleによる不正使用監視のログとは別に.+Google AI Studio.+開発者が所有する開発者ログ",
        )
        self.assertRegex(text, r"データセット共有.+別.+オプトイン")
        self.assertRegex(text, r"条件.+変更.+再確認.+分析機能を停止")
        self.assertRegex(text, r"送信済み.+保持期間")
        self.assertRegex(text, r"削除する.+履歴.+ありません")
        self.assertNotRegex(
            text,
            r"(?:プロンプト|写真入力|分析出力).{0,80}保持しません|保存期間は0|ゼロ保持を適用",
        )
        self.assertNotIn("自動的に期限切れ", text)

        retention_start = raw.index("<h2>保存期間</h2>")
        retention_end = raw.index("</section>", retention_start)
        retention_page = DocumentProbe()
        retention_page.feed(raw[retention_start:retention_end])
        retention_page.close()
        self.assertEqual(retention_page.text.count("出力を55日間保持します"), 1)
        self.assertNotRegex(
            retention_page.text,
            r"(?:自動(?:的)?に|55日(?:間)?後に|保持期間後に).{0,80}(?:期限切れ|削除|消去)",
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
        self.assertIn("https://firebase.google.com/support/privacy/", hrefs)
        self.assertIn("https://developer.apple.com/documentation/devicecheck", hrefs)
        self.assertIn("mailto:zll6796096@gmail.com", hrefs)

        integrity_sections = [
            attrs
            for tag, attrs in page.attributes
            if tag == "section" and attrs.get("data-integrity-disclosure") == "true"
        ]
        self.assertEqual(
            [attrs.get("lang") for attrs in integrity_sections],
            ["ja", "zh-CN", "en"],
        )

    def test_support_page_is_japanese_first_and_covers_safe_manual_help(self) -> None:
        raw, page = read_page("support")
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

        localized_terms = {
            "ja": ("カロスキャン", "この写真を分析"),
            "zh-CN": ("カロスキャン", "分析这张照片"),
            "en": ("カロスキャン", "Analyze this photo"),
        }
        for lang, terms in localized_terms.items():
            section_text = localized_section_text(raw, lang)
            for term in terms:
                with self.subTest(lang=lang, term=term):
                    self.assertIn(term, section_text)
            with self.subTest(lang=lang, term="legacy display name"):
                self.assertNotIn("Kalories", section_text)
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
            "APP_CHECK_FAILED",
            "1回だけ",
            "画像を読み取る前",
            "完整性令牌",
            "once",
            "integrity token",
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

        for forbidden_public_pattern in (
            r"testflight",
            r"\binvited\s+testers?\b",
        ):
            with self.subTest(
                contract="forbidden public-release wording",
                pattern=forbidden_public_pattern,
            ):
                self.assertIsNone(
                    re.search(forbidden_public_pattern, text, re.IGNORECASE),
                    f"public support page must not contain: {forbidden_public_pattern}",
                )

        for required_public_term in (
            "App Store",
            "日本のApp Storeで公開するカロスキャンの利用案内です。",
            "zll6796096@gmail.com",
            "医療診断",
            "medical diagnosis",
            "临床用途",
            "clinical purposes",
        ):
            with self.subTest(
                contract="required public support wording", term=required_public_term
            ):
                self.assertIn(required_public_term, text)

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
        self.assertIn("mailto:zll6796096@gmail.com", hrefs)

    def test_public_pages_disclose_the_adult_only_local_confirmation_contract(
        self,
    ) -> None:
        privacy_text = read_page("privacy")[1].text
        for required in (
            "カロスキャンは18歳以上の方のみ利用できます。",
            "初回起動時に「18歳以上です」を選択した事実だけを端末内に保存します。",
            "生年月日、氏名、本人確認書類は収集しません。",
            "年齢確認の結果はKalories、Google、FirebaseまたはAppleへ送信しません。",
        ):
            with self.subTest(page="privacy", required=required):
                self.assertIn(required, privacy_text)

        support_text = read_page("support")[1].text
        for required in (
            "18歳以上の方のみ利用できます",
            "仅限18岁以上用户",
            "only to users aged 18 or older",
        ):
            with self.subTest(page="support", required=required):
                self.assertIn(required, support_text)

        for forbidden in ("一般の利用者", "一般用户", "general users"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, privacy_text)
                self.assertNotIn(forbidden, support_text)


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
                "/privacy/": "カロスキャン プライバシーポリシー",
                "/support/": "カロスキャン サポート",
            }
            for route, heading in expected.items():
                with self.subTest(route=route):
                    status_code, body = responses[route]
                    self.assertEqual(status_code, 200)
                    self.assertIn(heading, body)


if __name__ == "__main__":
    unittest.main()
