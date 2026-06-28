#!/usr/bin/env python3
"""
withu 인터랙티브 프롬프트 랩.

브라우저에서:
  - 캐릭터 설명 / 상태별 포즈(generationHint) / 움직임 힌트(animationFrame2Hint)를 직접 편집
  - 상태별 정적(frame 0) + 움직임(frame 1) 이미지를 개별 또는 전체 생성
  - 조립된 전체 프롬프트를 실시간으로 확인

정적 HTML 은 CORS 때문에 서버를 못 부르므로, 이 스크립트가 로컬 미니 서버를 띄워
페이지를 서빙하고 /api/generate 요청을 Cloudflare Worker 로 중계한다(SSL·UA·지역재시도 처리).

실행 (! 로 — 매 생성 = OpenAI 과금):
  ! cd ~/Desktop/withu && python3 tools/prompt_lab.py
브라우저가 자동으로 http://localhost:8765 를 연다. Ctrl+C 로 종료.
"""
import http.server, socketserver, json, re, os, base64, time, threading, webbrowser
import urllib.request, urllib.error
import prompt_test as P   # SSL_CTX, SERVER 재사용

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE_FILE = os.path.join(ROOT, "withu", "Character", "CharacterState.swift")
PORT = 8765

# 앱(단건 생성)의 흰배경 가드와 동일.
WHITE_BG = (". Solid clean WHITE background, no shadows, no gradients, no other elements behind the character. "
            "Never draw a checkerboard or transparency grid pattern — the background must be one flat solid white color.")
DEFAULT_IDENTITY = "round green sprout character with big friendly eyes"


def _cases(block):
    out = {}
    for m in re.finditer(r'case\s+\.(\w+)\s*:\s*return\s+"((?:[^"\\]|\\.)*)"', block):
        out[m.group(1)] = m.group(2)
    return out


def parse_states():
    src = open(STATE_FILE, encoding="utf-8").read()
    facing = re.findall(r"\.(\w+)", re.search(r"userFacing[^=]*=\s*\[(.*?)\]", src, re.S).group(1))
    pose = _cases(src[src.index("var generationHint"):src.index("var animationFrame2Hint")])
    anim = _cases(src[src.index("var animationFrame2Hint"):src.index("var symbolEmoji")])
    labels = _cases(src[src.index("var koreanShortLabel"):src.index("var caption")])
    return [{"name": s, "label": labels.get(s, s), "pose": pose.get(s, ""), "anim": anim.get(s, "")}
            for s in facing if s in pose]


def generate(prompt, quality, art_style, reference=None, region_retries=8):
    """Worker /generate 호출 → {image_base64, revised_prompt}. 지역차단 403 은 재시도."""
    body = {"prompt": prompt, "steps": 30, "width": 1024, "height": 1024,
            "quality": quality, "art_style": art_style, "style": "auto"}
    if reference:
        body["reference_image_base64"] = reference
    data = json.dumps(body).encode()
    for attempt in range(region_retries + 1):
        req = urllib.request.Request(P.SERVER + "/generate", data=data,
                                     headers={"Content-Type": "application/json",
                                              "X-Withu-Kind": "single",
                                              "User-Agent": "withu-prompt-lab/1.0"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=600, context=P.SSL_CTX) as r:
                out = json.loads(r.read())
            return {"image_base64": out.get("image_base64"), "revised_prompt": out.get("revised_prompt")}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="ignore")
            if e.code == 403 and "not supported" in detail and attempt < region_retries:
                time.sleep(1.5)
                continue
            return {"error": f"HTTP {e.code}: {detail[:300]}"}
        except Exception as e:
            return {"error": str(e)}
    return {"error": "지역차단 재시도 모두 실패"}


STATES = parse_states()

