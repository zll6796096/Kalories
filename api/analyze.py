import os
import io
import base64
import json
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from google import genai
from google.genai import types
from dotenv import load_dotenv

# Load environment variables from frontend .env or local
env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
load_dotenv(env_path)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class AnalyzeRequest(BaseModel):
    image: str

class AnalyzeResponse(BaseModel):
    name: str = Field(description="食物名称")
    calories: int = Field(description="预估热量 (千卡)")
    protein: int = Field(description="蛋白质含量 (克)")
    carbs: int = Field(description="碳水化合物含量 (克)")
    fat: int = Field(description="脂肪含量 (克)")

@app.post("/api/analyze", response_model=AnalyzeResponse)
@app.post("/", response_model=AnalyzeResponse)
async def analyze_food(request: AnalyzeRequest):
    try:
        if not os.environ.get("GEMINI_API_KEY"):
            raise HTTPException(status_code=500, detail="GEMINI_API_KEY environment variable not set")
            
        # Extract base64 part
        if "," in request.image:
            base64_data = request.image.split(",")[1]
            mime_type = request.image.split(";")[0].split(":")[1]
        else:
            base64_data = request.image
            mime_type = "image/jpeg"
            
        file_bytes = base64.b64decode(base64_data)
        
        client = genai.Client()
        prompt = "分析图片中的食物，如果识别成功，返回这道菜的名称、热量（kcal）、蛋白质（g）、碳水化合物（g）、脂肪（g）。如果是多种食物，可以估算总和或者主要部分的数值。"
        
        response = client.models.generate_content(
            model='gemini-1.5-flash',
            contents=[
                types.Part.from_bytes(
                    data=file_bytes,
                    mime_type=mime_type,
                ),
                prompt,
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=AnalyzeResponse,
                temperature=0.1,
            ),
        )
        
        if response.parsed:
            return response.parsed
        else:
            return json.loads(response.text)
            
    except Exception as e:
        print(f"Error during analysis: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
