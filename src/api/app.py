from fastapi import FastAPI, Depends, HTTPException, status, Request
from pydantic import BaseModel
from typing import Optional, List
import os
from supabase import create_client, Client

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") # For admin actions

if not SUPABASE_URL or not SUPABASE_ANON_KEY:
    raise ValueError("Supabase URL and Anon Key must be set as environment variables.")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)

app = FastAPI()

class TaskCreate(BaseModel):
    title: str
    description: Optional[str] = None
    due_date: Optional[str] = None # YYYY-MM-DD
    assigned_to: Optional[str] = None
    family_group_id: str

class TaskUpdate(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    due_date: Optional[str] = None
    assigned_to: Optional[str] = None
    is_completed: Optional[bool] = None

async def get_current_user(request: Request):
    token = request.headers.get('Authorization')
    if not token or not token.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )
    jwt_token = token.split(" ")[1]
    try:
        user_response = supabase.auth.get_user(jwt_token)
        if user_response.user:
            return user_response.user
        else:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=f"Authentication failed: {e}")

@app.get("/tasks", response_model=List[dict])
async def read_tasks(current_user: dict = Depends(get_current_user)):
    response = supabase.from('tasks').select('*').execute()
    if response.data:
        return response.data
    raise HTTPException(status_code=404, detail="Tasks not found")

@app.post("/tasks", response_model=dict, status_code=status.HTTP_201_CREATED)
async def create_task(task: TaskCreate, current_user: dict = Depends(get_current_user)):
    new_task_data = task.dict()
    new_task_data["created_by"] = current_user["id"]
    response = supabase.from('tasks').insert(new_task_data).execute()
    if response.data:
        return response.data[0]
    raise HTTPException(status_code=400, detail="Failed to create task")

@app.put("/tasks/{task_id}", response_model=dict)
async def update_task(task_id: str, task: TaskUpdate, current_user: dict = Depends(get_current_user)):
    response = supabase.from('tasks').update(task.dict(exclude_unset=True)).eq('id', task_id).execute()
    if response.data:
        return response.data[0]
    raise HTTPException(status_code=404, detail="Task not found or unauthorized")

@app.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_task(task_id: str, current_user: dict = Depends(get_current_user)):
    response = supabase.from('tasks').delete().eq('id', task_id).execute()
    if response.error:
        raise HTTPException(status_code=400, detail=response.error.message)
    return
