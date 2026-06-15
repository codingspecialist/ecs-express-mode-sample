output "alb_url" {
  description = "브라우저로 접속할 주소"
  value       = "http://${aws_lb.main.dns_name}"
}

output "test_commands" {
  description = "동작 확인용 curl 명령"
  value = {
    basic = "curl http://${aws_lb.main.dns_name}/"
    users = "curl http://${aws_lb.main.dns_name}/api/users"
    auth  = "curl http://${aws_lb.main.dns_name}/auth/login?user=kim"
  }
}
