from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def home():
    return {"service": "nomad-backend", "status": "running"}

@app.get("/data")
def data():
    return {"message": "Hello from backend"}