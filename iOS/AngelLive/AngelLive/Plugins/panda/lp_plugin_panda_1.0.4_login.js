const _panda_loginPlatformId = "panda";
const _panda_loginUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36";
const _panda_loginRuntime = {
  credentialSynced: false,
  credentialStatus: {
    state: "missing",
    expireAt: 0,
    userId: "",
    userName: "",
    message: ""
  }
};

function _panda_loginTrim(value) {
  return value === undefined || value === null ? "" : String(value).trim();
}

function _panda_loginToNumber(value, defaultValue) {
  if (value === null || value === undefined || value === "") return defaultValue;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : defaultValue;
}

function _panda_loginBuildCredentialStatus(status) {
  const source = status && typeof status === "object" ? status : {};
  return {
    state: _panda_loginTrim(source.state) || "unknown",
    expireAt: _panda_loginToNumber(source.expireAt, 0),
    userId: _panda_loginTrim(source.userId),
    userName: _panda_loginTrim(source.userName),
    message: _panda_loginTrim(source.message)
  };
}

function _panda_loginSetCredentialStatus(status) {
  _panda_loginRuntime.credentialStatus = _panda_loginBuildCredentialStatus(status);
  return _panda_loginGetCredentialStatusSnapshot();
}

function _panda_loginGetCredentialStatusSnapshot() {
  return _panda_loginBuildCredentialStatus(_panda_loginRuntime.credentialStatus);
}

function _panda_loginParseJSON(text, fallback) {
  try {
    return JSON.parse(text === undefined || text === null ? "{}" : String(text));
  } catch (e) {
    return fallback === undefined ? null : fallback;
  }
}

function _panda_loginMarkSynced(message) {
  _panda_loginRuntime.credentialSynced = true;
  return _panda_loginSetCredentialStatus({
    state: "unknown",
    expireAt: 0,
    userId: "",
    userName: "",
    message: _panda_loginTrim(message) || "credential synced; validation pending"
  });
}

function _panda_loginMarkCleared() {
  _panda_loginRuntime.credentialSynced = false;
  return _panda_loginSetCredentialStatus({
    state: "missing",
    expireAt: 0,
    userId: "",
    userName: "",
    message: ""
  });
}

async function _panda_loginRequest(request, authMode) {
  return await Host.http.request({
    platformId: _panda_loginPlatformId,
    authMode: authMode || "none",
    request: request || {}
  });
}

function _panda_loginReadCookieHeader() {
  if (globalThis.Host && Host.session && typeof Host.session.getCookieHeader === "function") {
    return _panda_loginTrim(Host.session.getCookieHeader(_panda_loginPlatformId));
  }
  return "";
}

function _panda_loginReadCookieValue(cookieHeader, name) {
  const cookie = _panda_loginTrim(cookieHeader);
  const target = _panda_loginTrim(name);
  if (!cookie || !target) return "";
  const parts = cookie.split(";");
  for (const part of parts) {
    const segment = _panda_loginTrim(part);
    if (!segment) continue;
    const index = segment.indexOf("=");
    const key = index >= 0 ? segment.slice(0, index).trim() : segment;
    const value = index >= 0 ? segment.slice(index + 1).trim() : "";
    if (key === target) return value;
  }
  return "";
}

function _panda_loginPickFirst(values) {
  for (const value of values || []) {
    const text = _panda_loginTrim(value);
    if (text) return text;
  }
  return "";
}

function _panda_loginHasSignalCookie(cookieHeader) {
  return !!_panda_loginReadCookieValue(cookieHeader, "sessKey");
}

function _panda_loginAuthFailureStatus(httpCode, obj, hasCredential) {
  const loginInfo = obj && typeof obj.loginInfo === "object" ? obj.loginInfo : {};
  const userInfo = loginInfo && typeof loginInfo.userInfo === "object" ? loginInfo.userInfo : {};
  const message = _panda_loginPickFirst([
    obj && obj.message,
    obj && obj.error,
    obj && obj.error_message,
    loginInfo && loginInfo.message
  ]);
  if (httpCode === 429) {
    return {
      state: "risk_control",
      message: message || "panda credential blocked by risk control"
    };
  }
  if (httpCode === 401 || httpCode === 403 || userInfo.isLogin === false) {
    return {
      state: hasCredential ? "expired" : "missing",
      message: message || "panda login required"
    };
  }
  return {
    state: hasCredential ? "invalid" : "missing",
    message: message || "panda credential validation failed"
  };
}

async function _panda_loginValidateCredential() {
  const hasCredential = !!_panda_loginRuntime.credentialSynced;
  const cookieHeader = _panda_loginReadCookieHeader();
  if (!_panda_loginHasSignalCookie(cookieHeader)) {
    return _panda_loginSetCredentialStatus({
      state: "missing",
      expireAt: 0,
      userId: "",
      userName: "",
      message: "panda sessKey cookie not present in host vault"
    });
  }

  const resp = await _panda_loginRequest({
    url: "https://api.pandalive.co.kr/v1/member/login_info",
    method: "GET",
    headers: {
      "Accept": "application/json, text/plain, */*",
      "Referer": "https://www.pandalive.co.kr/",
      "Origin": "https://www.pandalive.co.kr",
      "User-Agent": _panda_loginUA
    },
    timeout: 15
  }, "platform_cookie");

  const httpCode = _panda_loginToNumber(resp && (resp.statusCode || resp.status), 0);
  const obj = _panda_loginParseJSON(resp && resp.bodyText, {}) || {};
  const loginInfo = obj && typeof obj.loginInfo === "object" ? obj.loginInfo : {};
  const userInfo = loginInfo && typeof loginInfo.userInfo === "object" ? loginInfo.userInfo : {};
  const isLogin = userInfo.isLogin === true || _panda_loginToNumber(userInfo.isLogin, 0) === 1;
  const userId = _panda_loginPickFirst([userInfo.id, userInfo.userId, userInfo.idx, userInfo.userIdx]);
  const userName = _panda_loginPickFirst([userInfo.nick, userInfo.nickname, userInfo.userNick, userInfo.id]);

  if (httpCode >= 400 || obj.result === false || !isLogin || !userId) {
    const failure = _panda_loginAuthFailureStatus(httpCode, obj, hasCredential);
    return _panda_loginSetCredentialStatus({
      state: failure.state,
      expireAt: 0,
      userId: userId,
      userName: userName,
      message: failure.message
    });
  }

  return _panda_loginSetCredentialStatus({
    state: "valid",
    expireAt: 0,
    userId: userId,
    userName: userName,
    message: ""
  });
}

async function _panda_loginSetCookie() {
  _panda_loginMarkSynced("cookie synced from host");
  return { ok: true };
}

async function _panda_loginClearCookie() {
  _panda_loginMarkCleared();
  return { ok: true };
}

async function _panda_loginSetCredential() {
  const status = _panda_loginMarkSynced("credential synced from host");
  return Object.assign({ ok: true }, status);
}

async function _panda_loginClearCredential() {
  const status = _panda_loginMarkCleared();
  return Object.assign({ ok: true }, status);
}

async function _panda_loginGetCredentialStatus() {
  return _panda_loginGetCredentialStatusSnapshot();
}

globalThis.__lp_plugin_panda_1_0_4_login = {
  request: _panda_loginRequest,
  setCookie: _panda_loginSetCookie,
  clearCookie: _panda_loginClearCookie,
  setCredential: _panda_loginSetCredential,
  clearCredential: _panda_loginClearCredential,
  getCredentialStatus: _panda_loginGetCredentialStatus,
  validateCredential: _panda_loginValidateCredential
};
