# ex01 — 테라폼 없이 직접 배포해보기

기본서버 1종(컨테이너 **2개**)과 인증서버 1종(컨테이너 **1개**)을
**AWS 콘솔과 CLI로 직접** 배포합니다.

> 이 실습의 목적은 "잘 된다"가 아니라 **"손이 많이 간다"는 걸 체감**하는 것입니다.
> 같은 작업을 [ex02-terraform](../ex02-terraform)에서는 `terraform apply` 한 줄로 끝냅니다.

## 완성 그림

```
                          ┌─────────────────────────────┐
   인터넷 ──▶  ALB (80)   │  /auth*  ──▶  auth-server  ×1 │
                          │  그 외   ──▶  basic-server ×2 │
                          └─────────────────────────────┘
```

| 서비스 | 이미지 | 컨테이너 수 | ALB 경로 |
|---|---|---|---|
| basic-server | `basic-server` | 2 (오토스케일링 1~10) | 기본(default) |
| auth-server | `auth-server` | 1 | `/auth*` |

## 사전 준비물

- AWS 계정 + IAM 액세스 키 (`aws configure` 완료)
- Docker Desktop, AWS CLI v2
- 리전: `ap-northeast-2` (서울)

아래 명령에서 `<ACCOUNT_ID>`는 본인 12자리 AWS 계정 ID로 바꾸세요.
(`aws sts get-caller-identity --query Account --output text`로 확인)

---

## STEP 1. ECR 저장소 생성 + 이미지 푸시 (CLI)

서버가 2종이므로 **저장소도 2개** 만듭니다.

```bash
# 저장소 2개 생성
aws ecr create-repository --repository-name basic-server --region ap-northeast-2
aws ecr create-repository --repository-name auth-server  --region ap-northeast-2

# Docker 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin \
  <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com

# basic-server 빌드 & 푸시 (앱 코드는 ../servers 에 있습니다)
docker build -t basic-server ../servers/basic-server
docker tag basic-server:latest <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/basic-server:latest
docker push <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/basic-server:latest

# auth-server 빌드 & 푸시
docker build -t auth-server ../servers/auth-server
docker tag auth-server:latest <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/auth-server:latest
docker push <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/auth-server:latest
```

> 벌써 같은 작업을 **2번** 반복했습니다. 서버가 늘수록 이만큼 더 반복됩니다.

---

## STEP 2. 클러스터 & 로그 그룹 생성 (콘솔)

1. **CloudWatch → 로그 그룹**에서 `/ecs/basic-server`, `/ecs/auth-server` 2개 생성
2. **ECS → 클러스터 생성**: 이름 `my-cluster`, 인프라 **AWS Fargate**

---

## STEP 3. basic-server 서비스 생성 (콘솔) — 컨테이너 2개

1. **ECS → 작업 정의(Task Definition) 생성**
   - 시작 유형: Fargate, CPU 0.25 vCPU / 메모리 0.5GB
   - 컨테이너 이름 `basic-server`, 이미지 URI = STEP 1에서 푸시한 basic-server URI
   - 포트 `8080`
   - (참고) JSON으로 만들고 싶으면 [taskdef/basic-server.json](taskdef/basic-server.json) 사용
2. **클러스터 → 서비스 생성**
   - 작업 정의: `basic-server`
   - **원하는 작업 수: `2`** ← 동일 컨테이너 2개
   - 로드 밸런서: **Application Load Balancer 새로 생성** (`my-alb`)
   - 리스너 포트 80 → 대상 그룹 `basic-tg`, **헬스체크 경로 `/health`**
   - 배포 실패 시 롤백(Circuit Breaker) 켜기
3. **오토스케일링**: 최소 1 / 최대 10, 정책 = 평균 CPU **70%**

---

## STEP 4. auth-server 서비스 생성 (콘솔) — 같은 ALB에 경로 추가

1. **작업 정의 생성**: 컨테이너 `auth-server`, 이미지 = auth-server URI, 포트 8080
   ([taskdef/auth-server.json](taskdef/auth-server.json))
2. **서비스 생성**
   - 원하는 작업 수: `1`
   - 로드 밸런서: STEP 3에서 만든 **`my-alb` 재사용**
   - 대상 그룹 `auth-tg` 새로 생성, 헬스체크 경로 `/health`
3. **ALB 리스너 규칙 추가** (EC2 → 로드 밸런서 → 리스너 → 규칙 관리)
   - 조건: 경로 `/auth*` → 대상 그룹 `auth-tg` 로 전달 (우선순위 10)
   - 기본 규칙은 그대로 `basic-tg`

> 여기서도 **서비스 생성을 처음부터 다시** 했습니다. 서버 종류만큼 반복됩니다.

---

## STEP 5. 동작 확인

ALB DNS 주소(`EC2 → 로드 밸런서`에서 확인)로 접속:

```bash
ALB=<my-alb DNS 주소>

curl http://$ALB/                 # basic-server (새로고침하면 hostname이 2개 컨테이너로 번갈아 나옴)
curl http://$ALB/api/users        # basic-server
curl http://$ALB/auth             # auth-server
curl "http://$ALB/auth/login?user=kim"   # auth-server
```

부하 테스트로 오토스케일링 확인:

```bash
hey -n 50000 -c 200 http://$ALB/stress   # basic-server Task가 2 → 늘어남
```

---

## STEP 6. 정리(삭제) — 과금 방지

직접 만든 만큼 **직접 하나씩 지워야** 합니다. 순서도 신경 써야 합니다.

1. ECS 서비스 2개 삭제 (basic, auth)
2. ALB + 리스너 + 대상 그룹 2개 삭제
3. ECS 클러스터 삭제
4. ECR 저장소 2개 삭제
5. CloudWatch 로그 그룹 2개 삭제
6. (만들었다면) 보안 그룹 삭제

> 지우는 것도 이만큼 번거롭습니다. ex02에서는 `terraform destroy` 한 줄입니다.

---

## 이 실습에서 느낄 점

- 서버가 **2종**이 되니 거의 모든 단계를 **2번씩** 반복했습니다.
- 만들고 → 확인하고 → **지우는 것까지** 전부 수작업입니다.
- 사람이 클릭하므로 **재현이 어렵고 실수가 생깁니다.**

➡️ 다음: [ex02-terraform](../ex02-terraform) — **같은 결과를 코드 한 벌 + 명령 한 줄로**.
