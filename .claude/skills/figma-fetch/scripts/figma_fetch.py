#!/usr/bin/env python3
"""Figma 파일 링크 하나로 프레임 렌더와 원본 이미지 fill 을 통째로 내려받는다.

표준 라이브러리만 쓴다 — macOS 기본 python3 로 pip 설치 없이 돈다.

    python3 figma_fetch.py <figma-url> --out corpus/maps --scale 2

토큰은 다음 순서로 찾는다:  --token  >  $FIGMA_TOKEN  >  스킬 디렉터리의 .env
토큰은 **어디에도 출력하지 않는다** — 로그·에러·매니페스트 전부.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

API = "https://api.figma.com"

# 스킬 루트 = 이 파일의 부모의 부모 (scripts/ 위)
SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Figma 가 "프레임"으로 취급할 만한 노드. INSTANCE 는 기본에서 뺀다 — 컴포넌트를
#   쓴 화면마다 중복으로 쏟아져 나온다. 필요하면 --include-types 로 넣는다.
DEFAULT_TYPES = ("FRAME", "COMPONENT", "COMPONENT_SET")

# /v1/images 는 서버에서 실제로 렌더를 돌리므로 한 번에 많이 넣으면 타임아웃 난다.
#   공식 상한이 문서에 없어서 보수적으로 잡는다(--batch-size 로 조정).
DEFAULT_BATCH = 20


# ─────────────────────────────────────────────────────────────────────────────
# 설정
# ─────────────────────────────────────────────────────────────────────────────


def load_dotenv(path: str) -> dict[str, str]:
    """KEY=VALUE 만 읽는 최소 파서. 없는 파일은 빈 dict."""
    out: dict[str, str] = {}
    if not os.path.isfile(path):
        return out
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            val = val.strip().strip("'\"")
            if val:
                out[key.strip()] = val
    return out


def resolve_token(cli_token: str | None, env: dict[str, str]) -> str:
    token = cli_token or os.environ.get("FIGMA_TOKEN") or env.get("FIGMA_TOKEN")
    if not token:
        die(
            "Figma 토큰이 없다.\n"
            f"  {os.path.join(SKILL_DIR, '.env')} 의 FIGMA_TOKEN= 뒤에 붙여넣거나,\n"
            "  FIGMA_TOKEN=... 환경변수로 주거나, --token 으로 넘긴다.\n"
            "  발급: Figma → Settings → Security → Personal access tokens"
        )
    return token.strip()


# ─────────────────────────────────────────────────────────────────────────────
# URL 파싱
# ─────────────────────────────────────────────────────────────────────────────

_URL_KEY = re.compile(r"/(?:file|design|proto|board)/([A-Za-z0-9]+)")


def parse_file_url(url: str) -> tuple[str, str | None]:
    """(file_key, node_id) 를 낸다. node_id 는 API 형식(`1:2`)으로 정규화한다.

    받아들이는 꼴:
        https://www.figma.com/design/KEY/title?node-id=12-345
        https://www.figma.com/file/KEY/title?node-id=12%3A345
        KEY                                     (키만 준 경우)
    """
    url = url.strip()
    if "/" not in url and "?" not in url:
        return url, None  # 키만 넘긴 경우

    match = _URL_KEY.search(url)
    if not match:
        die(f"Figma 파일 키를 못 찾았다: {url!r}\n  기대하는 꼴: figma.com/design/<KEY>/...")
    key = match.group(1)

    node = None
    query = urllib.parse.urlparse(url).query
    raw = urllib.parse.parse_qs(query).get("node-id", [None])[0]
    if raw:
        # URL 은 `12-345`, API 는 `12:345`. `%3A` 는 parse_qs 가 이미 풀어 준다.
        node = raw.replace("-", ":") if ":" not in raw else raw
    return key, node


# ─────────────────────────────────────────────────────────────────────────────
# HTTP
# ─────────────────────────────────────────────────────────────────────────────


class FigmaError(RuntimeError):
    pass


@dataclass
class Client:
    token: str
    retries: int = 4
    timeout: int = 120
    verbose: bool = False

    def _sleep(self, attempt: int, retry_after: str | None) -> float:
        if retry_after:
            try:
                return min(float(retry_after), 60.0)
            except ValueError:
                pass
        return min(2.0**attempt, 30.0)

    def get_json(self, path: str, params: dict[str, str] | None = None) -> dict:
        qs = f"?{urllib.parse.urlencode(params)}" if params else ""
        url = f"{API}{path}{qs}"
        req = urllib.request.Request(url, headers={"X-Figma-Token": self.token})

        for attempt in range(self.retries + 1):
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    return json.loads(resp.read().decode("utf-8"))
            except urllib.error.HTTPError as exc:
                body = _read_err(exc)
                # 429(레이트리밋)·5xx 는 재시도, 나머지는 즉시 실패.
                if exc.code in (429, 500, 502, 503, 504) and attempt < self.retries:
                    wait = self._sleep(attempt, exc.headers.get("Retry-After"))
                    log(f"  {exc.code} — {wait:.0f}s 뒤 재시도 ({attempt + 1}/{self.retries})")
                    time.sleep(wait)
                    continue
                raise FigmaError(_explain(exc.code, body, path)) from None
            except (urllib.error.URLError, TimeoutError) as exc:
                if attempt < self.retries:
                    wait = self._sleep(attempt, None)
                    log(f"  네트워크 오류({exc}) — {wait:.0f}s 뒤 재시도")
                    time.sleep(wait)
                    continue
                raise FigmaError(f"네트워크 실패: {exc}") from None
        raise FigmaError("재시도 소진")

    def download(self, url: str, dest: str) -> int:
        """S3 등 외부 URL 로 내려받는다.

        ⚠️ 여기엔 **토큰 헤더를 붙이지 않는다.** 렌더 결과는 서명된 외부 URL 이고,
           거기에 Figma 토큰을 실어 보내면 제3자 호스트에 자격증명을 흘리는 셈이다.
        """
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        req = urllib.request.Request(url, headers={"User-Agent": "figma-fetch/1.0"})
        for attempt in range(self.retries + 1):
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    data = resp.read()
                with open(dest, "wb") as fh:
                    fh.write(data)
                return len(data)
            except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
                if attempt < self.retries:
                    time.sleep(min(2.0**attempt, 20.0))
                    continue
                raise FigmaError(f"내려받기 실패 {os.path.basename(dest)}: {exc}") from None
        return 0


def _read_err(exc: urllib.error.HTTPError) -> str:
    try:
        return exc.read().decode("utf-8", "replace")[:400]
    except Exception:  # noqa: BLE001 — 에러 읽다 또 터지면 그냥 포기
        return ""


def _explain(code: int, body: str, path: str) -> str:
    hints = {
        403: "토큰이 없거나·만료됐거나·이 파일에 권한이 없다. 스코프에 `file_content:read` 가 필요하다.",
        404: "파일 키가 틀렸거나 접근 권한이 없다(비공개 팀 파일은 404 로 온다).",
        400: "요청 파라미터가 잘못됐다 — node-id 형식(`1:2`)을 확인하라.",
        429: "레이트리밋. 잠시 뒤 다시 돌리거나 --batch-size 를 줄여라.",
    }
    tip = hints.get(code, "")
    return f"Figma API {code} ({path})" + (f"\n  {tip}" if tip else "") + (f"\n  {body}" if body else "")


# ─────────────────────────────────────────────────────────────────────────────
# 트리 훑기
# ─────────────────────────────────────────────────────────────────────────────


@dataclass
class Frame:
    node_id: str
    name: str
    page: str
    type: str
    width: float | None = None
    height: float | None = None
    path: str = ""
    bytes: int = 0


def collect(document: dict, types: tuple[str, ...], pages: list[str] | None) -> list[Frame]:
    """CANVAS(페이지) 아래에서 원하는 타입의 노드를 모은다.

    최상위 프레임만 본다 — 프레임 안의 프레임까지 파고들면 같은 그림이 겹쳐 나온다.
    """
    found: list[Frame] = []
    for canvas in document.get("children", []):
        if canvas.get("type") != "CANVAS":
            continue
        page = canvas.get("name", "page")
        if pages and page not in pages:
            continue
        for node in canvas.get("children", []):
            if node.get("type") in types:
                box = node.get("absoluteBoundingBox") or {}
                found.append(
                    Frame(
                        node_id=node["id"],
                        name=node.get("name", node["id"]),
                        page=page,
                        type=node.get("type", "?"),
                        width=box.get("width"),
                        height=box.get("height"),
                    )
                )
    return found


def collect_from_nodes(payload: dict, types: tuple[str, ...]) -> list[Frame]:
    """`--node-id` 로 특정 노드만 받았을 때. 그 노드 자신을 프레임으로 본다."""
    found: list[Frame] = []
    for node_id, wrap in (payload.get("nodes") or {}).items():
        node = (wrap or {}).get("document")
        if not node:
            continue
        if types and node.get("type") not in types:
            log(f"  ! {node_id} 는 {node.get('type')} 라 기본 필터 밖이다 — 그래도 받는다")
        box = node.get("absoluteBoundingBox") or {}
        found.append(
            Frame(
                node_id=node_id,
                name=node.get("name", node_id),
                page="",
                type=node.get("type", "?"),
                width=box.get("width"),
                height=box.get("height"),
            )
        )
    return found


# ─────────────────────────────────────────────────────────────────────────────
# 파일명
# ─────────────────────────────────────────────────────────────────────────────

_UNSAFE = re.compile(r'[/\\:*?"<>|\x00-\x1f]')
_SPACE = re.compile(r"\s+")


def safe_name(raw: str, fallback: str) -> str:
    """Figma 레이어 이름을 파일명으로 쓸 수 있게 만든다.

    실무에서 사고 나는 자리를 전부 막는다:
      · `/` 가 든 이름(`icon/24/close`)이 디렉터리를 만들어 버리는 것 → `-` 로 바꾼다
      · macOS 가 한글을 NFD 로 쪼개 `git status` 가 깨지는 것 → NFC 로 고정
      · 앞뒤 공백·점(`.`)으로 숨김파일이 되는 것
      · 이름이 비었거나 구분자뿐일 때 → 노드 id 로 대체
        (이모지만 있는 이름은 그대로 둔다 — macOS·git 둘 다 문제없다)
      · 255바이트 상한(파일명 길이는 바이트 기준이다)
    """
    name = unicodedata.normalize("NFC", raw)
    name = _UNSAFE.sub("-", name)
    name = _SPACE.sub(" ", name).strip(" .")
    if not name or not name.strip("-_ "):
        return fallback
    while len(name.encode("utf-8")) > 200:
        name = name[:-1]
    return name or fallback


def dedupe(names: list[str]) -> list[str]:
    """같은 이름이 여러 개면 뒤에 -2, -3 을 붙인다(대소문자 무시 — macOS 기본 FS)."""
    seen: dict[str, int] = {}
    out: list[str] = []
    for name in names:
        key = name.lower()
        seen[key] = seen.get(key, 0) + 1
        out.append(name if seen[key] == 1 else f"{name}-{seen[key]}")
    return out


# ─────────────────────────────────────────────────────────────────────────────
# 본체
# ─────────────────────────────────────────────────────────────────────────────


@dataclass
class Stats:
    rendered: int = 0
    fills: int = 0
    failed: list[str] = field(default_factory=list)


def render(client: Client, key: str, frames: list[Frame], args, stats: Stats) -> None:
    params_base = {"format": args.format}
    if args.format != "svg":
        params_base["scale"] = str(args.scale)
    if args.absolute_bounds:
        params_base["use_absolute_bounds"] = "true"

    for start in range(0, len(frames), args.batch_size):
        batch = frames[start : start + args.batch_size]
        params = dict(params_base, ids=",".join(f.node_id for f in batch))
        log(f"렌더 {start + 1}–{start + len(batch)} / {len(frames)}")
        payload = client.get_json(f"/v1/images/{key}", params)
        if payload.get("err"):
            raise FigmaError(f"렌더 실패: {payload['err']}")

        urls = payload.get("images") or {}
        for frame in batch:
            url = urls.get(frame.node_id)
            if not url:
                # 빈 프레임이거나 렌더 불가. 전체를 죽이지 말고 기록만 남긴다.
                stats.failed.append(f"{frame.page}/{frame.name} ({frame.node_id})")
                log(f"  ! 렌더 안 나옴: {frame.name}")
                continue
            frame.bytes = client.download(url, frame.path)
            stats.rendered += 1
            log(f"  ✓ {os.path.relpath(frame.path)} ({frame.bytes // 1024}KB)")


def collect_image_refs(node: dict) -> set[str]:
    """서브트리에서 실제로 쓰인 imageRef 만 긁는다(중첩 깊이 무제한)."""
    refs: set[str] = set()
    stack = [node]
    while stack:
        cur = stack.pop()
        for fill in cur.get("fills") or []:
            if fill.get("type") == "IMAGE" and fill.get("imageRef"):
                refs.add(fill["imageRef"])
        stack.extend(cur.get("children") or [])
    return refs


def fetch_fills(
    client: Client, key: str, out_dir: str, stats: Stats, only: set[str] | None
) -> list[dict]:
    """디자이너가 넣은 **원본 비트맵**(imageRef)을 그대로 받는다.

    프레임 렌더와 다른 것이다 — 렌더는 화면에 보이는 합성 결과이고, 이쪽은 업로드된
    원본 픽셀이다. 지도 PNG 처럼 원본이 필요한 경우엔 이쪽을 써야 한다.

    ⚠️ `/v1/files/:key/images` 는 **파일 전체**의 fill 을 준다 — 내가 고른 프레임이
       쓰는 것만 주지 않는다. 그래서 `only` 로 걸러 낸다. 안 거르면 디자인 파일
       하나에서 수백 장·수백 MB 가 딸려 온다(실제로 561장 241MB 를 받은 적 있다).
    """
    payload = client.get_json(f"/v1/files/{key}/images")
    images = ((payload.get("meta") or {}).get("images")) or {}
    if only is not None:
        total = len(images)
        images = {ref: url for ref, url in images.items() if ref in only}
        log(f"원본 이미지 fill — 파일 전체 {total}개 중 고른 프레임이 쓰는 {len(images)}개만")
    if not images:
        log("원본 이미지 fill 없음 (고른 프레임이 비트맵을 안 쓴다 — 전부 벡터일 수 있다)")
        return []

    log(f"원본 이미지 fill {len(images)}개")
    records = []
    for ref, url in sorted(images.items()):
        if not url:
            continue
        dest = os.path.join(out_dir, "_images", f"{ref}.png")
        try:
            size = client.download(url, dest)
        except FigmaError as exc:
            stats.failed.append(f"imageRef {ref}: {exc}")
            continue
        stats.fills += 1
        records.append({"imageRef": ref, "path": os.path.relpath(dest), "bytes": size})
        log(f"  ✓ _images/{ref}.png ({size // 1024}KB)")
    return records


def main() -> int:
    env = load_dotenv(os.path.join(SKILL_DIR, ".env"))

    ap = argparse.ArgumentParser(
        prog="figma_fetch.py",
        description="Figma 파일의 프레임과 asset 을 통째로 내려받는다.",
    )
    ap.add_argument("url", nargs="?", default=env.get("FIGMA_FILE_URL"),
                    help="Figma 파일 링크 또는 파일 키 (.env 의 FIGMA_FILE_URL 로 대체 가능)")
    ap.add_argument("--token", help="Personal access token (권장하지 않음 — .env 를 써라)")
    ap.add_argument("--out", default=env.get("FIGMA_OUT_DIR") or "figma-out",
                    help="받을 위치 (기본: figma-out)")
    ap.add_argument("--format", default="png", choices=("png", "jpg", "svg", "pdf"))
    ap.add_argument("--scale", type=float, default=2.0, help="0.01–4 (svg·pdf 에는 무시)")
    ap.add_argument("--node-id", help="이 노드만. URL 의 ?node-id= 를 덮어쓴다")
    ap.add_argument("--pages", help="이 페이지들만 (쉼표 구분, 이름 정확히 일치)")
    ap.add_argument("--include-types", default=",".join(DEFAULT_TYPES),
                    help=f"수집할 노드 타입 (기본: {','.join(DEFAULT_TYPES)})")
    ap.add_argument("--image-fills", action="store_true",
                    help="고른 프레임이 실제로 쓰는 원본 비트맵(imageRef)도 받는다")
    ap.add_argument("--all-image-fills", action="store_true",
                    help="파일 **전체**의 원본 비트맵을 받는다 (수백 MB 가 될 수 있다)")
    ap.add_argument("--absolute-bounds", action="store_true",
                    help="그림자·외곽선이 프레임 밖으로 삐져나올 때 잘리지 않게 한다")
    ap.add_argument("--flat", action="store_true", help="페이지별 하위 폴더를 만들지 않는다")
    ap.add_argument("--batch-size", type=int, default=DEFAULT_BATCH)
    ap.add_argument("--dry-run", action="store_true", help="목록만 보고 받지 않는다")
    args = ap.parse_args()

    if not args.url:
        die("Figma 링크를 인자로 주거나 .env 의 FIGMA_FILE_URL 을 채워라.")
    if not 0.01 <= args.scale <= 4:
        die("--scale 은 0.01 에서 4 사이여야 한다 (Figma 제한).")

    key, url_node = parse_file_url(args.url)
    node_id = args.node_id or url_node
    types = tuple(t.strip().upper() for t in args.include_types.split(",") if t.strip())
    pages = [p.strip() for p in args.pages.split(",")] if args.pages else None

    token = resolve_token(args.token, env)
    client = Client(token=token)

    log(f"파일 {key}" + (f" · 노드 {node_id}" if node_id else ""))

    # imageRef 를 프레임 단위로 좁히려면 **깊이 제한 없는** 트리가 필요하다.
    scoped: list[dict] = []

    if node_id:
        payload = client.get_json(f"/v1/files/{key}/nodes", {"ids": node_id})
        file_name = payload.get("name", key)
        frames = collect_from_nodes(payload, types)
        last_modified = payload.get("lastModified", "")
        scoped = [w["document"] for w in (payload.get("nodes") or {}).values() if w and w.get("document")]
    else:
        # depth=2 면 페이지와 그 바로 아래 최상위 프레임까지만 온다. 큰 파일에서
        #   전체 트리를 받으면 수십 MB 라 느리고, 우리는 최상위만 필요하다.
        payload = client.get_json(f"/v1/files/{key}", {"depth": "2"})
        file_name = payload.get("name", key)
        last_modified = payload.get("lastModified", "")
        frames = collect(payload.get("document", {}), types, pages)

    if not frames:
        die("받을 프레임이 없다. --include-types 나 --pages 를 확인하라.")

    log(f"“{file_name}” — 프레임 {len(frames)}개")

    # 경로 확정 (중복 이름 처리 포함)
    ext = args.format
    base_names = dedupe([safe_name(f.name, f.node_id.replace(":", "-")) for f in frames])
    out_root = os.path.abspath(args.out)
    for frame, base in zip(frames, base_names):
        sub = "" if (args.flat or not frame.page) else safe_name(frame.page, "page")
        frame.path = os.path.join(out_root, sub, f"{base}.{ext}")

    if args.dry_run:
        for frame in frames:
            dim = f"{frame.width:.0f}×{frame.height:.0f}" if frame.width else "?"
            log(f"  [{frame.type}] {frame.page}/{frame.name}  {dim}  → {os.path.relpath(frame.path)}")
        log("\n--dry-run 이라 받지 않았다.")
        return 0

    stats = Stats()
    render(client, key, frames, args, stats)

    fills: list[dict] = []
    if args.image_fills or args.all_image_fills:
        only: set[str] | None = None
        if not args.all_image_fills:
            if not scoped:
                # 파일 전체 모드는 depth=2 로 받아 중첩 fill 을 못 본다. 다시 깊게 받는다.
                log("imageRef 범위를 좁히려고 전체 트리를 다시 받는다 (큰 파일이면 느리다)")
                deep = client.get_json(f"/v1/files/{key}")
                scoped = [deep.get("document", {})]
            only = set()
            for root in scoped:
                only |= collect_image_refs(root)
        fills = fetch_fills(client, key, out_root, stats, only)

    manifest = {
        "fileKey": key,
        "fileName": file_name,
        "lastModified": last_modified,
        "fetchedWith": {"format": args.format, "scale": args.scale,
                        "absoluteBounds": args.absolute_bounds},
        "frames": [
            {"nodeId": f.node_id, "name": f.name, "page": f.page, "type": f.type,
             "width": f.width, "height": f.height,
             "path": os.path.relpath(f.path, out_root), "bytes": f.bytes}
            for f in frames if f.bytes
        ],
        "imageFills": fills,
        "failed": stats.failed,
    }
    # ⚠️ 매니페스트에 토큰을 절대 넣지 않는다. 위 dict 에 토큰이 없는지 확인할 것.
    manifest_path = os.path.join(out_root, "figma-manifest.json")
    os.makedirs(out_root, exist_ok=True)
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)

    log(f"\n프레임 {stats.rendered}개" + (f" · 원본 이미지 {stats.fills}개" if args.image_fills else ""))
    log(f"매니페스트 {os.path.relpath(manifest_path)}")
    if stats.failed:
        log(f"\n못 받은 것 {len(stats.failed)}개:")
        for item in stats.failed:
            log(f"  - {item}")
        return 1
    return 0


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def die(msg: str) -> None:
    log(f"error: {msg}")
    raise SystemExit(2)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except FigmaError as exc:
        die(str(exc))
    except KeyboardInterrupt:
        die("중단됨")
