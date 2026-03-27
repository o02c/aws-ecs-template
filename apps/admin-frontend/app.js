const API_BASE = "/api";
const statusEl = document.getElementById("status");
const statsEl = document.getElementById("stats");

async function checkHealth() {
  try {
    const res = await fetch("/health");
    const data = await res.json();
    statusEl.textContent = `API Status: ${data.status} (${data.service})`;
    statusEl.className = "ok";
  } catch {
    statusEl.textContent = "API Status: unreachable";
    statusEl.className = "error";
  }
}

async function loadDashboard() {
  try {
    const res = await fetch(`${API_BASE}/dashboard`);
    const data = await res.json();
    statsEl.innerHTML = `
      <div class="stat">
        <div class="stat-value">${data.total_users}</div>
        <div class="stat-label">Total Users</div>
      </div>
      <div class="stat">
        <div class="stat-value">${data.active_sessions}</div>
        <div class="stat-label">Active Sessions</div>
      </div>
    `;
  } catch {
    statsEl.innerHTML = "<p>Failed to load dashboard</p>";
  }
}

checkHealth();
loadDashboard();
