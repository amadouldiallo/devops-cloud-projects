from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)


PAGE = """\
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <title>Projet 04 — Chat</title>
  <style>
    body { font-family: sans-serif; max-width: 32rem; margin: 3rem auto; padding: 0 1rem; }
    form { display: flex; gap: 0.5rem; }
    input { flex: 1; padding: 0.5rem; }
    button { padding: 0.5rem 1rem; }
    #reply { margin-top: 1rem; white-space: pre-wrap; }
  </style>
</head>
<body>
  <h1>Chat</h1>
  <form id="chat-form">
    <input type="text" name="message" placeholder="Votre message" required autofocus>
    <button type="submit">Envoyer</button>
  </form>
  <p id="reply"></p>
  <script>
    document.getElementById("chat-form").addEventListener("submit", async (e) => {
      e.preventDefault();
      const reply = document.getElementById("reply");
      const formData = new FormData(e.target);
      const res = await fetch("/chat", { method: "POST", body: formData });
      if (res.ok) {
        const data = await res.json();
        reply.textContent = data.reply;
      } else if (res.status === 429) {
        reply.textContent = "Trop de requêtes — réessaie dans une minute.";
      } else {
        reply.textContent = `Erreur ${res.status}`;
      }
    });
  </script>
</body>
</html>
"""


@app.get("/", response_class=HTMLResponse)
def index():
    return PAGE


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/chat")
@limiter.limit("10/minute")
async def chat(request: Request, message: str = Form(...)):
    return {"reply": f"Tu as dit : {message}"}
