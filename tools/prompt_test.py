#!/usr/bin/env python3
"""
withu 디폴트 프롬프트 테스트 하니스.

각 캐릭터 상태(userFacing)의 '디폴트 프롬프트'를 앱과 똑같이 조립해서
서버 /generate 로 이미지를 뽑고, [이미지 | 프롬프트 전문] contact sheet(HTML)로 모아 본다.

- 상태 목록 + generationHint 를 withu/Character/CharacterState.swift 에서 자동 파싱(소스와 동기화).
- 서버가 추가로 입히는 시스템 프롬프트(스타일/콘텐츠)는 cloudflare/withu-api/src/index.js 에 있음 — 여기선 클라 프롬프트만 다룸.

사용법 (이 세션에서 ! 로 직접 실행 — 매 생성 = OpenAI 과금):
  ! cd ~/Desktop/withu && python3 tools/prompt_test.py                    # 8개 전부, low
  ! cd ~/Desktop/withu && python3 tools/prompt_test.py --quality medium   # 품질 올려서
  ! cd ~/Desktop/withu && python3 tools/prompt_test.py --states idle,walking --style pixel
  ! cd ~/Desktop/withu && python3 tools/prompt_test.py --identity "round green cat, big eyes"
끝나면 prompt-tests/index.html 가 자동으로 열림.
"""
import os, re, json, base64, argparse, html, subprocess, ssl, time, urllib.request, urllib.error

# macOS Python 이 시스템 루트 인증서를 못 찾는 경우 대비 — certifi 번들 사용, 없으면 미검증 폴백.
try:
    import certifi
    SSL_CTX = ssl.create_default_context(cafile=certifi.where())
except Exception:
    SSL_CTX = ssl.create_default_context()
    SSL_CTX.check_hostname = False
    SSL_CTX.verify_mode = ssl.CERT_NONE

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE_FILE = os.path.join(ROOT, "withu", "Character", "CharacterState.swift")
SERVER = "https://withu-api.ysy1398.workers.dev"

# 앱(BatchCharacterGenView)이 항상 덧붙이는 흰배경 가드 — 글자 그대로 일치시킴.
WHITE_BG = (". Solid clean WHITE background, no shadows, no gradients. "
            "Never draw a checkerboard or transparency grid pattern — "
            "the background must be one flat solid white color.")
# baseIdentity 기본값 (앱의 fallback 과 동일). --identity 로 덮어쓰기.
DEFAULT_IDENTITY = "round chibi mascot character with simple features and friendly closed-eye smile"


def parse_states():
    """CharacterState.swift 에서 userFacing 순서 + generationHint(frame0) 파싱."""
    src = open(STATE_FILE, encoding="utf-8").read()
    m = re.search(r"userFacing[^=]*=\s*\[(.*?)\]", src, re.S)
    facing = re.findall(r"\.(\w+)", m.group(1))
    # generationHint 프로퍼티 구간만 잘라서(다음 프로퍼티 전까지) 파싱
    start = src.index("var generationHint")
    end = src.index("var animationFrame2Hint", start)
    block = src[start:end]
    hints = {}
    for mm in re.finditer(r'case\s+\.(\w+)\s*:\s*return\s+"((?:[^"\\]|\\.)*)"', block):
        hints[mm.group(1)] = mm.group(2)
    # 한글 라벨(koreanShortLabel)도 같이 — 표시용
    ks = src[src.index("var koreanShortLabel"):src.index("var generationHint")]
    labels = {a: b for a, b in re.findall(r'case\s+\.(\w+)\s*:\s*return\s+"([^"]*)"', ks)}
    return facing, hints, labels


def build_prompt(identity, hint):
    """앱 BatchCharacterGenView.runOne(frame0, reference 없음)과 동일 조립."""
    return f"{identity}, {hint}{WHITE_BG}"


