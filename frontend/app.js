// Backend URL — in this compose setup, the browser hits the host port
// that is mapped to the backend container (see app-stack/docker-compose.yaml)
const API_BASE = window.location.protocol + "//" + window.location.hostname + ":5000";

async function loadItems() {
  const res = await fetch(`${API_BASE}/items`);
  const items = await res.json();
  const list = document.getElementById("list");
  list.innerHTML = "";
  items.forEach((item) => {
    const li = document.createElement("li");
    li.textContent = `${item.id}: ${item.name}`;
    list.appendChild(li);
  });
}

async function addItem() {
  const input = document.getElementById("name");
  const name = input.value.trim();
  if (!name) return;
  await fetch(`${API_BASE}/items`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name }),
  });
  input.value = "";
  loadItems();
}

loadItems();
