# AWS ECS Express Mode — 1시간 특강 실습 코드

컨테이너 배포 전 과정 자동화: **ECR → CI/CD → ECS Fargate → 오토스케일링**

push 한 번이면 빌드부터 배포, 헬스체크 실패 시 자동 롤백까지 전부 자동으로 동작하는 것을 체험합니다.

```
GitHub Repo → GitHub Actions → Amazon ECR → ECS Fargate → ALB + HTTPS
 (코드 push)   (워크플로)      (이미지 저장)  (컨테이너 실행)  (트래픽 라우팅)
```

## 앱 소개 (코드는 몰라도 됩니다)

포트 **8080**에서 동작하는 아주 작은 Node.js 서버입니다.

| 엔드포인트 | 용도 |
|---|---|
| `GET /` | 배포 확인 (버전·호스트명 표시) |
| `GET /health` | ECS 헬스체크용 (200 응답) |
| `GET /api/users` | 더미 API |
| `GET /stress` | CPU 부하 발생 (오토스케일링 실습용) |

## 사전 준비물

- AWS 계정 + IAM 액세스 키 (`AmazonEC2ContainerRegistryFullAccess`, `AmazonECS_FullAccess` 권한)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (`aws configure`로 키 등록)
- (STEP 6용, 선택) [hey](https://github.com/rakyll/hey) 부하 테스트 도구

---

## STEP 0. Fork & Clone + Secrets 등록

1. 이 저장소를 본인 계정으로 **Fork**
2. Fork한 저장소를 clone

```bash
git clone https://github.com/<본인계정>/ecs-express-mode-sample.git
cd ecs-express-mode-sample
```

3. GitHub Secrets 등록: Fork한 저장소에서
   **Settings → Secrets and variables → Actions → New repository secret**

| Secret 이름 | 값 |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM 액세스 키 ID |
| `AWS_SECRET_ACCESS_KEY` | IAM 시크릿 액세스 키 |
| `AWS_REGION` | `ap-northeast-2` |

---

## STEP 1. ECR 저장소 생성 + Docker 푸시

```bash
# 1. ECR 저장소 생성
aws ecr create-repository \
  --repository-name my-app \
  --region ap-northeast-2

# 2. Docker 로그인 (<account>는 12자리 AWS 계정 ID)
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin \
  <account>.dkr.ecr.ap-northeast-2.amazonaws.com

# 3. 이미지 빌드 & 푸시
docker build -t my-app .
docker tag my-app:latest <account>.dkr.ecr.ap-northeast-2.amazonaws.com/my-app:latest
docker push <account>.dkr.ecr.ap-northeast-2.amazonaws.com/my-app:latest
```

> 로그인 토큰은 12시간 유효합니다.

---

## STEP 2. GitHub Actions 워크플로 확인

[.github/workflows/deploy.yml](.github/workflows/deploy.yml)이 이미 들어 있습니다.

`main` 브랜치에 push하면: **AWS 인증 → ECR 로그인 → 이미지 빌드/푸시 → ECS 배포** 순으로 실행됩니다.

```bash
git commit --allow-empty -m "trigger deploy"
git push origin main
```

저장소의 **Actions 탭**에서 실행 과정을 확인하세요.

> 아직 ECS 서비스가 없으므로 이 시점에는 **ECR 푸시까지만** 실행되고 배포 단계는 자동으로 스킵됩니다. (정상입니다)

---

## STEP 3. ECS 서비스 생성 — 인프라 자동 생성

AWS 콘솔 → **ECS → 클러스터 생성** (`my-cluster`, Fargate) → **서비스 생성**:

- 이미지 URI: `<account>.dkr.ecr.ap-northeast-2.amazonaws.com/my-app:latest`
- 서비스 이름 / 컨테이너 이름: `my-app`
- 컨테이너 포트: `8080`
- 로드 밸런서: **Application Load Balancer 새로 생성**
- 헬스체크 경로: `/health`
- 배포 실패 감지: **Circuit Breaker + 롤백 활성화** ← STEP 5의 핵심
- 오토스케일링: 최소 1 / 최대 10, CPU 70% 기준 ← STEP 6의 핵심

서비스 하나 만들면 ALB, Target Group, Security Group, Task Definition, CloudWatch Logs가 **전부 자동 생성**됩니다.

> Fargate = 서버 관리 Zero. EC2 프로비저닝 불필요.

생성 후 ALB의 DNS 주소로 접속해 `{"message":"Hello, ECS Express Mode!"}`가 보이면 성공입니다.

> ⚠️ 워크플로의 `env:` 값(클러스터/서비스/컨테이너 이름)과 콘솔에서 만든 이름이 같아야 합니다. 다르게 만들었다면 [deploy.yml](.github/workflows/deploy.yml) 상단의 `env:`를 수정하세요.

---

## STEP 4. CloudWatch 로그 & 헬스체크 확인

```bash
# 로그 스트림 실시간 조회 (로그 그룹 이름은 ECS 콘솔의 Task Definition에서 확인)
aws logs tail /ecs/my-app --follow --since 5m
```

헬스체크 동작 방식:

| 항목 | 값 |
|---|---|
| 방식 | `GET /health` → HTTP 200이면 정상 |
| Interval | 30초 |
| Timeout | 5초 |
| Threshold | 3회 연속 실패 시 태스크 교체 |

---

## STEP 5. 의도적 장애 주입 → 자동 롤백 체험

1. [app.js](app.js)의 `/health` 핸들러에서 아래 줄의 **주석을 해제**합니다:

```js
// return res.status(500).json({ status: "broken" });
```

2. commit & push:

```bash
git add -A
git commit -m "🔥 장애 주입 실습"
git push origin main
```

3. ECS 콘솔에서 관찰: 새 태스크 시작 → 헬스체크 3회 실패 → **이전 버전으로 자동 롤백** (30~60초)
4. 실습이 끝나면 **주석을 다시 복구**하고 push합니다.

수동 롤백도 가능합니다:

```bash
aws ecs update-service --cluster my-cluster \
  --service my-app --task-definition my-app:<이전번호>
```

---

## STEP 6. 부하 테스트 & 오토스케일링

```bash
# hey 사용 (또는 ab -n 50000 -c 200 ...)
hey -n 50000 -c 200 http://<ALB주소>/stress
```

ECS 콘솔에서 실시간 관찰:

| 항목 | 값 |
|---|---|
| Scale-Out 트리거 | CPU 70% 초과 |
| Scale-Out 쿨다운 | 60초 |
| Scale-In 쿨다운 | 300초 (안정화) |
| Task 수 | 1 → 최대 10 |

부하를 멈추면 5분 뒤 Task 수가 다시 줄어듭니다.

---

## 로컬에서 먼저 실행해보기 (선택)

```bash
npm install
npm start
# 다른 터미널에서
curl http://localhost:8080/health
```

## 다음 단계 / 추천 학습

- **Secrets Manager** — DB 비밀번호 등 환경변수 안전 관리
- **Route 53 + ACM** — 커스텀 도메인 + SSL 인증서 자동 갱신
- **RDS + ECS** — Aurora Serverless v2 연동
- **Multi-Stage Build** — Dockerfile 최적화로 이미지 크기 절감
