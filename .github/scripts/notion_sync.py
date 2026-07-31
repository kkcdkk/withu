#!/usr/bin/env python3
"""GitHub Issue → Notion 이슈 DB 동기화 스크립트.

GitHub Actions 의 `issues` 이벤트가 트리거되면 실행된다.
이벤트 페이로드의 issue 객체를 받아 Notion 이슈 DB 의 같은 GitHub URL row 를
찾아서 갱신하고, 없으면 새 row 를 만든다.

환경 변수
---------
NOTION_TOKEN          Notion integration token (repo Secret)
NOTION_ISSUE_DB_ID    이슈 DB id (workflow 에서 주입)
ISSUE_PAYLOAD         github.event.issue 의 JSON 문자열

매칭 키: issue.html_url == Notion 'GitHub 이슈' (url) 프로퍼티

PATCH 시 갱신하는 프로퍼티 (그 외는 사용자가 손으로 둔 값 그대로 보존):
  이슈            f"#{number} — {title}"
  상태            Closed if state == "closed" else Open
  GitHub 이슈     html_url
  GitHub 번호     number
  GitHub 라벨    labels[].name  (multi_select; Notion 이 새 옵션 자동 생성)
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.notion.com/v1"
NOTION_VERSION = "2022-06-28"

token = os.environ["NOTION_TOKEN"]
db_id = os.environ["NOTION_ISSUE_DB_ID"]
issue = json.loads(os.environ["ISSUE_PAYLOAD"])

headers = {
    "Authorization": f"Bearer {token}",
    "Notion-Version": NOTION_VERSION,
    "Content-Type": "application/json",
}


def request(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        f"{API}{path}", data=data, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(
            f"HTTP {e.code} on {method} {path}: {e.read().decode('utf-8')}",
            file=sys.stderr,
        )
        raise


def build_props(*, on_create: bool) -> dict:
    title = f"#{issue['number']} — {issue['title']}"
    state = "Closed" if issue["state"] == "closed" else "Open"
    labels = [{"name": label["name"]} for label in issue.get("labels", [])]

    props = {
        "이슈": {"title": [{"type": "text", "text": {"content": title}}]},
        "상태": {"select": {"name": state}},
        "GitHub 이슈": {"url": issue["html_url"]},
        "GitHub 번호": {"number": issue["number"]},
        "GitHub 라벨": {"multi_select": labels},
    }

    if on_create:
        # 새 row 일 때만 우선순위 기본값. 기존 row 의 사용자 값은 절대 덮어쓰지 않음.
        props["우선순위"] = {"select": {"name": "보통"}}

    return props


def find_existing_row() -> str | None:
    result = request(
        "POST",
        f"/databases/{db_id}/query",
        {
            "filter": {
                "property": "GitHub 이슈",
                "url": {"equals": issue["html_url"]},
            }
        },
    )
    pages = result.get("results", [])
    return pages[0]["id"] if pages else None


def main() -> int:
    existing_id = find_existing_row()
    if existing_id:
        print(f"updating page {existing_id} for issue #{issue['number']}")
        request(
            "PATCH",
            f"/pages/{existing_id}",
            {"properties": build_props(on_create=False)},
        )
    else:
        print(f"creating new page for issue #{issue['number']}")
        request(
            "POST",
            "/pages",
            {
                "parent": {"database_id": db_id},
                "properties": build_props(on_create=True),
            },
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