def generate(prompt, quality, art_style, region_retries=8):
    body = json.dumps({
        "prompt": prompt, "steps": 30, "width": 1024, "height": 1024,
        "quality": quality, "art_style": art_style, "style": "auto",
    }).encode()
    # OpenAI 지역 차단(403 "Country ... not supported")은 Cloudflare 출구 IP 가
    # 요청마다 달라서 간헐적 — 새 요청으로 재시도하면 보통 곧 지원 지역으로 나감.
    for attempt in range(region_retries + 1):
        req = urllib.request.Request(SERVER + "/generate", data=body,
                                     headers={"Content-Type": "application/json",
                                              "X-Withu-Kind": "single",
                                              # 기본 Python-urllib UA 는 Cloudflare 가 403 으로 막음.
                                              "User-Agent": "withu-prompt-test/1.0"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=600, context=SSL_CTX) as r:
                data = json.loads(r.read())
            return base64.b64decode(data["image_base64"])
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="ignore")
            if e.code == 403 and "not supported" in detail and attempt < region_retries:
                print(f"      ↻ 지역차단, 재시도 {attempt + 1}/{region_retries}", flush=True)
                time.sleep(1.5)
                continue
            raise
    raise RuntimeError("지역차단 재시도 모두 실패")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--states", default="all", help="쉼표 구분 또는 all(=userFacing 전부)")
    ap.add_argument("--identity", default=DEFAULT_IDENTITY)
    ap.add_argument("--quality", default="low", choices=["low", "medium", "high"])
    ap.add_argument("--style", default="casual", choices=["casual", "pixel"])
    ap.add_argument("--out", default=os.path.join(ROOT, "prompt-tests"))
    args = ap.parse_args()

    facing, hints, labels = parse_states()
    states = facing if args.states == "all" else [s.strip() for s in args.states.split(",")]
    states = [s for s in states if s in hints]
    if not states:
        print("⚠️ 해당 상태 없음. 가능:", ", ".join(facing)); return

    os.makedirs(args.out, exist_ok=True)
    print(f"생성 대상 {len(states)}개 · 품질={args.quality} · 스타일={args.style}")
    print(f"baseIdentity = {args.identity}\n")

    rows = []
    for i, st in enumerate(states, 1):
        prompt = build_prompt(args.identity, hints[st])
        label = labels.get(st, st)
        print(f"[{i}/{len(states)}] {st} ({label}) 생성 중…", flush=True)
        try:
            png = generate(prompt, args.quality, args.style)
            fname = f"{st}.png"
            with open(os.path.join(args.out, fname), "wb") as f:
                f.write(png)
            print(f"   ✅ {fname}")
            rows.append((st, label, hints[st], prompt, fname, None))
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="ignore")
            print(f"   ❌ HTTP {e.code}: {detail[:200]}")
            rows.append((st, label, hints[st], prompt, None, f"HTTP {e.code}: {detail[:300]}"))
        except Exception as e:
            print(f"   ❌ {e}")
            rows.append((st, label, hints[st], prompt, None, str(e)))

    # contact sheet
    cards = []
    for st, label, hint, prompt, fname, err in rows:
        img = (f'<img src="{html.escape(fname)}" alt="{html.escape(st)}">'
               if fname else f'<div class="err">실패<br>{html.escape(err or "")}</div>')
        cards.append(f"""
      <div class="card">
        <div class="img">{img}</div>
        <div class="meta">
          <div class="state">{html.escape(label)} <span class="raw">{html.escape(st)}</span></div>
          <div class="lbl">generationHint (디폴트)</div>
          <div class="hint">{html.escape(hint)}</div>
          <div class="lbl">서버로 보낸 전체 프롬프트</div>
          <div class="prompt">{html.escape(prompt)}</div>
        </div>
      </div>""")

    page = f"""<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>withu 디폴트 프롬프트 테스트</title>
<style>
  body{{font-family:-apple-system,"Apple SD Gothic Neo",sans-serif;background:#f2f2f5;margin:0;padding:24px;color:#1c1c1e}}
  h1{{font-size:1.4rem;margin:0 0 4px}}
  .note{{color:#8a8a8e;font-size:.85rem;margin-bottom:20px}}
  .card{{display:flex;gap:18px;background:#fff;border:1px solid #e3e3e6;border-radius:14px;padding:16px;margin-bottom:14px}}
  .img img{{width:240px;height:240px;object-fit:contain;background:#fff;border-radius:10px;border:1px solid #eee}}
  .err{{width:240px;height:240px;display:flex;align-items:center;justify-content:center;background:#fff3f3;color:#c00;border-radius:10px;text-align:center;font-size:.8rem;padding:8px}}
  .meta{{flex:1;min-width:0}}
  .state{{font-size:1.15rem;font-weight:700;margin-bottom:10px}}
  .raw{{font-size:.8rem;color:#aaa;font-weight:400}}
  .lbl{{font-size:.72rem;color:#8a8a8e;text-transform:uppercase;letter-spacing:.04em;margin:10px 0 3px}}
  .hint{{font-size:.92rem;color:#3a3a3c}}
  .prompt{{font-family:ui-monospace,Menlo,monospace;font-size:.78rem;color:#555;background:#f7f7f8;border-radius:8px;padding:10px;white-space:pre-wrap;word-break:break-word;line-height:1.5}}
</style></head><body>
  <h1>withu 디폴트 프롬프트 테스트</h1>
  <div class="note">품질 {args.quality} · 스타일 {args.style} · baseIdentity: {html.escape(args.identity)}<br>
  ⚠️ 서버가 추가로 [Style/Content] 시스템 프롬프트로 감쌉니다 (cloudflare/withu-api/src/index.js). 아래는 클라가 보낸 프롬프트.</div>
  {''.join(cards)}
</body></html>"""
    out_html = os.path.join(args.out, "index.html")
    with open(out_html, "w", encoding="utf-8") as f:
        f.write(page)
    print(f"\n📄 {out_html}")
    try:
        subprocess.run(["open", out_html], check=False)
    except Exception:
        pass


if __name__ == "__main__":
    main()