PAGE = r"""<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>withu 프롬프트 랩</title>
<style>
  body{font-family:-apple-system,"Apple SD Gothic Neo",sans-serif;background:#f2f2f5;margin:0;padding:20px;color:#1c1c1e}
  h1{font-size:1.3rem;margin:0 0 12px}
  .bar{position:sticky;top:0;background:#f2f2f5;padding:12px 0;z-index:10;border-bottom:1px solid #ddd;margin-bottom:16px}
  textarea,input,select{font:inherit;border:1px solid #ccc;border-radius:8px;padding:8px;width:100%;box-sizing:border-box}
  textarea{resize:vertical}
  .desc{min-height:54px}
  label{font-size:.8rem;color:#666;display:block;margin:8px 0 3px}
  button{font:inherit;font-weight:600;border:0;border-radius:9px;padding:8px 14px;background:#ff5e9a;color:#fff;cursor:pointer}
  button.sec{background:#e3e3e6;color:#1c1c1e}
  button:disabled{opacity:.4;cursor:default}
  .row{display:flex;gap:12px;align-items:center;flex-wrap:wrap}
  .card{background:#fff;border:1px solid #e3e3e6;border-radius:14px;padding:16px;margin-bottom:14px}
  .card h2{font-size:1.05rem;margin:0 0 10px}
  .raw{font-size:.78rem;color:#aaa;font-weight:400}
  .pair{display:flex;gap:16px;flex-wrap:wrap}
  .col{flex:1;min-width:280px}
  .col h3{font-size:.85rem;color:#666;margin:0 0 6px;text-transform:uppercase;letter-spacing:.03em}
  .imgbox{width:100%;aspect-ratio:1;background:#fafafa;border:1px solid #eee;border-radius:10px;display:flex;align-items:center;justify-content:center;overflow:hidden;margin-top:8px}
  .imgbox img{width:100%;height:100%;object-fit:contain}
  .imgbox .ph{color:#bbb;font-size:.85rem}
  .full{font-family:ui-monospace,Menlo,monospace;font-size:.72rem;color:#777;background:#f7f7f8;border-radius:8px;padding:8px;white-space:pre-wrap;word-break:break-word;margin-top:8px;line-height:1.5}
  .err{color:#c00}
  .spin{color:#ff5e9a;font-size:.85rem}
</style></head><body>
<h1>withu 프롬프트 랩</h1>
<div class="bar">
  <label>캐릭터 설명 (모든 상태 공통)</label>
  <textarea id="desc" class="desc">__DEFAULT_IDENTITY__</textarea>
  <div class="row" style="margin-top:10px">
    품질 <select id="quality"><option>low</option><option>medium</option><option>high</option></select>
    스타일 <select id="style"><option value="casual">Soft</option><option value="pixel">Pixel</option></select>
    <label style="display:inline;margin:0"><input type="checkbox" id="withAnim" style="width:auto"> 전체 생성 시 움직임도 함께</label>
    <button onclick="genAll()">전체 생성</button>
    <span id="globalStatus" class="spin"></span>
  </div>
</div>
<div id="cards"></div>

<script>
const STATES = __STATES_JSON__;
const WHITE_BG = __WHITE_BG_JSON__;
const frame0 = {};   // name -> b64 (움직임 reference)

const desc = () => document.getElementById('desc').value.trim();
const quality = () => document.getElementById('quality').value;
const style = () => document.getElementById('style').value;

function buildStatic(pose){ const d=desc(); return (d? d+', ':'') + pose + WHITE_BG; }
function buildAnim(pose, anim){ const d=desc(); return (d? d+', ':'') + pose + '. Animation frame 2 (for a 2-frame swap loop): ' + anim + WHITE_BG; }

function render(){
  const c = document.getElementById('cards'); c.innerHTML='';
  STATES.forEach((s,i)=>{
    const el = document.createElement('div'); el.className='card';
    el.innerHTML = `
      <h2>${s.label} <span class="raw">${s.name}</span></h2>
      <div class="pair">
        <div class="col">
          <h3>정적 (frame 0)</h3>
          <label>포즈 (generationHint)</label>
          <textarea id="pose${i}" rows="3" oninput="upd(${i})">${s.pose}</textarea>
          <div class="row" style="margin-top:8px">
            <button onclick="genStatic(${i})">정적 생성</button>
            <span id="st${i}" class="spin"></span>
          </div>
          <div class="imgbox" id="img0_${i}"><span class="ph">아직 없음</span></div>
          <div class="full" id="full0_${i}"></div>
        </div>
        <div class="col">
          <h3>움직임 (frame 1)</h3>
          <label>움직임 힌트 (animationFrame2Hint)</label>
          <textarea id="anim${i}" rows="3" oninput="upd(${i})">${s.anim}</textarea>
          <div class="row" style="margin-top:8px">
            <button class="sec" id="ab${i}" onclick="genAnim(${i})" disabled>움직임 생성 (정적 먼저)</button>
            <span id="at${i}" class="spin"></span>
          </div>
          <div class="imgbox" id="img1_${i}"><span class="ph">아직 없음</span></div>
          <div class="full" id="full1_${i}"></div>
        </div>
      </div>`;
    c.appendChild(el);
  });
  STATES.forEach((s,i)=>upd(i));
}

function upd(i){
  const pose=document.getElementById('pose'+i).value, anim=document.getElementById('anim'+i).value;
  document.getElementById('full0_'+i).textContent = buildStatic(pose);
  document.getElementById('full1_'+i).textContent = buildAnim(pose, anim);
}

async function callGen(prompt, reference){
  const r = await fetch('/api/generate', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({prompt, quality:quality(), art_style:style(), reference})});
  return r.json();
}

async function genStatic(i){
  const s=STATES[i], st=document.getElementById('st'+i);
  st.textContent='생성 중…';
  const res = await callGen(buildStatic(document.getElementById('pose'+i).value), null);
  if(res.image_base64){
    frame0[s.name]=res.image_base64;
    document.getElementById('img0_'+i).innerHTML = `<img src="data:image/png;base64,${res.image_base64}">`;
    document.getElementById('ab'+i).disabled=false;
    document.getElementById('ab'+i).textContent='움직임 생성';
    st.textContent='✅';
  } else { st.innerHTML = '<span class="err">❌ '+(res.error||'실패')+'</span>'; }
}

async function genAnim(i){
  const s=STATES[i], at=document.getElementById('at'+i);
  if(!frame0[s.name]){ at.innerHTML='<span class="err">정적 먼저</span>'; return; }
  at.textContent='생성 중…';
  const prompt = buildAnim(document.getElementById('pose'+i).value, document.getElementById('anim'+i).value);
  const res = await callGen(prompt, frame0[s.name]);
  if(res.image_base64){
    document.getElementById('img1_'+i).innerHTML = `<img src="data:image/png;base64,${res.image_base64}">`;
    at.textContent='✅';
  } else { at.innerHTML = '<span class="err">❌ '+(res.error||'실패')+'</span>'; }
}

async function genAll(){
  const gs=document.getElementById('globalStatus');
  const withAnim=document.getElementById('withAnim').checked;
  for(let i=0;i<STATES.length;i++){
    gs.textContent=`${i+1}/${STATES.length} ${STATES[i].label} 정적…`;
    await genStatic(i);
    if(withAnim){ gs.textContent=`${i+1}/${STATES.length} ${STATES[i].label} 움직임…`; await genAnim(i); }
  }
  gs.textContent='완료 ✅';
}

render();
</script></body></html>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        b = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            page = (PAGE.replace("__STATES_JSON__", json.dumps(STATES, ensure_ascii=False))
                        .replace("__WHITE_BG_JSON__", json.dumps(WHITE_BG))
                        .replace("__DEFAULT_IDENTITY__", DEFAULT_IDENTITY))
            self._send(200, page, "text/html")
        else:
            self._send(404, "not found", "text/plain")

    def do_POST(self):
        if self.path != "/api/generate":
            self._send(404, "{}"); return
        n = int(self.headers.get("Content-Length", 0))
        try:
            req = json.loads(self.rfile.read(n))
        except Exception:
            self._send(400, json.dumps({"error": "bad json"})); return
        label = (req.get("prompt", "")[:40]).replace("\n", " ")
        print(f"  → 생성: {label}…", flush=True)
        res = generate(req.get("prompt", ""), req.get("quality", "low"),
                       req.get("art_style", "casual"), req.get("reference"))
        print("    " + ("✅" if res.get("image_base64") else "❌ " + str(res.get("error"))[:80]), flush=True)
        self._send(200, json.dumps(res))


def main():
    print(f"상태 {len(STATES)}개 로드: {', '.join(s['name'] for s in STATES)}")
    print(f"브라우저 열기 → http://localhost:{PORT}   (Ctrl+C 종료)")
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", PORT), Handler)
    srv.daemon_threads = True
    threading.Timer(0.6, lambda: webbrowser.open(f"http://localhost:{PORT}")).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n종료")
        srv.shutdown()


if __name__ == "__main__":
    main()
