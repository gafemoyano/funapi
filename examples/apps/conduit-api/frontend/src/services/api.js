// API service for Conduit backend

const API_URL = '/api';

// Get stored token
const getToken = () => localStorage.getItem('token');

// Set token
const setToken = (token) => localStorage.setItem('token', token);

// Clear token
const clearToken = () => localStorage.removeItem('token');

// Base request function
async function request(method, endpoint, body = null) {
  const headers = {
    'Content-Type': 'application/json',
  };

  const token = getToken();
  if (token) {
    headers['Authorization'] = `Token ${token}`;
  }

  const options = {
    method,
    headers,
  };

  if (body) {
    options.body = JSON.stringify(body);
  }

  const response = await fetch(`${API_URL}${endpoint}`, options);

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.detail || 'Request failed');
  }

  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

// Auth API
export const auth = {
  register: (user) => request('POST', '/users', { user }).then(data => {
    setToken(data.user.token);
    return data.user;
  }),

  login: (user) => request('POST', '/users/login', { user }).then(data => {
    setToken(data.user.token);
    return data.user;
  }),

  getCurrentUser: () => request('GET', '/user').then(data => data.user),

  updateUser: (user) => request('PUT', '/user', { user }).then(data => data.user),

  logout: () => {
    clearToken();
  }
};

// Articles API
export const articles = {
  list: (params = {}) => {
    const query = new URLSearchParams(params).toString();
    return request('GET', `/articles${query ? '?' + query : ''}`).then(data => data);
  },

  feed: () => request('GET', '/articles/feed').then(data => data),

  get: (slug) => request('GET', `/articles/${slug}`).then(data => data.article),

  create: (article) => request('POST', '/articles', { article }).then(data => data.article),

  update: (slug, article) => request('PUT', `/articles/${slug}`, { article }).then(data => data.article),

  delete: (slug) => request('DELETE', `/articles/${slug}`),

  favorite: (slug) => request('POST', `/articles/${slug}/favorite`).then(data => data.article),

  unfavorite: (slug) => request('DELETE', `/articles/${slug}/favorite`).then(data => data.article),
};

// Comments API
export const comments = {
  list: (slug) => request('GET', `/articles/${slug}/comments`).then(data => data.comments),

  create: (slug, comment) => request('POST', `/articles/${slug}/comments`, { comment }).then(data => data.comment),

  delete: (slug, id) => request('DELETE', `/articles/${slug}/comments/${id}`),
};

// Profile API
export const profiles = {
  get: (username) => request('GET', `/profiles/${username}`).then(data => data.profile),

  follow: (username) => request('POST', `/profiles/${username}/follow`).then(data => data.profile),

  unfollow: (username) => request('DELETE', `/profiles/${username}/follow`).then(data => data.profile),
};

// Tags API
export const tags = {
  list: () => request('GET', '/tags').then(data => data.tags),
};

export { getToken, setToken, clearToken };
