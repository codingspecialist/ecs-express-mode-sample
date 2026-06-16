# ex00 — 로컬에서 먼저 실행 & 테스트하기

AWS로 배포하기 **전에**, 내 PC에서 두 앱이 정상 동작하는지 확인합니다.
**여기서 되면** ex01(직접 배포) / ex02(테라폼 배포)로 넘어갑니다.

> "배포했는데 안 떠요"의 절반은 사실 앱 자체 문제입니다.
> 로컬에서 한 번 띄워보면 그 절반을 미리 걸러냅니다.

| 서버 | 코드 위치 | 로컬 포트(예시) |
|---|---|---|
| basic-server | [../servers/basic-server](../servers/basic-server) | 8080 |
| auth-server | [../servers/auth-server](../servers/auth-server) | 8081 |

> 두 앱 모두 기본 포트가 8080이라, 동시에 띄우려면 하나는 `PORT`로 옮깁니다.

---

## 방법 A. Node로 실행 (가장 빠름)

사전: Node.js 설치 확인 — `node --version` (없으면 https://nodejs.org)

### basic-server (터미널 1)

```bash
cd ../servers/basic-server
npm install
npm start              # http://localhost:8080 에서 실행
```

### auth-server (터미널 2 — 포트 8081로)

```bash
cd ../servers/auth-server
npm install
```

```bash
# macOS / Linux / Git Bash
PORT=8081 npm start
```

```powershell
# Windows PowerShell
$env:PORT=8081; npm start
```

### 테스트 (터미널 3, 또는 브라우저)

```bash
curl http://localhost:8080/                    # basic-server 인사 + hostname
curl http://localhost:8080/health              # {"status":"ok"}
curl http://localhost:8080/api/users
curl http://localhost:8081/health              # auth-server
curl http://localhost:8081/auth
curl "http://localhost:8081/auth/login?user=kim"
```

> Windows PowerShell의 `curl`은 동작이 달라 헷갈리면, **브라우저에서 주소를 직접** 열어도 됩니다.
> 예: `http://localhost:8080/`, `http://localhost:8081/auth/login?user=kim`

종료: 각 터미널에서 **Ctrl+C**

---

## 방법 B. Docker로 실행 (ex01/ex02에서 올릴 "그 이미지" 미리 확인)

ex01/ex02는 이 Dockerfile로 만든 이미지를 ECR에 올립니다.
**올리기 전에 로컬에서 이미지가 잘 뜨는지** 확인하는 단계입니다.

사전: Docker Desktop 실행 중 — `docker --version`

### basic-server (터미널 1)

```bash
cd ../servers/basic-server
docker build -t basic-server .
docker run --rm -p 8080:8080 basic-server      # 호스트 8080 → 컨테이너 8080
```

### auth-server (터미널 2)

```bash
cd ../servers/auth-server
docker build -t auth-server .
docker run --rm -p 8081:8080 auth-server       # 호스트 8081 → 컨테이너 8080
```

테스트는 **방법 A의 테스트와 동일**합니다.

종료: **Ctrl+C** (또는 `docker ps`로 확인 후 `docker stop <id>`)

> 여기서 Docker 이미지가 정상 동작하면, ex01/ex02에서 같은 이미지를 그대로 ECR에 푸시합니다.
> 즉 ex00의 `docker build`가 **ex01 STEP 1의 예행연습**입니다.

---

## 다음 단계

로컬에서 두 앱이 확인됐으면:

- ➡️ [ex01 — 테라폼 없이 직접 배포](../ex01-manual)
- ➡️ [ex02 — 테라폼으로 배포](../ex02-terraform)
