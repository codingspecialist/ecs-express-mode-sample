# ex01 — 테라폼 없이 직접 배포해보기

기본서버 1종(컨테이너 **2개**)과 인증서버 1종(컨테이너 **1개**)을
**AWS 콘솔과 CLI로 직접** 배포합니다.

> 이 실습의 목적은 "잘 된다"가 아니라 **"손이 많이 간다"는 걸 체감**하는 것입니다.
> 같은 작업을 [ex02-terraform](../ex02-terraform)에서는 `terraform apply` 한 줄로 끝냅니다.

> 🚦 **먼저 [ex00-local](../ex00-local)에서 로컬 실행을 확인**한 뒤 진행하세요.
> 로컬에서 `docker build`가 되는 걸 본 다음에 배포하면 문제 원인을 빨리 좁힐 수 있습니다.

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

- AWS 계정 (없으면 https://aws.amazon.com 에서 가입)
- Docker Desktop
- 리전: `ap-northeast-2` (서울)

> **AWS CLI 설치와 IAM 키 발급은 아래 STEP 0**에서 함께 진행합니다.

---

## STEP 0. AWS CLI 설치 + IAM 액세스 키 발급 (제일 먼저!)

ECS는 명령어(CLI)로 다루므로, **내 PC를 AWS 계정에 연결**하는 작업을 가장 먼저 합니다.
순서: ① CLI 설치 → ② IAM 키 발급 → ③ 연결(`aws configure`).

### ① AWS CLI 설치

**Windows** — PowerShell에서 명령 한 줄 (Windows 10/11 기본 winget):

```powershell
winget install Amazon.AWSCLI
```

> winget이 없거나 실패하면 설치 파일을 직접 받으세요: https://awscli.amazonaws.com/AWSCLIV2.msi
> **macOS**: `brew install awscli` / **Linux**: 공식 문서 https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

설치 후 **새 터미널**을 열어 확인:

```bash
aws --version      # aws-cli/2.x.x ... 가 나오면 성공
```

### ② IAM 액세스 키 발급 (AWS 콘솔)

액세스 키 = 내 PC가 AWS에 로그인하는 **아이디(Access Key ID) + 비밀번호(Secret Access Key)** 입니다.

1. AWS 콘솔 로그인 → 상단 검색창에 **IAM** 입력 → 이동
2. 왼쪽 **사용자(Users)** → **사용자 생성**
   - 사용자 이름: 예) `ecs-lecture`
   - **권한 설정** → "직접 정책 연결" → 아래 정책 체크
     - `AmazonECS_FullAccess`
     - `AmazonEC2ContainerRegistryFullAccess`
     - `ElasticLoadBalancingFullAccess`
     - `IAMFullAccess` (작업 실행 역할 생성에 필요)
     - `CloudWatchLogsFullAccess`
   - > 실습 편의상 넓게 줍니다. 빠르게 가려면 `AdministratorAccess` 하나로도 됩니다.
     > (실무에선 최소 권한이 원칙이지만, 이 강의의 주제는 권한 설계가 아닙니다.)
3. 생성된 사용자 클릭 → **보안 자격 증명(Security credentials)** 탭
   → **액세스 키 만들기** → 사용 사례 **CLI(Command Line Interface)** 선택 → 생성
4. **Access Key ID**와 **Secret Access Key**가 표시됩니다.
   - ⚠️ Secret은 **이 화면에서만** 보입니다. `.csv 다운로드` 또는 복사해서 안전한 곳에 보관하세요.

### ③ 내 PC를 AWS에 연결

```bash
aws configure
```

순서대로 입력:

```
AWS Access Key ID     : (②에서 받은 Access Key ID)
AWS Secret Access Key : (②에서 받은 Secret Access Key)
Default region name   : ap-northeast-2
Default output format : json
```

연결이 잘 됐는지 확인 (내 계정 ID가 나오면 성공):

```bash
aws sts get-caller-identity
```

> 출력의 `"Account"` 값이 본인 **12자리 계정 ID**입니다.
> 아래 STEP들에서 `<ACCOUNT_ID>`는 이 값으로 바꾸세요.

---

## STEP 1. ECR 저장소 생성 + 이미지 푸시 (CLI)

> 아래 명령은 **`ex01-manual/` 폴더 안에서** 실행합니다 (이미지 경로가 `../servers` 기준).

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

   > **실행 역할(ecsTaskExecutionRole) 안내**: 작업 정의에는 ECR pull·로그 권한을 가진
   > `ecsTaskExecutionRole`이 필요합니다. **콘솔로 만들면 없을 때 자동 생성**되지만,
   > 위 JSON을 CLI(`aws ecs register-task-definition`)로 등록하려면 이 역할이 **미리 있어야** 합니다.
   > 없으면: `aws iam create-role` + `AmazonECSTaskExecutionRolePolicy` 연결로 한 번 만들어 두세요.
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
