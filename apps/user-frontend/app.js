const API_BASE = "/api";
const statusEl = document.getElementById("status");
const userListEl = document.getElementById("user-list");

async function checkHealth() {
  try {
    const res = await fetch("/api/health");
    const data = await res.json();
    statusEl.textContent = `API Status: ${data.status} (${data.service})`;
    statusEl.className = "ok";
  } catch {
    statusEl.textContent = "API Status: unreachable";
    statusEl.className = "error";
  }
}

async function loadUsers() {
  try {
    const res = await fetch(`${API_BASE}/users`);
    const users = await res.json();
    userListEl.innerHTML = users
      .map((u) => `<li>${u.name} (ID: ${u.id})</li>`)
      .join("");
  } catch {
    userListEl.innerHTML = "<li>Failed to load users</li>";
  }
}

checkHealth();
loadUsers();
