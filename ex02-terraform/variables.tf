variable "aws_region" {
  description = "배포 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "ecs-demo"
}

variable "image_tag" {
  description = "ECR 이미지 태그 (STEP 1에서 푸시한 태그)"
  type        = string
  default     = "latest"
}

variable "basic_desired_count" {
  description = "기본서버 컨테이너 수"
  type        = number
  default     = 2
}

variable "auth_desired_count" {
  description = "인증서버 컨테이너 수"
  type        = number
  default     = 1
}
