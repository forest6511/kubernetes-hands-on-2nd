// 画面の動き。データはすべて /api/ 経由で todo-api から取る
const list = document.getElementById("todos");
const errorBox = document.getElementById("error");

function showError(message) {
  errorBox.textContent = message;
  errorBox.hidden = false;
}

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    throw new Error(`${method} ${path}: ${res.status}`);
  }
  return res.status === 204 ? null : res.json();
}

async function load() {
  try {
    const config = await api("GET", "/api/config");
    document.getElementById("title").textContent = config.title;
    document.title = config.title;
    const todos = await api("GET", "/api/todos");
    list.replaceChildren(...todos.map(render));
    errorBox.hidden = true;
  } catch (e) {
    showError(`API に届きません（${e.message}）`);
  }
}

function render(todo) {
  const li = document.createElement("li");
  const box = document.createElement("input");
  box.type = "checkbox";
  box.checked = todo.done;
  box.onchange = () => api("PATCH", `/api/todos/${todo.id}`, { done: box.checked }).then(load, (e) => showError(e.message));
  const label = document.createElement("span");
  label.textContent = todo.title;
  if (todo.done) label.className = "done";
  const del = document.createElement("button");
  del.textContent = "削除";
  del.onclick = () => api("DELETE", `/api/todos/${todo.id}`).then(load, (e) => showError(e.message));
  li.append(box, label, del);
  return li;
}

document.getElementById("add").onsubmit = async (event) => {
  event.preventDefault();
  const input = document.getElementById("new-title");
  try {
    await api("POST", "/api/todos", { title: input.value });
    input.value = "";
    load();
  } catch (e) {
    showError(`追加できません（${e.message}）`);
  }
};

load();
