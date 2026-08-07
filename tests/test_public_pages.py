from __future__ import annotations

import re
import unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
PAGES = {
    "privacy": ROOT / "public" / "privacy" / "index.html",
    "support": ROOT / "public" / "support" / "index.html",
}


class DocumentProbe(HTMLParser):
    """Collect document structure and visible text without executing anything."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.declarations: list[str] = []
        self.tags: list[str] = []
        self.attributes: list[tuple[str, dict[str, str | None]]] = []
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
        self.attributes.append((tag, dict(attrs)))
        if tag in {"script", "style"}:
            self._suppressed_depth += 1
        if tag == "title":
            self._title_depth += 1

    def handle_startendtag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        self.tags.append(tag)
        self.attributes.append((tag, dict(attrs)))

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
        forbidden_asset_tags = {"audio", "embed", "iframe", "img", "object", "script", "source", "video"}

        for page_name in PAGES:
            with self.subTest(page=page_name):
                raw, page = read_page(page_name)
                lower_raw = raw.lower()
                for marker in forbidden_markers:
                    self.assertNotIn(marker, lower_raw)
                for token in forbidden_tracker_tokens:
                    self.assertNotIn(token, lower_raw)
                self.assertTrue(forbidden_asset_tags.isdisjoint(page.tags))
                self.assertNotIn("link", page.tags, "remote stylesheets and preload assets are forbidden")
                for tag, attrs in page.attributes:
                    self.assertFalse(
                        any(name.lower().startswith("on") for name in attrs),
                        f"inline event handler found on <{tag}>",
                    )
                    self.assertNotIn("src", attrs, f"external asset source found on <{tag}>")

    def test_all_links_are_internal_or_valid_https_urls(self) -> None:
        for page_name in PAGES:
            with self.subTest(page=page_name):
                _raw, page = read_page(page_name)
                hrefs = [
                    attrs["href"]
                    for tag, attrs in page.attributes
                    if tag == "a" and attrs.get("href")
                ]
                self.assertTrue(hrefs)
                for href in hrefs:
                    assert href is not None
                    if href.startswith("/") and not href.startswith("//"):
                        continue
                    parsed = urlsplit(href)
                    self.assertEqual(parsed.scheme, "https", href)
                    self.assertTrue(parsed.hostname, href)
                    self.assertIsNone(parsed.username, href)
                    self.assertIsNone(parsed.password, href)

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
        raw, page = read_page("support")
        text = page.text
        self.assertLess(raw.index('lang="ja"'), raw.index('lang="zh-CN"'))
        self.assertLess(raw.index('lang="zh-CN"'), raw.index('lang="en"'))

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


if __name__ == "__main__":
    unittest.main()
