const express = require("express");
const os = require("os");

const app = express();
const PORT = process.env.PORT || 8080;

// 기본(모놀리식) 서버 — 실제 서비스 로직이 들어갈 자리
app.get("/", (req, res) => {
  res.json({
    server: "basic-server",
    message: "Hello from basic-server!",
    hostname: os.hostname(), // 어느 컨테이너가 응답했는지 (2개 중 분산 확인)
  });
});

app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

app.get("/api/users", (req, res) => {
  res.json([
    { id: 1, name: "kim" },
    { id: 2, name: "lee" },
  ]);
});

// 오토스케일링 실습용 CPU 부하
app.get("/stress", (req, res) => {
  let sum = 0;
  for (let i = 0; i < 5_000_000; i++) sum += Math.sqrt(i);
  res.json({ result: sum, hostname: os.hostname() });
});

app.listen(PORT, () => console.log(`INFO  basic-server started on :${PORT}`));
