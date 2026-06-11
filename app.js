const express = require("express");
const os = require("os");

const app = express();
const PORT = process.env.PORT || 8080;
const VERSION = process.env.APP_VERSION || "1.0.0";

// 배포 확인용 메인 페이지 — 어떤 버전/컨테이너가 응답하는지 보여줌
app.get("/", (req, res) => {
  res.json({
    message: "Hello, ECS Express Mode!",
    version: VERSION,
    hostname: os.hostname(),
  });
});

// ECS 헬스체크 엔드포인트
app.get("/health", (req, res) => {
  // 🔥 STEP 5 실습: 아래 한 줄의 주석을 풀고 push 하면 헬스체크가 실패합니다
  // return res.status(500).json({ status: "broken" });

  res.json({ status: "ok" });
});

// 더미 API
app.get("/api/users", (req, res) => {
  res.json([
    { id: 1, name: "kim" },
    { id: 2, name: "lee" },
    { id: 3, name: "park" },
  ]);
});

// STEP 6 실습: CPU 부하 발생용 (오토스케일링 트리거)
app.get("/stress", (req, res) => {
  let sum = 0;
  for (let i = 0; i < 5_000_000; i++) {
    sum += Math.sqrt(i);
  }
  res.json({ result: sum, hostname: os.hostname() });
});

app.listen(PORT, () => {
  console.log(`INFO  App started on :${PORT}`);
});
