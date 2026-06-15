# ex02 — 테라폼으로 배포하기

[ex01](../ex01-manual)에서 콘솔로 클릭하고 CLI로 반복했던 **모든 인프라**를
Terraform 코드 한 벌([main.tf](main.tf))로 정의하고 **명령 한 줄**로 배포합니다.

결과물은 ex01과 **완전히 동일**합니다: 기본서버 2개 + 인증서버 1개 + ALB + 오토스케일링.

## Terraform이 만드는 것 (main.tf 한 파일에 전부)

```
IAM 실행역할  ·  ECS 클러스터  ·  CloudWatch 로그그룹 ×2  ·  보안그룹 ×2
ALB  ·  대상그룹 ×2  ·  리스너 + /auth* 라우팅 규칙
작업정의 ×2  ·  ECS 서비스 ×2  ·  오토스케일링(CPU 70%)
```

ex01에서 손으로 하던 STEP 2~6이 전부 이 안에 들어 있습니다.

## 사전 준비물

- AWS 계정 + IAM 액세스 키 (`aws configure` 완료)
- Docker Desktop, AWS CLI v2
- **Terraform** 설치 — https://developer.hashicorp.com/terraform/install
- 리전: `ap-northeast-2`

---

## STEP 1. ECR 저장소 생성 + 이미지 푸시

> 이미지 빌드/푸시는 Terraform이 하지 않습니다(이미지는 ECS 밖의 일).
> ex01 STEP 1과 동일합니다. `<ACCOUNT_ID>`는 본인 계정 ID로 바꾸세요.

```bash
aws ecr create-repository --repository-name basic-server --region ap-northeast-2
aws ecr create-repository --repository-name auth-server  --region ap-northeast-2

aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin \
  <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com

docker build -t basic-server ../servers/basic-server
docker tag basic-server:latest <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/basic-server:latest
docker push <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/basic-server:latest

docker build -t auth-server ../servers/auth-server
docker tag auth-server:latest <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/auth-server:latest
docker push <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/auth-server:latest
```

---

## STEP 2. 인프라 배포 — 명령 한 줄

```bash
cd ex02-terraform

terraform init      # 1. AWS provider 다운로드 (최초 1회)
terraform plan      # 2. 무엇이 만들어질지 미리보기 (선택)
terraform apply     # 3. 실제 생성 → yes 입력
```

`apply`가 끝나면 접속 주소가 출력됩니다:

```
alb_url = "http://ecs-demo-alb-xxxxx.ap-northeast-2.elb.amazonaws.com"
```

> ex01에서 5~6개 STEP, 수십 번의 클릭으로 하던 일이 **이 한 번**에 끝납니다.

---

## STEP 3. 동작 확인

```bash
ALB=$(terraform output -raw alb_url)   # 또는 위 alb_url 값 복사

curl $ALB/                  # basic-server (새로고침 시 hostname 2개 번갈아)
curl $ALB/api/users         # basic-server
curl $ALB/auth              # auth-server  (/auth* 라우팅)
curl "$ALB/auth/login?user=kim"

# 오토스케일링: 부하를 주면 basic 서비스 Task가 2 → 늘어남
hey -n 50000 -c 200 $ALB/stress
```

컨테이너 수를 바꾸고 싶으면 변수만 바꿔서 다시 apply:

```bash
terraform apply -var="basic_desired_count=4"
```

> 코드 한 줄(숫자)만 바꾸면 인프라가 따라옵니다. 이게 IaC의 핵심입니다.

---

## STEP 4. 정리(삭제) — 명령 한 줄

```bash
terraform destroy   # Terraform이 만든 것 전부 삭제 → yes
```

> ex01에서 순서 신경 쓰며 하나씩 지우던 걸, 여기선 한 줄이 알아서 역순으로 지웁니다.
> (단, STEP 1에서 만든 ECR 저장소는 Terraform 관리 밖이라 따로 삭제:
> `aws ecr delete-repository --repository-name basic-server --force` / auth-server)

---

## ex01 vs ex02 한눈에

| | ex01 (직접) | ex02 (테라폼) |
|---|---|---|
| 인프라 생성 | 콘솔 클릭 + CLI 반복 (STEP 2~6) | `terraform apply` |
| 서버 1종 추가 | 모든 단계 다시 반복 | 리소스 블록 복붙 |
| 컨테이너 수 변경 | 콘솔에서 수동 수정 | 변수 숫자 1개 |
| 삭제 | 순서대로 하나씩 | `terraform destroy` |
| 재현성 | 사람마다 다름 | 코드가 보장 |

➡️ 규모가 커질수록 ex02의 이점이 커집니다. 이것이 **기존 강의(콘솔 본편)에서 한 단계 나아간 자동화**입니다.
