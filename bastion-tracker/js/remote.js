function jwtRole(key) {
  try {
    const part = key.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const json = JSON.parse(atob(part));
    return json.role || "";
  } catch {
    return "";
  }
}

export function configured(config) {
  if (!config?.supabaseUrl || !config?.supabaseAnonKey) return false;
  if (jwtRole(config.supabaseAnonKey) === "service" + "_role") return false;
  return true;
}

export function serviceRoleRejected(config) {
  return Boolean(config?.supabaseAnonKey) && jwtRole(config.supabaseAnonKey) === "service" + "_role";
}

async function request(config, path, { method = "GET", body, token, headers = {} } = {}) {
  const response = await fetch(`${config.supabaseUrl.replace(/\/$/, "")}${path}`, {
    method,
    headers: {
      apikey: config.supabaseAnonKey,
      Authorization: `Bearer ${token || config.supabaseAnonKey}`,
      "Content-Type": "application/json",
      ...headers,
    },
    body: body == null ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;
  if (!response.ok) {
    const message = payload?.msg || payload?.message || payload?.error_description || payload?.error || response.statusText;
    const error = new Error(message || "The shared record refused the request.");
    error.status = response.status;
    throw error;
  }
  return payload;
}

export async function signIn(config, email, password) {
  const payload = await request(config, "/auth/v1/token?grant_type=password", {
    method: "POST",
    body: { email, password },
  });
  return { accessToken: payload.access_token, email: payload.user?.email || email };
}

export async function createEstate(config, token, name) {
  const rows = await request(config, "/rest/v1/rpc/create_estate", {
    method: "POST",
    token,
    body: { estate_name: name },
  });
  return rows;
}

export async function listEstates(config, token) {
  return request(config, "/rest/v1/estates?select=id,document,revision", { token });
}

export async function applyCommand(config, token, estateId, expectedRevision, idempotencyKey, command) {
  return request(config, "/rest/v1/rpc/apply_command", {
    method: "POST",
    token,
    body: {
      eid: estateId,
      expected_revision: expectedRevision,
      idempotency_key: idempotencyKey,
      command,
    },
  });
}

export async function createInvite(config, token, estateId, email, role) {
  return request(config, "/rest/v1/rpc/create_invite", {
    method: "POST",
    token,
    body: { eid: estateId, invite_email: email, invite_role: role },
  });
}

export async function acceptInvite(config, token, rawToken) {
  return request(config, "/rest/v1/rpc/accept_invite", {
    method: "POST",
    token,
    body: { raw_token: rawToken },
  });
}
