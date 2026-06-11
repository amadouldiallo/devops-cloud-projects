from fastapi import FastAPI, Form, Request
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/chat")
@limiter.limit("10/minute")
async def chat(request: Request, message: str = Form(...)):
    return {"reply": f"Tu as dit : {message}"}
