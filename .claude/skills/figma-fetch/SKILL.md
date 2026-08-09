---
name: figma-fetch
description: >
  Figma 파일 링크와 access token 만 주면 그 파일의 프레임을 전부 PNG/SVG 로 렌더해 받고, 디자이너가 업로드한 원본
  비트맵(imageRef)까지 통째로 내려받는 스킬. 표준 라이브러리만 쓰는 python3 스크립트 하나라 pip 설치가 필요 없다.
  프레임 렌더(화면에 보이는 합성 결과)와 원본 이미지 fill(업로드된 픽셀 그대로)을 구분해서 받는 것이 핵심 —
  픽셀 정합이 중요한 자산은 반드시 후자를 써야 한다. 토큰은 스킬 안 `.env` 에서 읽고 로그·에러·매니페스트 어디에도
  찍지 않으며, 렌더 결과를 받는 S3 요청에는 토큰 헤더를 붙이지 않는다. 페이지·노드 단위 선별, 이름 충돌·한글 NFD·
  `/` 포함 레이어명 정규화, 429 재시도, 받은 것의 매니페스트 JSON 기록까지 포함. 트리거 — "Figma에서 받아줘",
  "피그마 에셋 다운로드", "Figma 프레임 전부 내려받아", "figma 링크 주면 이미지 가져와", "디자인 자산 동기화",
  "figma export", "figma asset fetch", "피그마 토큰으로 파일 읽어", "Figma API로 프레임 뽑아". 단순히 Figma 디자인을
  코드로 옮기는 작업(레이아웃 구현)은 이 스킬이 아니다 — 이건 파일에서 **자산을 꺼내오는** 도구다.
---

# figma-fetch — 링크 하나로 프레임·자산 전부 받기

`scripts/figma_fetch.py` 하나가 전부다. 표준 라이브러리만 쓰므로 macOS 기본 `python3` 로 바로 돈다.

## 처음 한 번

1. Figma → Settings → Security → **Personal access tokens** 에서 발급. 스코프는 `file_content:read`.
2. 토큰을 이 디렉터리의 `.env` 에 넣는다:

```bash
# .env  (gitignore 된다 — 커밋되지 않는다)
FIGMA_TOKEN=figd_xxxxxxxxxxxxxxxxxxxx
```

3. 확인:

```bash
git check-ignore -v .claude/skills/figma-fetch/.env   # 규칙이 출력되면 정상
```

`.env` 가 `??` 로 잡히면 **거기서 멈춘다.** 커밋하면 토큰이 공개된다.

## 쓰는 법

```bash
S=.claude/skills/figma-fetch/scripts/figma_fetch.py

# 뭐가 들어 있는지 먼저 본다 (아무것도 받지 않는다)
python3 $S "https://www.figma.com/design/KEY/title" --dry-run

# 전부 받는다
python3 $S "https://www.figma.com/design/KEY/title" --out design-out --scale 2

# 링크에 ?node-id= 가 붙어 있으면 그 노드만 받는다
python3 $S "https://www.figma.com/design/KEY/t?node-id=12-345"

# 특정 페이지만, 원본 비트맵까지
python3 $S "KEY" --pages "지도,아이콘" --image-fills
```

받은 뒤 `<out>/figma-manifest.json` 에 노드 id·이름·크기·경로가 남는다. 나중에 "이 PNG 가 어느 프레임에서 왔나"를
되짚을 수 있는 유일한 기록이다.

## 프레임 렌더 vs 원본 이미지 fill — 헷갈리면 자산이 망가진다

| | 무엇 | 언제 |
|---|---|---|
| 기본 (`/v1/images`) | Figma 가 **렌더한 합성 결과**. `--scale` 이 먹고, 효과·마스크·불투명도가 구워진다 | 화면 목업, 아이콘, 미리보기 |
| `--image-fills` | 디자이너가 **업로드한 원본 비트맵** 그대로. 스케일 개념 없음 | 원본 픽셀이 중요한 자산 |

픽셀 단위로 비교하거나 계측할 자산이라면 반드시 `--image-fills` 쪽이다. 렌더는 Figma 버전·플랫폼에 따라 미세하게
달라질 수 있어서 골든 비교의 기준으로 삼으면 안 된다.

## 이 레포에서 (pen-reveal)

정본 지도 10종을 Figma 에서 받아 `corpus/maps/<key>/{base,composed}.png` 배치로 채울 때 쓴다. 다만 **받은 뒤에
그냥 두면 안 된다** — 레포 규칙이 있다(README §코퍼스, `.gitignore` 머리말):

> PNG 에서 픽셀 단위로 나온 것은 ignore, 재서 얻은 스칼라(각도·비율·길이)만 커밋.

`corpus/maps/` 는 이미 gitignore 대상이라 받아도 커밋되지 않는다. 계측해서 얻은 숫자와 `corpus/manifest.json`
(어떤 리샘플러로·어떤 해상도에서·어느 구현으로 쟀는지)만 커밋한다. 지금 이 레포에는 그 manifest 가 없으므로,
자산을 받았다면 **manifest 를 같이 쓰는 것까지가 한 작업이다.**

## 주의할 것

**토큰을 명령줄에 쓰지 마라.** `--token` 은 있지만 쓰면 셸 히스토리와 `ps` 에 남는다. `.env` 를 써라.

**렌더 URL 은 곧 만료된다.** `/v1/images` 가 주는 S3 링크는 수명이 짧다. 스크립트가 받아 오는 즉시 디스크에
쓰는 이유다. URL 만 따로 보관했다가 나중에 받으면 실패한다.

**프레임이 비어 있으면 렌더가 `null` 로 온다.** 스크립트는 전체를 죽이지 않고 그 항목만 `failed` 에 적고 넘어간다.
끝에 못 받은 목록이 뜨고 종료 코드가 1 이 된다.

**`--scale` 은 0.01~4 가 Figma 상한이다.** SVG·PDF 에는 안 먹는다.

**큰 파일은 `--dry-run` 부터.** 전체 트리를 `depth=2` 로만 받으니 목록은 빠르다. 프레임이 수백 개면 렌더에
시간이 걸리므로 `--pages` 로 좁히는 게 낫다.

**429 가 뜨면** 스크립트가 `Retry-After` 를 보고 기다렸다 재시도한다(최대 4회). 그래도 계속 막히면
`--batch-size` 를 낮춘다(기본 20).

## 실패했을 때

| 증상 | 원인 |
|---|---|
| `403` | 토큰 만료·오타, 또는 스코프에 `file_content:read` 가 없다 |
| `404` | 파일 키가 틀렸거나, 내 계정이 그 파일에 접근 권한이 없다(비공개 팀 파일은 403 아닌 404 로 온다) |
| `400` | `node-id` 형식 문제. URL 의 `12-345` 는 API 에서 `12:345` 다 — 스크립트가 변환하지만 직접 넘길 땐 콜론으로 |
| 프레임 0개 | 최상위 프레임만 수집한다. 프레임이 그룹 안에 있으면 `--node-id` 로 직접 지정하라 |
