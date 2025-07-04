import os
import uuid
from fastapi import FastAPI, HTTPException, status, Depends
from pydantic import BaseModel, Field
from typing import List, Optional
from azure.cosmos import CosmosClient, PartitionKey
from azure.cosmos.exceptions import CosmosResourceNotFoundError

# --- Configuration ---
COSMOS_ENDPOINT = os.environ["COSMOS_ENDPOINT"]
COSMOS_KEY = os.environ["COSMOS_KEY"]
COSMOS_DATABASE_NAME = os.environ["COSMOS_DATABASE_NAME"]
COSMOS_CONTAINER_NAME = os.environ["COSMOS_CONTAINER_NAME"]

# --- Pydantic Models ---
class Task(BaseModel):
    task_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    title: str
    description: Optional[str] = None
    due_date: Optional[str] = None
    assigned_to: Optional[str] = None
    is_completed: bool = False
    created_by: str

class FamilyMember(BaseModel):
    user_id: str
    email: str
    role: str = 'member'

class FamilyGroup(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    created_by: str
    members: List[FamilyMember] = []
    tasks: List[Task] = []

# --- FastAPI App ---
app = FastAPI()

# --- Cosmos DB Client ---
# Initialize the Cosmos client
cosmos_client = CosmosClient(url=COSMOS_ENDPOINT, credential=COSMOS_KEY)
database = cosmos_client.get_database_client(COSMOS_DATABASE_NAME)
container = database.get_container_client(COSMOS_CONTAINER_NAME)

# --- API Endpoints ---

@app.post("/family", response_model=FamilyGroup, status_code=status.HTTP_201_CREATED)
async def create_family_group(family: FamilyGroup):
    """Creates a new family group."""
    container.create_item(body=family.dict())
    return family

@app.get("/family/{family_id}", response_model=FamilyGroup)
async def get_family_group(family_id: str):
    """Retrieves a family group by its ID."""
    try:
        family_document = container.read_item(item=family_id, partition_key=family_id)
        return family_document
    except CosmosResourceNotFoundError:
        raise HTTPException(status_code=404, detail="Family group not found")

@app.post("/family/{family_id}/tasks", response_model=Task)
async def add_task_to_family(family_id: str, task: Task):
    """Adds a new task to a specific family group."""
    try:
        family_document = container.read_item(item=family_id, partition_key=family_id)
        family_document['tasks'].append(task.dict())
        container.upsert_item(body=family_document)
        return task
    except CosmosResourceNotFoundError:
        raise HTTPException(status_code=404, detail="Family group not found")

@app.get("/family/{family_id}/tasks", response_model=List[Task])
async def get_family_tasks(family_id: str):
    """Gets all tasks for a specific family group."""
    family_document = await get_family_group(family_id)
    return family_document['tasks']

@app.put("/family/{family_id}/tasks/{task_id}", response_model=Task)
async def update_family_task(family_id: str, task_id: str, updated_task: Task):
    """Updates a specific task within a family group."""
    try:
        family_document = container.read_item(item=family_id, partition_key=family_id)
        tasks = family_document.get('tasks', [])
        task_found = False
        for i, task in enumerate(tasks):
            if task['task_id'] == task_id:
                tasks[i] = updated_task.dict()
                task_found = True
                break
        
        if not task_found:
            raise HTTPException(status_code=404, detail="Task not found")

        container.upsert_item(body=family_document)
        return updated_task
    except CosmosResourceNotFoundError:
        raise HTTPException(status_code=404, detail="Family group not found")

@app.delete("/family/{family_id}/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_family_task(family_id: str, task_id: str):
    """Deletes a task from a family group."""
    try:
        family_document = container.read_item(item=family_id, partition_key=family_id)
        tasks = family_document.get('tasks', [])
        initial_task_count = len(tasks)

        family_document['tasks'] = [t for t in tasks if t['task_id'] != task_id]

        if len(family_document['tasks']) == initial_task_count:
            raise HTTPException(status_code=404, detail="Task not found")

        container.upsert_item(body=family_document)
        return
    except CosmosResourceNotFoundError:
        raise HTTPException(status_code=404, detail="Family group not found")