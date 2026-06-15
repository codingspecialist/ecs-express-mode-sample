const express = require("express");
const os = require("os");

const app = express();
const PORT = process.env.PORT || 8080;

// 인증 서버 — ALB가 /auth* 경로를 이 서버로 보냅니다
app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

app.get("/auth", (req, res) => {
  res.json({ server: "auth-server", hostname: os.hostname() });
});

// 로그인 (데모용 가짜 토큰)
app.get("/auth/login", (req, res) => {
  const user = req.query.user || "guest";
  res.json({ user, token: `fake-token-for-${user}` });
});

// 토큰 검증 (데모용 — 항상 ok)
app.get("/auth/verify", (req, res) => {
  res.json({ valid: true });
});

app.listen(PORT, () => console.log(`INFO  auth-server started on :${PORT}`));
